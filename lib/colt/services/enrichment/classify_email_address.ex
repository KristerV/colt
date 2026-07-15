defmodule Colt.Services.Enrichment.ClassifyEmailAddress do
  @moduledoc """
  Decides whether an email address belongs to **a specific human** (`:personal`)
  or is a shared/role/company mailbox (`:generic`).

  This is the gate on the owner rung. A registry contact email is only usable as
  the owner's address when it names a person — `andres@ettevote.ee` yes,
  `oravasolutions@gmail.com` no, even though the latter is equally "not info@".

  Keyword list first (free, deterministic), AI only on a miss. People are
  creative with shared-inbox prefixes — `tere@`, `pood@`, `kontor@` are all real
  and none are on any list — so the keyword pass is an optimisation, not the
  answer.

  Returns `{:ok, :personal | :generic}`.
  """

  alias Colt.Services.Ai.Complete

  require Logger

  # Unambiguous shared-inbox prefixes. Deliberately short: a false :generic here
  # silently costs us an owner, so only prefixes that are never a human's name
  # belong on this list. Everything else goes to the model.
  @generic_prefixes ~w(info contact hello sales hi kontakt myynti office mail
                       admin legal clients support help team reception noreply
                       no-reply arve arved invoice orders tellimus klienditugi
                       raamatupidamine juhatus accounting finance)

  @system """
  You classify a single email address as PERSONAL or GENERIC.

  PERSONAL means the address names one specific human being. It is the address of a person, and a message sent to it lands in that person's own inbox.
  - andres@ettevote.ee → PERSONAL (a first name)
  - aare.kulli@gmail.com → PERSONAL (first.last)
  - hg@krafteer.com → PERSONAL (a person's initials on a company domain)
  - soobik@sopser.ee → PERSONAL (a surname)

  GENERIC means anything else: a role, a department, a function, or the company itself.
  - info@firma.ee, kontakt@firma.ee, tere@firma.ee, pood@firma.ee → GENERIC (role/function inboxes)
  - oravasolutions@gmail.com → GENERIC (the company's name, not a person's)
  - valasteagro@gmail.com → GENERIC (company name)
  - 14614272@mail.ee → GENERIC (a registry code, not a person)

  Judge the LOCAL PART (before the @). The domain is context only — a free-provider domain like gmail.com does NOT make an address personal, and a company domain does NOT make it generic.

  These are Estonian, Finnish, Latvian and Lithuanian businesses. Estonian given names you should recognise as PERSONAL include: Andres, Toomas, Priit, Jaanus, Marko, Mati, Lauri, Martin, Aivar, Indrek, Jaan, Aare, Paavo, Vivian, Janika, Aino. Estonian words that are NOT names and indicate GENERIC include: tere (hello), pood (shop), kontor (office), müük (sales), arve (invoice), juhatus (board), kool (school).

  When genuinely torn, answer GENERIC. A wrongly-personal address means we address a shared inbox as if it were a named human, which reads worse than the reverse.

  Return JSON only.
  """

  @schema %{
    type: "object",
    additionalProperties: false,
    required: ["kind"],
    properties: %{
      kind: %{type: "string", enum: ["personal", "generic"]}
    }
  }

  @doc """
  Classify `email`. `opts` are forwarded to the AI call for cost attribution
  (`:campaign_id`, `:subject`).
  """
  def run(email, opts \\ [])

  def run(email, _opts) when not is_binary(email), do: {:ok, :generic}

  def run(email, opts) do
    local = local_part(email)

    cond do
      local == "" -> {:ok, :generic}
      local in @generic_prefixes -> {:ok, :generic}
      true -> classify_with_ai(email, local, opts)
    end
  end

  @doc """
  The canonical shared-inbox prefix list, so callers that need a cheap keyword
  pass (e.g. `ExtractGenericEmail`) don't grow a second, drifting copy.
  """
  def generic_prefixes, do: @generic_prefixes

  defp classify_with_ai(email, local, opts) do
    user = """
    Email address: #{email}
    Local part: #{local}

    Is this one specific human's address, or a role/department/company mailbox?
    Return: {"kind": "personal"|"generic"}.
    """

    # :smart, not :cheap. The `:cheap` tier is a reasoning model and this prompt
    # is far too small for it — it routinely spends its whole reasoning budget
    # and returns empty, which costs three retries plus an escalation to land
    # the same answer. :smart is a fast flash model here; one call per company
    # that enters a funnel, and only when the keyword list misses.
    case Complete.run(:smart, user,
           system: @system,
           response_format: :json,
           schema: @schema,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "classify_email_address",
           temperature: 0.0
         ) do
      {:ok, %{content: %{"kind" => "personal"}}} ->
        {:ok, :personal}

      {:ok, %{content: %{"kind" => "generic"}}} ->
        {:ok, :generic}

      {:ok, other} ->
        Logger.warning("classify_email_address: bad response for #{email}: #{inspect(other)}")
        {:error, :bad_response}

      {:error, _} = err ->
        err
    end
  end

  defp local_part(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> String.split("@", parts: 2)
    |> List.first()
    |> Kernel.||("")
  end
end
