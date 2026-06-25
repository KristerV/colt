defmodule Colt.Services.Sending.EmailWriter do
  @moduledoc """
  Claude 4.5 Sonnet writes the full sequence of drafts for one contact.

  Input: a `CampaignContact` (id or struct).
  Output: `{:ok, %{steps: [%{position, subject, body}], emails: [...]}}` —
  one `:drafted` Email is persisted per email step on the contact's
  thread, populating ai_* / user_* / final_* fields.

  The learning loop is scoped per-template: previous outbound rows whose
  contact was written under the SAME template (sequence) and where the user
  edited the AI draft are passed as few-shot examples (cap 50). When that
  pool is empty the writer skips the model and persists blank drafts — the
  user writes the first sequence for that template by hand, which then
  becomes the example pool the writer learns from.

  Pass the template via `sequence_id:` in opts. The writing view passes the
  template the user is working in; the auto-approve worker passes its
  weighted-random pick.

  Inspect a full prompt via iex:

      iex> contact = Colt.Resources.CampaignContact.get!(id)
      iex> {:ok, ctx} = Colt.Services.Sending.EmailWriter.context_for(contact, sequence_id: seq_id)
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
    sequence_id = Keyword.get(opts, :sequence_id)

    with {:ok, contact} <- load_contact(contact_or_id, actor),
         {:ok, ctx} <- load_context(contact, sequence_id, actor),
         {:ok, ctx} <- collect_examples(ctx) do
      generate(ctx, actor)
    end
  end

  # Empty example pool ⇒ no model call: persist blank drafts for the
  # template's email steps so the editor renders the full sequence with
  # empty fields, ready for the user to write the first one by hand.
  defp generate(%{examples: []} = ctx, actor) do
    {:ok, %{steps: [], emails: persist_blank(ctx, actor)}}
  end

  defp generate(ctx, actor) do
    with {:ok, prompt} <- build_prompt(ctx),
         {:ok, ai_steps} <- call_model(prompt, ctx),
         {:ok, emails} <- persist(ctx, prompt, ai_steps, actor) do
      {:ok, %{steps: ai_steps, emails: emails}}
    end
  end

  @doc "iex inspection helper — same as the private load_context."
  def context_for(contact, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    sequence_id = Keyword.get(opts, :sequence_id)
    load_context(contact, sequence_id, actor)
  end

  @doc "iex inspection helper — same as private build_prompt."
  def prompt_for(ctx) do
    {:ok, ctx} = collect_examples(ctx)
    build_prompt(ctx)
  end

  defp load_contact(%CampaignContact{} = c, _actor), do: {:ok, c}

  defp load_contact(id, actor) when is_binary(id) do
    Ash.get(CampaignContact, id,
      load: [:person, :thread],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_context(contact, sequence_id, actor) do
    contact =
      Ash.load!(
        contact,
        [person: [company: [:annual_reports]], thread: [], assigned_email_account: []],
        actor: actor,
        authorize?: actor != nil
      )

    sequence = load_sequence(sequence_id, contact.campaign_id, actor)

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

  # Load the specific template the contact is being written under. Falls back
  # to the campaign's oldest template when no id is passed (defensive — every
  # real caller threads a sequence_id).
  defp load_sequence(sequence_id, _campaign_id, actor) when is_binary(sequence_id) do
    Sequence.get!(sequence_id,
      load: [:sequence_steps],
      actor: actor,
      authorize?: actor != nil
    )
  end

  defp load_sequence(_nil, campaign_id, actor) do
    Sequence.get_for_campaign!(campaign_id,
      load: [:sequence_steps],
      actor: actor,
      authorize?: actor != nil
    )
  end

  @example_window 250
  @max_examples 50

  # Learning is scoped to ONE template: every prior sequence the user edited
  # under this same template, oldest-capped at @max_examples. No automatic
  # categorization — the template IS the grouping. An empty pool means the
  # user hasn't written for this template yet, so the writer leaves blanks.
  defp collect_examples(ctx) do
    rows =
      case OutboundEmail.list_user_edited_for_sequence(ctx.sequence.id, @example_window,
             load: [thread: [campaign_contact: [person: [company: [:annual_reports]]]]],
             authorize?: false
           ) do
        {:ok, list} -> list
        _ -> []
      end

    examples =
      rows
      |> Enum.group_by(& &1.thread_id)
      |> Enum.map(fn {_thread_id, emails} -> contact_example(emails) end)
      |> Enum.reject(&is_nil/1)
      # newest contacts first (rows already arrive inserted_at desc)
      |> Enum.sort_by(& &1.recency, {:desc, DateTime})
      |> Enum.take(@max_examples)

    {:ok, Map.put(ctx, :examples, examples)}
  end

  # A thread's user-edited rows, grouped upstream by thread.
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
      person_title: person && person.title,
      company: person && person.company,
      steps: steps
    }
  end

  defp build_prompt(ctx) do
    system = """
    You are a cold-outreach writer composing a multi-step email sequence
    in #{language_name(ctx.language)}. Output plain text only; no
    Markdown, no HTML, no signatures (the inbox appends those).

    What to learn from where:
    - The example sequences under "Examples" are the primary source. Take
      your style, structure, tone, length, angle, level of detail, opening
      moves and sign-off from them. Write like those emails were written.
    - The "Sender context" pitch is reference only — facts so you don't
      lie, invent claims, or misstate what the sender does. Do NOT treat it
      as the script, the talking points, or the structure. If the examples
      barely mention the product, neither should you. Never let the pitch
      override the voice and approach the examples demonstrate.

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

    user = """
    Sender (write as this person — use this name to introduce/sign):
    #{sender_block(ctx.sender)}

    Sender context (factual reference only — what we sell, so you stay
    accurate; not a script and not the source of style or structure):
    #{pitch_block(ctx.pitch)}

    Target person:
    - Name: #{ctx.person && ctx.person.name}
    - Title: #{ctx.person && ctx.person.title}
    - Email: #{ctx.person && ctx.person.email}

    Target company:
    #{company_block(ctx.company)}

    Sequence skeleton (write one subject+body per email step):
    #{skeleton_lines(ctx.all_steps)}

    #{examples_block(examples)}

    Language: #{language_name(ctx.language)} (write the whole email in
    this language).
    """

    {:ok,
     %{
       system: system,
       user: user,
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

  defp examples_block([]), do: ""

  # Each example is a prior sequence the user sent under THIS template, shown
  # with the company it was written for. The user's wording adapts to each
  # company's profile — that company→email mapping is the signal to learn, not
  # a single uniform script. Surface the company so the model can match by fit.
  defp examples_block(examples) do
    """
    Below are prior sequences the user sent under this template, each shown
    with the company it was written for. The user adapts wording to each
    company's size, revenue, industry and situation — that mapping is the
    point, not one uniform script:
    #{rendered_examples(examples)}
    Instruction: every example is a full sequence the user actually sent —
    real, finished writing in their own voice, and your primary model for
    how this email should read. Find the examples whose companies most
    resemble THIS target (revenue, employees, industry, situation) and
    follow their angle and specific moves; don't average all examples into
    one generic approach. Let these decide the style, structure, length and
    tone — not the pitch. Match style per step (opener style from openers,
    followup style from followups), and write fresh wording tailored to
    this company.
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
    Example #{i} — #{ex.person_title || "—"} at #{ex.company && ex.company.name}:
    #{company_block(ex.company)}
    #{steps}\
    """
  end

  defp step_label(nil), do: "manual reply"
  defp step_label(0), do: "opener"
  defp step_label(n) when is_integer(n), do: "followup #{n}"

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

  defp language_name(code) do
    Colt.Markets.languages()
    |> Enum.find_value(code, fn {c, label} -> if c == code, do: label end)
  end

  defp call_model(prompt, ctx) do
    case Complete.run(:smart, prompt.user,
           system: prompt.system,
           response_format: :json,
           schema: @schema,
           temperature: 0.7,
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

  # No examples yet for this template: create blank :drafted rows for each
  # email step so the editor renders the full sequence with empty fields and
  # the user writes the first one by hand.
  defp persist_blank(ctx, actor) do
    existing =
      OutboundEmail.list_for_thread!(ctx.thread.id, actor: actor, authorize?: actor != nil)
      |> Enum.map(& &1.step_position)
      |> MapSet.new()

    ctx.email_steps
    |> Enum.reject(&MapSet.member?(existing, &1.position))
    |> Enum.map(fn step ->
      OutboundEmail.create_draft!(ctx.thread.id, step.position, nil, nil,
        actor: actor,
        authorize?: actor != nil
      )
    end)
  end
end
