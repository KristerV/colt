defmodule Colt.Jobs.Enrichment.ResolveContact do
  @moduledoc """
  Walks the contact ladder (owner → title → generic) for one campaign company.

  Runs after `MatchICP` and replaces its old unconditional jump into
  `PickContactPages`. Re-entrant: each rung that misses re-enqueues this job for
  the next enabled rung, and `ExtractContacts` re-enters here when the title rung
  finds nobody. `args.rung` is the rung to attempt; absent means "start at the
  top of the ladder".

  Only the **title** rung is expensive — it needs the contact-page subchain. The
  owner and generic rungs resolve from addresses we already hold, so a campaign
  that wants owner-and-generic never scrapes a contact page at all. That's why
  the ladder is walked here rather than inside the scraping chain.

  Queue `:ai` because the rungs may call the address classifier; the work is
  otherwise a couple of reads.
  """
  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    priority: 3,
    unique: [
      fields: [:worker, :args],
      keys: [:campaign_company_id, :rung],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias Colt.Jobs.Enrichment.{PickContactPages, VerifyEmail}
  alias Colt.Resources.{Campaign, CampaignCompany, Company, Person}

  alias Colt.Services.Enrichment.{
    ContactDedup,
    ContactRungs,
    ResolveGenericInbox,
    ResolveOwnerEmail,
    Transition
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id} = args}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.resume(cc),
         {:ok, company} <- Company.get(cc.company_id),
         {:ok, campaign} <- Campaign.get(cc.campaign_id, authorize?: false) do
      rung = rung(args, campaign)
      attempt(rung, cc, company, campaign)
    end
  end

  defp rung(%{"rung" => rung}, _campaign) when is_binary(rung), do: String.to_existing_atom(rung)
  defp rung(_args, campaign), do: ContactRungs.first(campaign)

  defp attempt(:none, cc, _company, _campaign) do
    Transition.stage(cc, :contact, :fall)
    {:ok, _} = Transition.terminate(cc, :no_contacts, reason: no_rungs_reason())
    :ok
  end

  # The title rung is the only one that needs pages read, so it hands off to the
  # existing scraping subchain. ExtractContacts comes back to us on a miss.
  defp attempt(:title, cc, _company, _campaign) do
    %{campaign_company_id: cc.id} |> PickContactPages.new() |> Oban.insert!()
    :ok
  end

  defp attempt(:owner, cc, company, campaign) do
    Transition.stage(cc, :contact, :work)

    resolve(cc, company, campaign, :owner, fn ->
      ResolveOwnerEmail.run(company,
        campaign_id: cc.campaign_id,
        subject: {:campaign_company, cc.id}
      )
    end)
  end

  defp attempt(:generic, cc, company, campaign) do
    Transition.stage(cc, :contact, :work)

    resolve(cc, company, campaign, :generic, fn ->
      ResolveGenericInbox.run(company,
        campaign_id: cc.campaign_id,
        subject: {:campaign_company, cc.id}
      )
    end)
  end

  defp resolve(cc, company, campaign, rung, fun) do
    case fun.() do
      {:ok, nil} ->
        advance(cc, campaign, rung)

      {:ok, email} ->
        pick(cc, company, campaign, rung, email)

      {:error, reason} ->
        # A classifier outage shouldn't burn the company — let Oban retry, and
        # only give up once attempts run out.
        Logger.warning("resolve_contact: #{rung} rung failed for cc=#{cc.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp pick(cc, company, campaign, rung, email) do
    if ContactDedup.taken?(cc.campaign_id, email, cc.id) do
      # Someone else in this campaign is already emailing this human. Treat the
      # rung as a miss rather than the company as a dead end: this company may
      # still be reachable one rung down, at its own shared inbox.
      Logger.info("resolve_contact: #{email} already picked in campaign #{cc.campaign_id}")
      advance(cc, campaign, rung, duplicate: email)
    else
      {:ok, person} = find_or_create_person(company, email)

      case CampaignCompany.set_picked_person(cc, person.id, ContactDedup.normalize(email),
             authorize?: false
           ) do
        {:ok, cc} ->
          Transition.stage(cc, :contact, :done)
          %{campaign_company_id: cc.id} |> VerifyEmail.new() |> Oban.insert!()
          :ok

        # Lost the race: a concurrent job picked this address between our check
        # and our write, and the campaign_picked_email identity caught it. Same
        # outcome as losing the check.
        {:error, error} ->
          if ContactDedup.duplicate_error?(error) do
            advance(cc, campaign, rung, duplicate: email)
          else
            {:error, error}
          end
      end
    end
  end

  defp advance(cc, campaign, rung, opts \\ []) do
    case ContactRungs.after_rung(campaign, rung) do
      :none ->
        Transition.stage(cc, :contact, :fall)
        {:ok, _} = Transition.terminate(cc, :no_contacts, reason: reason(cc, campaign, opts))
        :ok

      next ->
        %{campaign_company_id: cc.id, rung: next} |> __MODULE__.new() |> Oban.insert!()
        :ok
    end
  end

  # The ladder ran out. If it ran out because the only address we found belongs
  # to someone we're already emailing, say so — "no contacts" on a company whose
  # owner we plainly found would just look broken.
  defp reason(cc, campaign, opts) do
    case Keyword.get(opts, :duplicate) do
      nil -> exhausted_reason(campaign)
      email -> duplicate_reason(cc, email)
    end
  end

  defp duplicate_reason(cc, email) do
    case ContactDedup.holder(cc.campaign_id, email, cc.id) do
      {:ok, %{company: %{name: name}}} ->
        "#{email} is already being contacted in this campaign, at #{name}"

      _ ->
        "#{email} is already being contacted in this campaign"
    end
  end

  defp find_or_create_person(company, email) do
    case Person.by_email(company.id, email, authorize?: false) do
      {:ok, %Person{} = person} ->
        {:ok, person}

      _ ->
        Person.create_from_address(%{company_id: company.id, email: email})
    end
  end

  defp no_rungs_reason, do: "no contact types enabled on the campaign"

  defp exhausted_reason(campaign) do
    tried =
      [
        campaign.reach_owner? && "owner",
        campaign.reach_title? && "job title",
        campaign.reach_generic? && "generic inbox"
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(", ")

    "no contact found (tried: #{tried})"
  end
end
