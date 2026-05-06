defmodule Colt.Jobs.Enrichment.SummarizeCompany do
  @moduledoc """
  §6.5 — GLM 4.7 turns landing markdown into a one-paragraph company summary.
  Cached on `Company.ai_summary` and reused across campaigns (spec §7).
  Enqueues `MatchICP` on success.
  """
  use Oban.Worker, queue: :ai, max_attempts: 2

  alias Colt.Jobs.Enrichment.MatchICP
  alias Colt.Resources.{CampaignCompany, Company, Page}

  alias Colt.Services.Enrichment.{
    Broadcast,
    FailureMessage,
    Freshness,
    SummarizeLanding,
    Transition
  }

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
        {user_msg, detail} = FailureMessage.run(:website, "no landing markdown to summarise")
        Transition.stage(cc, :website, :fall)

        {:ok, _} =
          Transition.terminate(cc, :failed,
            stage: :website,
            reason: user_msg,
            detail: detail
          )

        :ok

      md ->
        case SummarizeLanding.run(md, campaign_id: cc.campaign_id) do
          {:ok, summary} ->
            {:ok, _} = Company.set_ai_summary(company, summary)
            Broadcast.row(cc.campaign_id, cc.id, %{summary: summary})
            Transition.stage(cc, :website, :done)
            enqueue_next(cc)
            :ok

          {:error, reason} ->
            {user_msg, detail} = FailureMessage.run(:website, reason)
            Transition.stage(cc, :website, :fail)

            {:ok, _} =
              Transition.terminate(cc, :failed,
                stage: :website,
                reason: user_msg,
                detail: detail
              )

            {:error, detail}
        end
    end
  end

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
