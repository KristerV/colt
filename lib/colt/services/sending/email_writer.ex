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
      Ash.load!(
        contact,
        [person: [company: [:annual_reports]], thread: [], assigned_email_account: []],
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
       sender: contact.assigned_email_account,
       company: contact.person && contact.person.company,
       sequence: sequence,
       email_steps: Enum.filter(sequence.sequence_steps, &(&1.kind == :email)),
       all_steps: sequence.sequence_steps,
       thread: thread,
       language: sequence.language,
       pitch: pitch
     }}
  end

  @example_window 250
  @max_examples 50

  # Each contact = one whole approach ("template"). The labeler tags every
  # approved opener with a template_label; here we pick ONE label at random and
  # feed only that approach's sequences, so the writer commits to a single
  # approach per contact instead of averaging them into mush. Until a campaign
  # has labeled openers, fall back to the newest user-edited sequences.
  defp collect_examples(ctx) do
    case pick_template(ctx) do
      {:ok, template, examples} ->
        {:ok, ctx |> Map.put(:examples, examples) |> Map.put(:chosen_template, template)}

      :none ->
        {:ok, ctx |> Map.put(:examples, fallback_examples(ctx)) |> Map.put(:chosen_template, nil)}
    end
  end

  defp pick_template(ctx) do
    openers =
      OutboundEmail.list_labeled_openers_for_campaign!(ctx.contact.campaign_id,
        load: [thread: [:outbound_emails, campaign_contact: [person: [:company]]]],
        authorize?: false
      )

    case Enum.group_by(openers, & &1.template_label) do
      groups when map_size(groups) == 0 ->
        :none

      groups ->
        # Uniform pick across distinct approaches — every template gets used,
        # so a majority approach can't starve a minority one (or vice versa).
        {label, label_openers} = Enum.random(groups)

        examples =
          label_openers
          |> Enum.map(&example_from_opener/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.recency, {:desc, DateTime})
          |> Enum.take(@max_examples)

        template = template_axes(label, label_openers)

        if examples == [], do: :none, else: {:ok, template, examples}
    end
  end

  defp template_axes(label, [opener | _]) do
    %{
      label: label,
      angle: opener.template_angle,
      ask: opener.template_ask,
      offer: opener.template_offer
    }
  end

  defp fallback_examples(ctx) do
    rows =
      case OutboundEmail.list_user_edited_for_campaign(ctx.contact.campaign_id, @example_window,
             load: [thread: [campaign_contact: [person: [:company]]]],
             authorize?: false
           ) do
        {:ok, list} -> list
        _ -> []
      end

    rows
    |> Enum.group_by(& &1.thread_id)
    |> Enum.map(fn {_thread_id, emails} -> contact_example(emails) end)
    |> Enum.reject(&is_nil/1)
    # newest contacts first (rows already arrive inserted_at desc)
    |> Enum.sort_by(& &1.recency, {:desc, DateTime})
    |> Enum.take(@max_examples)
  end

  # Template path: a labeled opener carries its whole thread (the sequence).
  defp example_from_opener(opener) do
    thread = opener.thread
    contact = thread && thread.campaign_contact
    person = contact && contact.person

    emails =
      ((thread && thread.outbound_emails) || [])
      |> Enum.reject(&(is_nil(&1.step_position) or &1.is_manual_reply))

    build_example(person, emails, opener.inserted_at)
  end

  # Fallback path: a thread's user-edited rows, grouped upstream.
  defp contact_example(emails) do
    first = List.first(emails)
    contact = first && first.thread && first.thread.campaign_contact
    person = contact && contact.person

    build_example(person, emails, first && first.inserted_at)
  end

  # One prior contact = the whole sequence (opener + followups) in step order,
  # using only the user's final sent text — never the AI draft. Showing the
  # draft next to the edit trains the model to "correct away" from its own
  # instinct, which collapses approach diversity over time.
  defp build_example(_person, [], _recency), do: nil

  defp build_example(person, emails, recency) do
    company = person && person.company

    steps =
      emails
      |> Enum.sort_by(&(&1.step_position || 999))
      |> Enum.map(fn e ->
        %{
          position: e.step_position,
          subject: e.user_subject || e.ai_subject,
          body: e.user_body || e.ai_body
        }
      end)

    %{
      ids: Enum.map(emails, & &1.id),
      recency: recency,
      person_brief: %{name: person && person.name, title: person && person.title},
      company_brief: %{
        name: company && company.name,
        industry: company && company.industry_code,
        employees: company && company.employees_latest,
        summary: company && company.ai_summary
      },
      steps: steps
    }
  end

  defp build_prompt(ctx) do
    system = """
    You are a cold-outreach writer composing a multi-step email sequence
    in #{language_name(ctx.language)}. Mimic the user's natural tone —
    plain, direct, no marketing fluff. Output plain text only; no
    Markdown, no HTML, no signatures (the inbox appends those).

    Sender identity:
    - You are writing AS the sender named under "Sender" below. When you
      introduce yourself or sign off, use THAT name — never a name that
      appears in the examples (those were written by other senders).
    - Keep whatever name format the examples use: if they sign with a
      first name only, use only the sender's first name; if they use the
      full name, use the sender's full name.

    Sequence rules:
    - Step 1 opens cold; introduce yourself briefly (using the sender's
      name) and state the reason for reaching out tied to the recipient's
      role and company.
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
    template = Map.get(ctx, :chosen_template)

    user = """
    Sender (write as this person — use this name to introduce/sign):
    #{sender_block(ctx.sender)}

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

    #{examples_block(examples, template)}

    Language: #{language_name(ctx.language)} (write the whole email in
    this language).
    """

    {:ok,
     %{
       system: system,
       user: user,
       chosen_template: template && template.label,
       example_ids: Enum.flat_map(examples, & &1.ids)
     }}
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

  defp examples_block([], _template), do: ""

  # Template path: the approach is already chosen (in code). Feed only that
  # one approach's sequences and tell the model to commit to it.
  defp examples_block(examples, %{} = template) do
    """
    All examples below are ONE outreach approach the user uses — template
    "#{template.label}":
    - angle (reason for reaching out): #{template.angle}
    - ask (call to action): #{template.ask}
    - offer (value framing): #{template.offer}

    #{rendered_examples(examples)}
    Instruction: every example is a full sequence the user actually sent in
    this one approach — real, finished writing in their voice, not
    corrections. Write this contact's whole sequence in exactly this
    approach: same angle and same call to action, with fresh wording
    tailored to this company. Match the user's tone per step (opener style
    from openers, followup style from followups). Do not switch to a
    different angle or CTA.
    """
  end

  # Fallback path (campaign has no labeled templates yet): just learn the
  # user's voice from their recent edited sequences.
  defp examples_block(examples, nil) do
    """
    Few-shot examples (#{length(examples)} prior sequences the user sent):
    #{rendered_examples(examples)}
    Instruction: every example is a full sequence the user actually sent —
    real, finished writing in their own voice, not corrections. Write this
    contact's sequence in the same voice and tone, with fresh wording
    tailored to this company.
    """
  end

  defp rendered_examples(examples) do
    examples
    |> Enum.with_index()
    |> Enum.map(fn {ex, i} -> render_example(ex, i) end)
    |> Enum.join("\n")
  end

  defp render_example(ex, i) do
    steps =
      ex.steps
      |> Enum.map(fn s ->
        """
          #{step_label(s.position)}:
            Subject: #{s.subject}
            Body:
        #{indent(s.body || "")}\
        """
      end)
      |> Enum.join("\n")

    """
    Example #{i} — #{ex.person_brief.title} at #{ex.company_brief.name} (#{ex.company_brief.industry}, #{ex.company_brief.employees} employees):
      Company summary: #{trunc_text(ex.company_brief.summary, 240)}
    #{steps}\
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

  defp sender_block(nil),
    do: "- (no sender assigned yet — introduce yourself generically, no invented name)"

  defp sender_block(%{address: address} = sender) do
    "- Name: #{sender_name_or_local(sender)}\n- Email: #{address}"
  end

  # Prefer the configured display name; otherwise humanize the email local-part
  # so the writer still has a plausible name instead of inventing one.
  defp sender_name(%{display_name: name}) when is_binary(name) do
    if String.trim(name) == "", do: nil, else: name
  end

  defp sender_name(_), do: nil

  defp sender_name_or_local(%{address: address} = sender) do
    sender_name(sender) || humanize_local_part(address)
  end

  defp humanize_local_part(address) when is_binary(address) do
    address
    |> String.split("@")
    |> List.first()
    |> String.split(~r/[._]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize_local_part(_), do: nil

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
      "chosen_template" => prompt.chosen_template,
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
