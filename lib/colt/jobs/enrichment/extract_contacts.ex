defmodule Colt.Jobs.Enrichment.ExtractContacts do
  @moduledoc """
  §6.9 — terminal step. Concatenate the company's stored markdown (landing +
  contact pages), ask Claude Sonnet 4.5 to extract every named contact,
  validate emails by substring against the haystack, then batch a GLM 4.7
  call to flag rows that match the campaign's target title.

  Persists a `Person` per validated row, then marks the CampaignCompany
  `:enriched`.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Resources.{Campaign, CampaignCompany, Company, Page, Person}

  alias Colt.Services.Enrichment, as: Svc
  alias Colt.Services.Enrichment.{MatchTitles, Transition, ValidateInMarkdown}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id),
         {:ok, campaign} <- Campaign.get(cc.campaign_id, authorize?: false),
         {:ok, pages} <- Page.for_company(company.id) do
      Transition.stage(cc, :contact, :work)

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
  end

  defp run(cc, company, campaign, pages, haystack) do
    case Svc.ExtractContacts.run(haystack, campaign_id: cc.campaign_id) do
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
        Transition.stage(cc, :contact, :fail)
        {:ok, _} = Transition.terminate(cc, :failed, stage: :contact, reason: short(reason))
        {:error, inspect(reason)}
    end
  end

  defp persist_and_finish(cc, company, campaign, pages, validated) do
    title_flags = title_flags_for(campaign.target_job_title, validated, cc.campaign_id)
    source_page_id = pick_source_page(pages)

    validated
    |> Enum.zip(title_flags)
    |> Enum.each(fn {p, matches?} ->
      Person.create_validated(%{
        company_id: company.id,
        source_page_id: source_page_id,
        name: p.name,
        title: p.title,
        email: p.email,
        phone: p.phone,
        validated_in_markdown: true,
        matches_target_title: matches?
      })
    end)

    {:ok, _} = Company.touch_enriched(company)
    Transition.stage(cc, :contact, :done)
    {:ok, _} = Transition.terminate(cc, :enriched)

    contact_patch = first_contact_patch(validated, title_flags)
    if contact_patch != %{}, do: broadcast_contact(cc, contact_patch)

    :ok
  end

  defp short(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  defp short(reason), do: reason |> inspect() |> String.slice(0, 240)

  defp validate_all(candidates, haystack) do
    Enum.filter(candidates, fn p ->
      case ValidateInMarkdown.run(p.email, haystack) do
        {:ok, true} -> p.name != nil and p.email != nil
        _ -> false
      end
    end)
  end

  defp title_flags_for(_target, [], _cid), do: []
  defp title_flags_for(nil, list, _cid), do: List.duplicate(false, length(list))
  defp title_flags_for("", list, _cid), do: List.duplicate(false, length(list))

  defp title_flags_for(target, list, campaign_id) do
    titles = Enum.map(list, & &1.title)

    case MatchTitles.run(target, titles, campaign_id: campaign_id) do
      {:ok, flags} -> flags
      _ -> List.duplicate(false, length(list))
    end
  end

  defp pick_source_page(pages) do
    contact = Enum.find(pages, &(&1.in_navigation and not is_nil(&1.markdown)))
    landing = Enum.find(pages, &(&1.path == "/"))
    (contact || landing || %{id: nil}).id
  end

  defp first_contact_patch(validated, flags) do
    case Enum.zip(validated, flags) |> Enum.find(fn {_p, m} -> m end) do
      {p, _} -> %{contact_name: p.name, contact_title: p.title}
      _ -> %{}
    end
  end

  defp broadcast_contact(cc, patch) do
    Colt.Services.Enrichment.Broadcast.row(cc.campaign_id, cc.id, patch)
  end
end
