defmodule Colt.Services.Sending.AssignInbox do
  @moduledoc """
  Sticky inbox picker for a CampaignContact. Returns the EmailAccount with
  the lowest `(approved_today / daily_quota)` ratio among healthy, enrolled,
  non-paused accounts in the campaign. Ties broken by inserted_at.

  Phase E4: this is the naive interpretation; the full §5.2 burst scheduler
  lands in E5.
  """

  alias Colt.Resources.{CampaignContact, CampaignEmailAccount}

  def run(campaign_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, rows} <- load_enrollments(campaign_id, actor),
         {:ok, candidate} <- pick(rows, actor) do
      {:ok, candidate}
    end
  end

  defp load_enrollments(campaign_id, actor) do
    rows =
      CampaignEmailAccount.list_for_campaign!(campaign_id,
        load: [:email_account],
        actor: actor,
        authorize?: actor != nil
      )
      |> Enum.reject(& &1.paused?)
      |> Enum.filter(fn r -> r.email_account && r.email_account.status == :healthy end)

    {:ok, rows}
  end

  defp pick([], _actor), do: {:error, :no_healthy_inbox}

  defp pick(rows, actor) do
    sorted =
      rows
      |> Enum.map(fn row ->
        ea = row.email_account
        count = count_today(ea.id, actor)
        quota = max(ea.daily_quota, 1)
        {count / quota, row.inserted_at, ea}
      end)
      |> Enum.sort_by(fn {ratio, ts, _} -> {ratio, ts} end)

    case sorted do
      [{_, _, ea} | _] -> {:ok, ea}
      [] -> {:error, :no_healthy_inbox}
    end
  end

  defp count_today(email_account_id, actor) do
    case CampaignContact.count_assigned_today(email_account_id,
           actor: actor,
           authorize?: actor != nil
         ) do
      {:ok, list} -> length(list)
      _ -> 0
    end
  end
end
