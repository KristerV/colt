defmodule Colt.Jobs.Enrichment.ExtractContacts do
  @moduledoc """
  §6.9 — terminal step. Concatenate the company's stored markdown (landing +
  contact pages), ask Claude Sonnet 4.5 to extract every named contact,
  validate emails by substring against the haystack, then batch a GLM 4.7
  call to flag rows that match the campaign's target title.

  Persists a `Person` per validated row, then marks the CampaignCompany
  `:enriched`.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2, priority: 1

  alias Colt.Resources.{Campaign, CampaignCompany, Company, Page, Person}

  alias Colt.Services.Enrichment, as: Svc

  alias Colt.Services.Enrichment.{
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
        Transition.stage(cc, :contact, :fall)
        {:ok, _} = Transition.terminate(cc, :no_contacts, reason: "no contact-page markdown")
        :ok

      true ->
        run(cc, company, campaign, pages, haystack)
    end
  end

  defp reuse_existing(cc, campaign, persons) do
    titles = Enum.map(persons, & &1.title)
    picked_idx = pick_index(campaign.target_job_title, titles, cc.campaign_id, cc.id)

    picked_person =
      case picked_idx do
        i when is_integer(i) -> Enum.at(persons, i)
        _ -> List.first(persons)
      end

    {:ok, _} =
      CampaignCompany.set_picked_person(cc, (picked_person || %{id: nil}).id)

    Transition.stage(cc, :contact, :done)
    {:ok, _} = Transition.terminate(cc, :enriched)

    if picked_person do
      broadcast_contact(cc, %{
        contact_name: picked_person.name,
        contact_title: picked_person.title
      })
    end

    :ok
  end

  defp run(cc, company, campaign, pages, haystack) do
    case Svc.ExtractContacts.run(haystack,
           campaign_id: cc.campaign_id,
           subject: {:campaign_company, cc.id}
         ) do
      {:ok, []} ->
        Transition.stage(cc, :contact, :fall)

        {:ok, _} =
          Transition.terminate(cc, :no_contacts, reason: "no named people on contact pages")

        :ok

      {:ok, candidates} ->
        validated = validate_all(candidates, haystack)

        cond do
          validated == [] ->
            Transition.stage(cc, :contact, :fall)

            {:ok, _} =
              Transition.terminate(cc, :no_contacts,
                reason: "extracted #{length(candidates)} contact(s); none verified in markdown"
              )

            :ok

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
    titles = Enum.map(validated, & &1.title)
    picked_idx = pick_index(campaign.target_job_title, titles, cc.campaign_id, cc.id)
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

    picked_person =
      case picked_idx do
        i when is_integer(i) -> Enum.at(persisted, i)
        _ -> nil
      end

    if picked_person do
      {:ok, _} = CampaignCompany.set_picked_person(cc, picked_person.id)
    end

    {:ok, _} = Company.touch_enriched(company)
    Transition.stage(cc, :contact, :done)
    {:ok, _} = Transition.terminate(cc, :enriched)

    if picked_person do
      broadcast_contact(cc, %{
        contact_name: picked_person.name,
        contact_title: picked_person.title
      })
    end

    :ok
  end

  # ICP-validated companies must always have a picked contact. If the model
  # declines or errors, fall back to index 0 so downstream (UI + export)
  # always has someone to email.
  defp pick_index(_target, [], _campaign_id, _cc_id), do: nil

  defp pick_index(target, titles, campaign_id, cc_id) do
    case PickBestContact.run(target, titles,
           campaign_id: campaign_id,
           subject: {:campaign_company, cc_id}
         ) do
      {:ok, i} when is_integer(i) -> i
      _ -> 0
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
