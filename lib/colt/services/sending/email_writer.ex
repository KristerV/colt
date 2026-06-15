defmodule Colt.Services.Sending.EmailWriter do
  @moduledoc """
  Claude 4.5 Sonnet writes the full sequence of drafts for one contact.

  Input: a `CampaignContact` (id or struct).
  Output: `{:ok, %{steps: [%{position, subject, body}], emails: [...]}}` —
  one `:drafted` Email is persisted per email step on the contact's
  thread, populating ai_* / user_* / final_* fields.

  Phase E9 wires the learning loop: previous outbound rows in the same
  campaign where the user edited the AI draft are passed as few-shot
  examples (cap 20, no ranking). The prompt includes a seed integer
  0-99; the model uses `seed mod N` to pick deterministically among
  matching example styles so multiple voices get sampled across
  contacts.

  Inspect a full prompt via iex:

      iex> contact = Colt.Resources.CampaignContact.get!(id)
      iex> {:ok, ctx} = Colt.Services.Sending.EmailWriter.context_for(contact)
      iex> {:ok, prompt} = Colt.Services.Sending.EmailWriter.prompt_for(ctx)
      iex> IO.puts(prompt.system); IO.puts(prompt.user)
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
         {:ok, ctx} <- collect_examples(ctx),
         {:ok, prompt} <- build_prompt(ctx),
         {:ok, ai_steps} <- call_model(prompt, ctx),
         {:ok, emails} <- persist(ctx, prompt, ai_steps, actor) do
      {:ok, %{steps: ai_steps, emails: emails}}
    end
  end

  @doc "iex inspection helper — same as the private load_context."
  def context_for(contact, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    load_context(contact, actor)
  end

  @doc "iex inspection helper — same as private build_prompt."
  def prompt_for(ctx) do
    {:ok, ctx} = collect_examples(ctx)
    build_prompt(ctx)
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
      Ash.load!(contact, [person: [company: [:annual_reports]], thread: []],
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

  defp collect_examples(ctx) do
    rows =
      case OutboundEmail.list_user_edited_for_campaign(ctx.contact.campaign_id, 20,
             load: [thread: [campaign_contact: [person: [:company]]]],
             authorize?: false
           ) do
        {:ok, list} -> list
        _ -> []
      end

    examples =
      rows
      |> Enum.map(&example_from/1)
      |> Enum.reject(&is_nil/1)

    {:ok, Map.put(ctx, :examples, examples)}
  end

  defp example_from(email) do
    contact = email.thread && email.thread.campaign_contact
    person = contact && contact.person
    company = person && person.company

    after_subject = email.user_subject || email.ai_subject
    after_body = email.user_body || email.ai_body

    if after_subject || after_body do
      %{
        id: email.id,
        step_position: email.step_position,
        before_ai: %{subject: email.ai_subject, body: email.ai_body},
        after_user: %{subject: after_subject, body: after_body},
        person_brief: %{
          name: person && person.name,
          title: person && person.title
        },
        company_brief: %{
          name: company && company.name,
          industry: company && company.industry_code,
          employees: company && company.employees_latest,
          summary: company && company.ai_summary
        }
      }
    end
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

    examples = Map.get(ctx, :examples, [])
    seed = :rand.uniform(100) - 1

    user = """
    Sender context (what we sell):
    #{pitch_block(ctx.pitch)}

    Target person:
    - Name: #{ctx.person && ctx.person.name}
    - Title: #{ctx.person && ctx.person.title}
    - Email: #{ctx.person && ctx.person.email}

    Target company:
    #{company_block(ctx.company)}

    Sequence skeleton (write one subject+body per email step):
    #{skeleton_lines(ctx.all_steps)}

    #{examples_block(examples, seed)}

    Language: #{language_name(ctx.language)} (write the whole email in
    this language).
    """

    {:ok, %{system: system, user: user, seed: seed, example_ids: Enum.map(examples, & &1.id)}}
  end

  defp company_block(nil), do: "- (no company data)"

  defp company_block(company) do
    """
    - Name: #{company.name}
    - Industry code: #{company.industry_code}
    - Region: #{company.region}
    - Website: #{company.website_url || "—"}
    - Registry status: #{company.status}
    - Employees (latest): #{company.employees_latest}
    - Revenue (latest): #{format_eur(company.revenue_latest)}
    - Revenue growth: #{company.revenue_growth_bucket || "—"}
    - Recent annual figures:
    #{financials_block(company)}
    - Summary:
    #{company.ai_summary}\
    """
  end

  defp financials_block(company) do
    case recent_reports(company) do
      [] ->
        "    (no filed reports)"

      reports ->
        reports
        |> Enum.map(fn r ->
          "    #{r.year}: revenue #{format_eur(r.revenue)}, employees #{r.employees || "—"}"
        end)
        |> Enum.join("\n")
    end
  end

  defp recent_reports(%{annual_reports: reports}) when is_list(reports) do
    reports
    |> Enum.sort_by(& &1.year, :desc)
    |> Enum.take(3)
    |> Enum.map(&%{year: &1.year, revenue: &1.revenue_eur, employees: &1.employees})
  end

  defp recent_reports(_), do: []

  defp format_eur(nil), do: "—"

  defp format_eur(d) do
    n = Decimal.to_float(d)

    cond do
      n >= 1_000_000 -> "€#{trim_decimal(n / 1_000_000)}M"
      n >= 1_000 -> "€#{trim_decimal(n / 1_000)}K"
      true -> "€#{round(n)}"
    end
  end

  defp trim_decimal(x) do
    x |> Float.round(1) |> :erlang.float_to_binary(decimals: 1) |> String.replace_suffix(".0", "")
  end

  defp examples_block([], _seed), do: ""

  defp examples_block(examples, seed) do
    rendered =
      examples
      |> Enum.with_index()
      |> Enum.map(fn {ex, i} ->
        """
        Example #{i} (id #{ex.id}, #{step_label(ex.step_position)}):
          Person: #{ex.person_brief.title} at #{ex.company_brief.name} (#{ex.company_brief.industry}, #{ex.company_brief.employees} employees)
          Company summary: #{trunc_text(ex.company_brief.summary, 240)}
          AI draft subject: #{ex.before_ai.subject}
          AI draft body:
        #{indent(trunc_text(ex.before_ai.body, 400))}
          User-edited subject: #{ex.after_user.subject}
          User-edited body:
        #{indent(trunc_text(ex.after_user.body, 400))}
        """
      end)
      |> Enum.join("\n")

    """
    Few-shot examples (#{length(examples)} prior contacts the user edited):
    #{rendered}

    Seed: #{seed}
    Instruction: scan the examples above. Each is tagged with the step it
    came from (opener vs followup N). When writing a given step, prefer
    examples from the same step — learn opener style from openers and
    followup style from followups; do not copy an opener's structure into
    a followup. Among examples for the same step, if one or more closely
    match the target's industry, company size, or person title, follow the
    style of those. If multiple match, pick deterministically using
    `seed mod N` where N is the count of matching examples. If none match,
    write fresh in the user's tone.
    """
  end

  defp step_label(nil), do: "manual reply"
  defp step_label(0), do: "opener"
  defp step_label(n) when is_integer(n), do: "followup #{n}"

  defp trunc_text(nil, _), do: ""

  defp trunc_text(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp indent(text) do
    text |> String.split("\n") |> Enum.map(&("    " <> &1)) |> Enum.join("\n")
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

  defp persist(ctx, prompt, ai_steps, actor) do
    existing =
      OutboundEmail.list_for_thread!(ctx.thread.id, actor: actor, authorize?: actor != nil)
      |> Enum.filter(&(&1.status == :drafted))
      |> MapSet.new(& &1.step_position)

    meta = %{
      "seed" => prompt.seed,
      "example_ids" => prompt.example_ids,
      "prompt_chars" => String.length(prompt.user) + String.length(prompt.system)
    }

    emails =
      ai_steps
      |> Enum.reject(&MapSet.member?(existing, &1.position))
      |> Enum.map(fn s ->
        Ash.create!(
          OutboundEmail,
          %{
            thread_id: ctx.thread.id,
            step_position: s.position,
            ai_subject: s.subject,
            ai_body: s.body,
            writer_meta: meta
          },
          action: :create_draft,
          actor: actor,
          authorize?: actor != nil
        )
      end)

    {:ok, emails}
  end
end
