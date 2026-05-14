defmodule Colt.Services.Enrichment.StartTest do
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignCompany, Company}
  alias Colt.Services.Enrichment.Start

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_companies(n) do
    for i <- 1..n do
      Company.upsert_basic!(%{
        registry_code: "TEST#{i}",
        market: :ee,
        name: "Co #{i}",
        region: "Tallinn",
        status: :registered
      })
    end
  end

  setup do
    user = seed_user()
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)
    %{user: user, campaign: c}
  end

  test "run/3 creates CC rows, finalizes campaign, enqueues CheckWebsite",
       %{user: user, campaign: c} do
    seed_companies(5)

    {:ok, %{count: count, campaign: c2}} = Start.run(c, %{market: :ee}, user)

    assert count == 5
    assert c2.status == :enriching
    assert c2.finalized_at

    ccs = Ash.read!(CampaignCompany)
    assert length(ccs) == 5
    assert Enum.all?(ccs, &(&1.status == :pending))

    assert_enqueued(worker: Colt.Jobs.Enrichment.CheckWebsite)
  end

  test "run/3 caps at :enrichment_max_companies even when filter matches more",
       %{user: user, campaign: c} do
    cap = Application.fetch_env!(:colt, :enrichment_max_companies)
    seed_companies(cap + 10)

    {:ok, %{count: count}} = Start.run(c, %{market: :ee}, user)

    assert count == cap
  end
end
