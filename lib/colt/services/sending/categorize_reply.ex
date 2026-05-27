defmodule Colt.Services.Sending.CategorizeReply do
  @moduledoc """
  Classify one InboundEmail into `:ooo | :interested | :not_interested |
  :other` via Claude 4.5 Sonnet, write the category back, and halt the
  contact's sequence.

  Confidence floor: model outputs with `confidence < 0.7` are forced to
  `:other` regardless of label (per §12).
  """

  require Logger

  alias Colt.Resources.{CampaignContact, InboundEmail}
  alias Colt.Services.Ai.Complete
  alias Colt.Services.Sending.{Broadcast, HaltSequence}

  @confidence_floor 0.7
  @valid_categories ~w(ooo interested not_interested other)

  def run(inbound_id) when is_binary(inbound_id) do
    with {:ok, inbound} <- load(inbound_id),
         {:ok, category} <- classify(inbound),
         {:ok, _} <- InboundEmail.set_reply_category(inbound, category, authorize?: false),
         {:ok, contact} <- contact_for(inbound),
         {:ok, _} <- CampaignContact.mark_replied(contact, category, authorize?: false),
         {:ok, halted} <- HaltSequence.run(inbound.thread_id) do
      campaign_id = contact.campaign_id
      Broadcast.reply_categorized(campaign_id, contact.id, category)
      Broadcast.sequence_halted(campaign_id, contact.id, :reply)
      {:ok, %{category: category, halted_count: halted}}
    end
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
           max_tokens: 256,
           task: "reply_categorize",
           subject: {:inbound_email, inbound.id}
         ) do
      {:ok, %{content: %{} = json}} ->
        {:ok, coerce(json)}

      {:ok, other} ->
        Logger.warning("categorize_reply: unexpected complete response #{inspect(other)}")
        {:ok, :other}

      {:error, reason} ->
        Logger.warning("categorize_reply: ai error #{inspect(reason)} — defaulting :other")
        {:ok, :other}
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
      label not in @valid_categories -> :other
      confidence < @confidence_floor -> :other
      true -> String.to_existing_atom(label)
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
