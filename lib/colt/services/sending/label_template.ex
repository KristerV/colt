defmodule Colt.Services.Sending.LabelTemplate do
  @moduledoc """
  Classify one opener into an outreach *template* — a whole approach, not a
  style or wording variant (§6.2 learning loop).

  A template is defined by two axes:

    * **angle** — the premise / reason for reaching out (the point the
      subject makes).
    * **ask** — the call to action.

  Two openers are the *same* template when both axes match, regardless of
  wording, personalization, or company specifics. A *new* template is
  warranted only when the angle or the ask is a deliberate different bet —
  a new experiment, not a reword. The bias is strongly toward reusing an
  existing label; novelty must be justified by a differing axis.

  Scope is per-campaign. Run after a contact is approved, against the
  opener's effective (user_? || ai_?) content.

      iex> Colt.Services.Sending.LabelTemplate.run(opener, actor: actor)
  """

  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Ai.Complete

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["label", "angle", "ask", "offer"],
    properties: %{
      label: %{type: "string", description: "Short kebab-case template name."},
      angle: %{type: "string", description: "The premise / reason for reaching out."},
      ask: %{type: "string", description: "The call to action."},
      offer: %{type: "string", description: "The carrot / value framing."}
    }
  }

  def run(opener, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, subject, body} <- effective_content(opener),
         {:ok, existing} <- load_existing(opener, actor),
         {:ok, prompt} <- build_prompt(existing, subject, body),
         {:ok, label} <- call_model(prompt, opener),
         {:ok, updated} <- persist(opener, label, actor) do
      {:ok, updated}
    end
  end

  defp effective_content(%{step_position: 0} = email) do
    subject = email.user_subject || email.ai_subject
    body = email.user_body || email.ai_body

    if blank?(subject) and blank?(body) do
      {:error, :empty_opener}
    else
      {:ok, subject, body}
    end
  end

  defp effective_content(_), do: {:error, :not_an_opener}

  defp load_existing(opener, actor) do
    campaign_id =
      opener.thread && opener.thread.campaign_contact &&
        opener.thread.campaign_contact.campaign_id

    case campaign_id do
      nil ->
        {:ok, []}

      cid ->
        rows =
          OutboundEmail.list_labeled_openers_for_campaign!(cid,
            actor: actor,
            authorize?: actor != nil
          )
          |> Enum.reject(&(&1.id == opener.id))

        # One representative opener per distinct template (newest first; rows
        # already arrive inserted_at desc).
        existing =
          rows
          |> Enum.group_by(& &1.template_label)
          |> Enum.map(fn {label, [example | _]} ->
            %{
              label: label,
              angle: example.template_angle,
              ask: example.template_ask,
              offer: example.template_offer,
              subject: example.user_subject || example.ai_subject,
              body: example.user_body || example.ai_body
            }
          end)

        {:ok, existing}
    end
  end

  defp build_prompt(existing, subject, body) do
    system = """
    You sort cold-outreach openers into "templates". A template is a whole
    approach, defined by two axes:
      - angle: the premise / reason for reaching out (the point the subject makes)
      - ask: the call to action

    Rules:
    - Two openers are the SAME template if both angle AND ask match, even when
      the wording, personalization, or company details differ entirely.
    - Only call something a NEW template if the angle OR the ask is a deliberate
      different bet — a new experiment, not a reworded version of the same idea.
    - Bias hard toward reusing an existing label. If you propose a new one, it
      must be because a specific axis differs; if you can't name the differing
      axis, reuse instead.
    - When only one template exists, the bar for a second is the same: a
      different angle or ask, not a reword.

    Return JSON: the chosen label (reuse an existing one verbatim, or a new
    short kebab-case name) and the angle/ask/offer you read from this opener.
    """

    user = """
    #{existing_block(existing)}

    Classify this opener:
    Subject: #{subject}
    Body:
    #{body}
    """

    {:ok, %{system: system, user: user}}
  end

  defp existing_block([]) do
    "No templates exist yet for this campaign — this opener defines the first one."
  end

  defp existing_block(existing) do
    rendered =
      existing
      |> Enum.with_index(1)
      |> Enum.map(fn {t, i} ->
        """
        #{i}. label: #{t.label}
           angle: #{t.angle}
           ask: #{t.ask}
           offer: #{t.offer}
           example subject: #{t.subject}
           example body:
        #{indent(t.body || "")}
        """
      end)
      |> Enum.join("\n")

    """
    Existing templates in this campaign (reuse a label if the angle and ask match):
    #{rendered}
    """
  end

  defp call_model(prompt, opener) do
    case Complete.run(:smart, prompt.user,
           system: prompt.system,
           response_format: :json,
           schema: @schema,
           temperature: 0.0,
           max_tokens: 500,
           task: :template_label,
           subject: {:outbound_email, opener.id}
         ) do
      {:ok, %{content: %{"label" => label} = c}} when is_binary(label) and label != "" ->
        {:ok,
         %{
           label: label,
           angle: Map.get(c, "angle"),
           ask: Map.get(c, "ask"),
           offer: Map.get(c, "offer")
         }}

      {:ok, _other} ->
        {:error, :label_invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(opener, label, actor) do
    OutboundEmail.update_template(opener, label.label, label.angle, label.ask, label.offer,
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map(&("    " <> &1))
    |> Enum.join("\n")
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
end
