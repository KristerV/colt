defmodule Colt.Services.Sending.CategorizeReply do
  @moduledoc """
  Classify one InboundEmail into `:ooo | :interested | :not_interested |
  :other` via Claude 4.5 Sonnet and write the category back.

  A real reply (`:interested | :not_interested | :other`) marks the contact
  replied and halts the sequence — a human takes over. An out-of-office
  auto-reply (`:ooo`) is NOT a real reply: the prospect hasn't read the email,
  so instead of halting we defer the next follow-up. The AI extracts the
  return date and the next send is pushed to 3 days after it (or +7 days when
  no date is stated). If the inbox keeps auto-replying, each OOO defers again
  until the sequence exhausts itself.

  Confidence floor: model outputs with `confidence < 0.7` are forced to
  `:other` regardless of label (per §12).
  """

  require Logger

  alias Colt.Resources.{CampaignContact, InboundEmail}
  alias Colt.Services.Ai.Complete
  alias Colt.Services.Sales.RecordStatusEvent

  alias Colt.Services.Sending.{
    Broadcast,
    DeferFollowup,
    ExtractOooReturn,
    HaltSequence,
    InjectOooWelcomeBack
  }

  @confidence_floor 0.7
  @valid_categories ~w(ooo interested not_interested other)

  # No usable return date in the OOO reply → defer the next send by this many days.
  @no_date_defer_days 7
  # Send the next follow-up this many days after the stated return date.
  @after_return_days 3

  def run(inbound_id) when is_binary(inbound_id) do
    with {:ok, inbound} <- load(inbound_id),
         {:ok, {category, confidence}} <- classify(inbound),
         {:ok, _} <- InboundEmail.set_reply_category(inbound, category, authorize?: false),
         {:ok, contact} <- contact_for(inbound) do
      handle(category, confidence, inbound, contact)
    end
  end

  # OOO: keep the contact active. If the template carries an admin-authored
  # welcome-back email (golden, position -1), send it at return+3d and resume
  # the follow-ups behind it. Otherwise just push the next follow-up out. The
  # reschedule is persisted; the sending funnel reflects the new send time on
  # its next load (no live broadcast — the contact never leaves :sending).
  defp handle(:ooo, _confidence, inbound, contact) do
    not_before = ooo_not_before(inbound)

    case InjectOooWelcomeBack.run(inbound.thread_id, contact, not_before) do
      {:ok, :no_welcome_back} ->
        with {:ok, result} <- DeferFollowup.run(inbound.thread_id, not_before) do
          {:ok, %{category: :ooo, deferred: result}}
        end

      {:ok, injected} ->
        {:ok, %{category: :ooo, ooo_injected: injected}}
    end
  end

  # Real reply: mark replied + stop the sequence so a human takes over.
  defp handle(category, confidence, inbound, contact) do
    with {:ok, _} <- CampaignContact.mark_replied(contact, category, authorize?: false),
         {:ok, halted} <- HaltSequence.run(inbound.thread_id) do
      campaign_id = contact.campaign_id

      RecordStatusEvent.run(inbound.thread_id, :reply_category, nil, category_label(category),
        reason: classified_reason(category, confidence)
      )

      Broadcast.reply_categorized(campaign_id, contact.id, category)
      Broadcast.sequence_halted(campaign_id, contact.id, :reply)
      {:ok, %{category: category, halted_count: halted}}
    end
  end

  defp category_label(:interested), do: "interested"
  defp category_label(:not_interested), do: "not interested"
  defp category_label(:other), do: "other"
  defp category_label(:ooo), do: "out of office"
  defp category_label(other), do: to_string(other)

  defp classified_reason(category, confidence) when is_number(confidence) do
    "classified as #{category_label(category)} (#{:erlang.float_to_binary(confidence * 1.0, decimals: 2)})"
  end

  defp classified_reason(category, _), do: "classified as #{category_label(category)}"

  defp ooo_not_before(inbound) do
    case ExtractOooReturn.run(inbound) do
      {:ok, %Date{} = return_date} -> defer_not_before(return_date)
      _ -> defer_not_before(nil)
    end
  end

  @doc """
  Lower bound for the next follow-up after an OOO: `#{@after_return_days}` days
  after a known return date, else `#{@no_date_defer_days}` days from now.
  Public so the scheduling rule is unit-testable without the AI step.
  """
  def defer_not_before(%Date{} = return_date) do
    return_date |> Date.add(@after_return_days) |> start_of_day_utc()
  end

  def defer_not_before(nil) do
    DateTime.add(DateTime.utc_now(), @no_date_defer_days * 86_400, :second)
  end

  defp start_of_day_utc(%Date{} = date) do
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp load(inbound_id) do
    Ash.get(InboundEmail, inbound_id,
      load: [thread: [campaign_contact: [:campaign, :person]]],
      authorize?: false
    )
  end

  defp contact_for(%InboundEmail{thread: %{campaign_contact: %CampaignContact{} = c}}),
    do: {:ok, c}

  defp contact_for(_), do: {:error, :no_contact}

  # ── Classification ──────────────────────────────────────────────────

  defp classify(inbound) do
    subject = inbound.subject || ""
    body = (inbound.body || "") |> strip_html() |> String.slice(0, 4000)
    from = inbound.from_address || "unknown"

    user_message = """
    Classify the reply below. Categories:
      - ooo: out-of-office / vacation auto-reply
      - interested: positive intent, wants more info, agrees to a meeting
      - not_interested: explicit decline / unsubscribe / hostile
      - other: unclear, off-topic, requires human review

    Reply JSON only: {"category": "...", "confidence": 0.0-1.0, "reason": "..."}.

    From: #{from}
    Subject: #{subject}
    Body:
    #{body}
    """

    case Complete.run(:smart, user_message,
           system: classifier_system(),
           response_format: :json,
           schema: response_schema(),
           temperature: 0.0,
           task: "reply_categorize",
           subject: {:inbound_email, inbound.id}
         ) do
      {:ok, %{content: %{} = json}} ->
        {:ok, coerce(json)}

      {:ok, other} ->
        Logger.warning("categorize_reply: unexpected complete response #{inspect(other)}")
        {:ok, {:other, nil}}

      {:error, reason} ->
        Logger.warning("categorize_reply: ai error #{inspect(reason)} — defaulting :other")
        {:ok, {:other, nil}}
    end
  end

  defp response_schema do
    %{
      type: "object",
      additionalProperties: false,
      required: ["category", "confidence", "reason"],
      properties: %{
        category: %{
          type: "string",
          enum: ["ooo", "interested", "not_interested", "other"]
        },
        confidence: %{type: "number"},
        reason: %{type: "string"}
      }
    }
  end

  defp classifier_system do
    """
    You are a precise classifier for cold-outreach replies. Output strict
    JSON with exactly these keys: category, confidence, reason. Categories
    are: ooo, interested, not_interested, other. Be conservative — if the
    intent is ambiguous, return "other".
    """
  end

  defp coerce(json) do
    label = json |> Map.get("category", "other") |> to_string() |> String.downcase()
    confidence = json |> Map.get("confidence", 0) |> to_float()

    cond do
      label not in @valid_categories -> {:other, confidence}
      confidence < @confidence_floor -> {:other, confidence}
      true -> {String.to_existing_atom(label), confidence}
    end
  end

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r{<br\s*/?>}i, "\n")
    |> String.replace(~r{<[^>]+>}, "")
    |> String.replace(~r{[ \t]+\n}, "\n")
  end

  defp strip_html(_), do: ""
end
