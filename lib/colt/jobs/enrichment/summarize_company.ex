defmodule Colt.Jobs.Enrichment.SummarizeCompany do
  @moduledoc """
  §6.5 — GLM 4.7 turns landing markdown into a one-paragraph company summary.
  Cached on `Company.ai_summary` and reused across campaigns (spec §7).
  Enqueues `MatchICP` on success.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Jobs.Enrichment.MatchICP
  alias Colt.Resources.{CampaignCompany, Company, Page}
  alias Colt.Services.Enrichment.{Freshness, SummarizeLanding, Transition}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}}) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, company} <- Company.get(cc.company_id) do
      cond do
        Freshness.has_summary?(company) and Freshness.company_fresh?(company) ->
          Transition.stage(cc, :website, :skip)
          enqueue_next(cc)
          :ok

        true ->
          run_summary(cc, company)
      end
    end
  end

  defp run_summary(cc, company) do
    Transition.stage(cc, :website, :work)

    case landing_markdown(company) do
      "" ->
        Transition.stage(cc, :website, :fall)

        {:ok, _} =
          Transition.terminate(cc, :failed,
            stage: :website,
            reason: "no landing markdown to summarise"
          )

        :ok

      md ->
        case SummarizeLanding.run(md, campaign_id: cc.campaign_id) do
          {:ok, summary} ->
            {:ok, _} = Company.set_ai_summary(company, summary)
            Transition.stage(cc, :website, :done)
            enqueue_next(cc)
            :ok

          {:error, reason} ->
            Transition.stage(cc, :website, :fail)
            {:ok, _} = Transition.terminate(cc, :failed, stage: :website, reason: short(reason))
            {:error, inspect(reason)}
        end
    end
  end

  defp short(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  defp short(reason), do: reason |> inspect() |> String.slice(0, 240)

  defp enqueue_next(cc) do
    %{campaign_company_id: cc.id} |> MatchICP.new() |> Oban.insert!()
  end

  defp landing_markdown(company) do
    case Page.for_company(company.id) do
      {:ok, pages} ->
        case Enum.find(pages, &(&1.path == "/")) do
          %Page{markdown: md} when is_binary(md) -> md
          _ -> ""
        end

      _ ->
        ""
    end
  end
end
