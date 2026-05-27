defmodule Colt.Services.Sending.EmailWriter do
  @moduledoc """
  Claude 4.5 Sonnet writes the full sequence of drafts for one contact.

  Input: a `CampaignContact` (id or struct).
  Output: `{:ok, %{steps: [%{position, subject, body}], emails: [...]}}` —
  one `:drafted` Email is persisted per email step on the contact's
  thread, populating ai_* / user_* / final_* fields.

  Phase E3: no few-shot examples yet. The prompt includes the sequence
  skeleton (positions + delays + terminal action) so the model can
  reference followup timing naturally. Example collection lands in E9.
  """

  alias Colt.Resources.{CampaignContact, OutboundEmail, Pitch, Sequence, Thread}
  alias Colt.Services.Ai.Complete

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["steps"],
    properties: %{
      steps: %{
        type: "array",
        items: %{
          type: "object",
          additionalProperties: false,
          required: ["position", "subject", "body"],
          properties: %{
            position: %{type: "integer"},
            subject: %{type: "string"},
            body: %{type: "string"}
          }
        }
      }
    }
  }

  def run(contact_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <- load_contact(contact_or_id, actor),
         {:ok, ctx} <- load_context(contact, actor),
         {:ok, prompt} <- build_prompt(ctx),
         {:ok, ai_steps} <- call_model(prompt, ctx),
         {:ok, emails} <- persist(ctx, ai_steps, actor) do
      {:ok, %{steps: ai_steps, emails: emails}}
    end
  end

  defp load_contact(%CampaignContact{} = c, _actor), do: {:ok, c}

  defp load_contact(id, actor) when is_binary(id) do
    Ash.get(CampaignContact, id,
      load: [:person, :thread, campaign: [:sequence]],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_context(contact, actor) do
    contact =
      Ash.load!(contact, [person: [:company], thread: []],
        actor: actor,
        authorize?: actor != nil
      )

    sequence =
      Sequence.get_for_campaign!(contact.campaign_id,
        load: [:sequence_steps],
        actor: actor,
        authorize?: actor != nil
      )

    thread =
      contact.thread ||
        Thread.create_for_contact!(contact.id, actor: actor, authorize?: actor != nil)

    pitch =
      case Pitch.get_for_campaign(contact.campaign_id, actor: actor, authorize?: actor != nil) do
        {:ok, p} -> p
        _ -> nil
      end

    {:ok,
     %{
       contact: contact,
       person: contact.person,
       company: contact.person && contact.person.company,
       sequence: sequence,
       email_steps: Enum.filter(sequence.sequence_steps, &(&1.kind == :email)),
       all_steps: sequence.sequence_steps,
       thread: thread,
       language: sequence.language,
       pitch: pitch
     }}
  end

  defp build_prompt(ctx) do
    system = """
    You are a cold-outreach writer composing a multi-step email sequence
    in #{language_name(ctx.language)}. Mimic the user's natural tone —
    plain, direct, no marketing fluff. Output plain text only; no
    Markdown, no HTML, no signatures (the inbox appends those).

    Sequence rules:
    - Step 1 opens cold; introduce yourself briefly and state the reason
      for reaching out tied to the recipient's role and company.
    - Followup steps reference the previous email obliquely; do not
      repeat the pitch verbatim. Each followup ships some days after
      the previous one (see "Sequence" below for exact delays).
    - The final email adds a gentle close — no aggression, no
      pressure-selling.
    - Subject lines: short (under 60 chars), lowercase preferred,
      no clickbait, no emojis.

    Return JSON matching the schema. One object per email step.
    """

    user = """
    Sender context (what we sell):
    #{pitch_block(ctx.pitch)}

    Target person:
    - Name: #{ctx.person && ctx.person.name}
    - Title: #{ctx.person && ctx.person.title}
    - Email: #{ctx.person && ctx.person.email}

    Target company:
    - Name: #{ctx.company && ctx.company.name}
    - Industry code: #{ctx.company && ctx.company.industry_code}
    - Employees: #{ctx.company && ctx.company.employees_latest}
    - Region: #{ctx.company && ctx.company.region}
    - Summary:
    #{ctx.company && ctx.company.ai_summary}

    Sequence skeleton (write one subject+body per email step):
    #{skeleton_lines(ctx.all_steps)}

    Language: #{language_name(ctx.language)} (write the whole email in
    this language).
    """

    {:ok, %{system: system, user: user}}
  end

  defp pitch_block(nil),
    do: "(none — write a generic, polite intro that asks what they're working on)"

  defp pitch_block(%{user_summary: u, ai_summary: a, domain: d}) do
    text = u || a

    cond do
      is_binary(text) and String.trim(text) != "" ->
        domain_line = if is_binary(d) and d != "", do: "Domain: #{d}\n", else: ""
        domain_line <> text

      true ->
        "(domain set but no summary yet — write a generic, polite intro)"
    end
  end

  defp skeleton_lines(steps) do
    steps
    |> Enum.map(fn s ->
      case s.kind do
        :email ->
          label =
            cond do
              s.position == 0 -> "Initial email"
              true -> "Followup #{s.position}"
            end

          "  - position #{s.position}: #{label} (ships #{s.delay_days} days after previous step)"

        :terminal ->
          "  - terminal: mark contact as #{s.terminal_action}, #{s.delay_days} days after final email (no email written)"
      end
    end)
    |> Enum.join("\n")
  end

  defp language_name("en"), do: "English"
  defp language_name("et"), do: "Estonian"
  defp language_name("fi"), do: "Finnish"
  defp language_name(other), do: other

  defp call_model(prompt, ctx) do
    case Complete.run(:smart, prompt.user,
           system: prompt.system,
           response_format: :json,
           schema: @schema,
           temperature: 0.7,
           max_tokens: 2500,
           task: :email_writer,
           campaign_id: ctx.contact.campaign_id,
           subject: {:campaign_contact, ctx.contact.id}
         ) do
      {:ok, %{content: %{"steps" => steps}}} when is_list(steps) ->
        {:ok, normalize_steps(steps, ctx.email_steps)}

      {:ok, _other} ->
        {:error, :writer_invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_steps(ai_steps, email_steps) do
    by_position = Map.new(ai_steps, fn s -> {s["position"], s} end)

    Enum.map(email_steps, fn step ->
      raw = Map.get(by_position, step.position) || %{}

      %{
        position: step.position,
        subject: Map.get(raw, "subject", ""),
        body: Map.get(raw, "body", "")
      }
    end)
  end

  defp persist(ctx, ai_steps, actor) do
    existing =
      OutboundEmail.list_for_thread!(ctx.thread.id, actor: actor, authorize?: actor != nil)
      |> Enum.filter(&(&1.status == :drafted))
      |> MapSet.new(& &1.step_position)

    emails =
      ai_steps
      |> Enum.reject(&MapSet.member?(existing, &1.position))
      |> Enum.map(fn s ->
        OutboundEmail.create_draft!(ctx.thread.id, s.position, s.subject, s.body,
          actor: actor,
          authorize?: actor != nil
        )
      end)

    {:ok, emails}
  end
end
