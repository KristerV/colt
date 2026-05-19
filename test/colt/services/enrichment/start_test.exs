defmodule Colt.Services.Enrichment.StartTest do
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Resources.Campaign
  alias Colt.Services.Enrichment.Start

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  setup do
    user = seed_user()
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)
    {:ok, c} = Campaign.update_filters(c, %{market: :ee}, actor: user)
    %{user: user, campaign: c}
  end

  test "run/3 finalizes campaign with target and schedules a Topup",
       %{user: user, campaign: c} do
    {:ok, %{campaign: c2}} = Start.run(c, 50, user)

    assert c2.status == :enriching
    assert c2.target_contact_count == 50
    assert c2.finalized_at

    assert_enqueued(worker: Colt.Jobs.Enrichment.Topup, args: %{campaign_id: c2.id})
  end
end
