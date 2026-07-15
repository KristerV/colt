defmodule Colt.Jobs.Enrichment.ExtractContacts do
  @moduledoc """
  §6.9 — the job-title rung. Concatenate the company's stored markdown (landing +
  contact pages), ask Claude Sonnet 4.5 to extract every named contact,
  validate emails by substring against the haystack, then batch a GLM 4.7
  call to flag rows that match the campaign's target title.

  Persists a `Person` per validated row, then marks the CampaignCompany
  `:enriched`.

  No longer terminal: when this rung finds nobody, it hands back to
  `ResolveContact`, which drops to the generic-inbox rung if the campaign
  enabled it. Only an exhausted ladder ends as `:no_contacts`.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2, priority: 1

  alias Colt.Jobs.Enrichment.ResolveContact
  alias Colt.Jobs.Enrichment.VerifyEmail, as: VerifyEmailJob
  alias Colt.Resources.{Campaign, CampaignCompany, Company, IcpLearning, Page, Person}

  alias Colt.Services.Enrichment, as: Svc

  alias Colt.Services.Enrichment.{
    ContactDedup,
    ContactRungs,
    FailureMessage,
    Freshness,
    PickBestContact,
    Transition,
    ValidateInMarkdown
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    if scrapes_pending?(id) do
      # ScrapeContactPage siblings are still working (incl. recursive children).
      # Wait for them so the haystack is complete.
      {:snooze, 5}
    else
      do_perform(id)
    end
  end

  defp do_perform(id) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.resume(cc),
         {:ok, company} <- Company.get(cc.company_id),
         {:ok, campaign} <- Campaign.get(cc.campaign_id, authorize?: false),
         {:ok, pages} <- Page.for_company(company.id) do
      Transition.stage(cc, :contact, :work)

      existing = Freshness.existing_persons(company)

      cond do
        Freshness.company_fresh?(company) and existing != [] ->
          reuse_existing(cc, campaign, existing)

        true ->
          extract_fresh(cc, company, campaign, pages)
      end
    end
  end

  defp extract_fresh(cc, company, campaign, pages) do
    haystack =
      pages
      |> Enum.map(& &1.markdown)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join("\n\n---\n\n")

    cond do
      haystack == "" ->
        title_rung_missed(cc, campaign, "no contact-page markdown")

      true ->
        run(cc, company, campaign, pages, haystack)
    end
  end

  # The title rung came up empty. Hand back to the ladder rather than ending the
  # company here — the campaign may still accept a generic inbox.
  defp title_rung_missed(cc, campaign, reason) do
    case ContactRungs.after_rung(campaign, :title) do
      :none ->
        Transition.stage(cc, :contact, :fall)
        {:ok, _} = Transition.terminate(cc, :no_contacts, reason: reason)
        :ok

      next ->
        %{campaign_company_id: cc.id, rung: next}
        |> ResolveContact.new()
        |> Oban.insert!()

        :ok
    end
  end

  defp reuse_existing(cc, campaign, persons) do
    pick_best(cc, campaign, persons)
  end

  # Drop anyone this campaign is already emailing *before* choosing, so the
  # pick falls to the next-best real person at this company rather than
  # abandoning it. Only if everyone here is a duplicate does the rung miss.
  defp pick_best(cc, campaign, persons) do
    {available, dupes} =
      Enum.split_with(persons, &(not ContactDedup.taken?(cc.campaign_id, &1.email, cc.id)))

    titles = Enum.map(available, & &1.title)

    case pick_index(campaign.target_job_title, titles, cc.campaign_id, cc.id) do
      i when is_integer(i) ->
        finish_pick(cc, campaign, Enum.at(available, i))

      :none ->
        title_rung_missed(cc, campaign, unpicked_reason(campaign, titles, dupes))
    end
  end

  defp finish_pick(cc, campaign, person) do
    case CampaignCompany.set_picked_person(cc, person.id, ContactDedup.normalize(person.email),
           authorize?: false
         ) do
      {:ok, cc} ->
        Transition.stage(cc, :contact, :done)

        broadcast_contact(cc, %{
          contact_name: person.name,
          contact_title: person.title,
          contact_email: person.email,
          contact_phone: person.phone
        })

        enqueue_verify(cc)
        :ok

      {:error, error} ->
        # Another company in this campaign claimed the address between the check
        # above and this write. Anything else is a real failure and must not be
        # reported to the user as a duplicate.
        if ContactDedup.duplicate_error?(error) do
          title_rung_missed(
            cc,
            campaign,
            "#{person.email} is already being contacted in this campaign"
          )
        else
          {:error, error}
        end
    end
  end

  defp unpicked_reason(_campaign, [], [_ | _] = dupes) do
    emails = dupes |> Enum.map(& &1.email) |> Enum.reject(&is_nil/1) |> Enum.join(", ")
    "everyone found here is already being contacted in this campaign (#{emails})"
  end

  defp unpicked_reason(campaign, titles, _dupes), do: no_match_reason(campaign, titles)

  defp run(cc, company, campaign, pages, haystack) do
    case Svc.ExtractContacts.run(haystack,
           campaign_id: cc.campaign_id,
           subject: {:campaign_company, cc.id}
         ) do
      {:ok, []} ->
        title_rung_missed(cc, campaign, "no named people on contact pages")

      {:ok, candidates} ->
        validated = validate_all(candidates, haystack)

        cond do
          validated == [] ->
            title_rung_missed(
              cc,
              campaign,
              "extracted #{length(candidates)} contact(s); none verified in markdown"
            )

          true ->
            persist_and_finish(cc, company, campaign, pages, validated)
        end

      {:error, reason} ->
        {user_msg, detail} = FailureMessage.run(:contact, reason)
        Transition.stage(cc, :contact, :fail)

        {:ok, _} =
          Transition.terminate(cc, :failed,
            stage: :contact,
            reason: user_msg,
            detail: detail
          )

        {:error, detail}
    end
  end

  defp persist_and_finish(cc, company, campaign, pages, validated) do
    source_page_id = pick_source_page(pages)

    persisted =
      Enum.map(validated, fn p ->
        {:ok, person} =
          Person.create_validated(%{
            company_id: company.id,
            source_page_id: source_page_id,
            name: p.name,
            title: p.title,
            email: p.email,
            phone: p.phone,
            validated_in_markdown: true
          })

        person
      end)

    # Always touch the company so the persisted people seed the freshness cache,
    # even when none match this campaign's target. Everyone found is persisted;
    # the duplicate filter only governs who we *pick*, not who we remember.
    {:ok, _} = Company.touch_enriched(company)

    pick_best(cc, campaign, persisted)
  end

  defp no_match_reason(campaign, titles) do
    target = campaign.target_job_title || "target role"
    "found #{length(titles)} contact(s) but none match \"#{target}\""
  end

  defp enqueue_verify(cc) do
    %{campaign_company_id: cc.id}
    |> VerifyEmailJob.new(
      unique: [
        period: :infinity,
        keys: [:campaign_company_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
    |> Oban.insert!()
  end

  # Returns the index of the contact matching the campaign's target job title,
  # or :none when no candidate is in the target function. We deliberately do
  # NOT fall back to a random contact — a company with people but no on-target
  # contact should become :no_contacts, not get a wrong person attached.
  defp pick_index(_target, [], _campaign_id, _cc_id), do: :none

  defp pick_index(target, titles, campaign_id, cc_id) do
    case PickBestContact.run(target, titles,
           campaign_id: campaign_id,
           subject: {:campaign_company, cc_id},
           learnings: contact_learnings(campaign_id)
         ) do
      {:ok, i} when is_integer(i) -> i
      _ -> :none
    end
  end

  defp contact_learnings(campaign_id) do
    case IcpLearning.list_by_target(campaign_id, :contact, authorize?: false) do
      {:ok, learnings} -> Enum.map(learnings, &%{body: &1.body})
      _ -> []
    end
  end

  defp validate_all(candidates, haystack) do
    candidates
    |> Enum.filter(fn p ->
      case ValidateInMarkdown.run(p.email, haystack) do
        {:ok, true} -> p.name != nil and p.email != nil
        _ -> false
      end
    end)
    |> Enum.map(fn p ->
      case ValidateInMarkdown.run_phone(p.phone, haystack) do
        {:ok, true} -> p
        _ -> %{p | phone: nil}
      end
    end)
  end

  defp pick_source_page(pages) do
    contact = Enum.find(pages, &(&1.in_navigation and not is_nil(&1.markdown)))
    landing = Enum.find(pages, &(&1.path == "/"))
    (contact || landing || %{id: nil}).id
  end

  defp broadcast_contact(cc, patch) do
    Colt.Services.Enrichment.Broadcast.row(cc.campaign_id, cc.id, patch)
  end

  defp scrapes_pending?(cc_id) do
    import Ecto.Query

    cc_id_str = to_string(cc_id)

    q =
      from j in Oban.Job,
        where: j.worker == "Colt.Jobs.Enrichment.ScrapeContactPage",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        where: fragment("?->>'campaign_company_id' = ?", j.args, ^cc_id_str)

    Colt.Repo.aggregate(q, :count, :id) > 0
  end
end
