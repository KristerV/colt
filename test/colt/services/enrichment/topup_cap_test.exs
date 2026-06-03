defmodule Colt.Services.Enrichment.TopupCapTest do
  @moduledoc """
  Proves the usage caps halt the Topup admission gate: once the owner's monthly
  contact allowance is spent, Topup idles and admits no further companies.
  """
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignCompany, Company}
  alias Colt.Services.Enrichment.Topup

  defp paid_user(capacity) do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, user} =
      Colt.Accounts.apply_subscription(
        user,
        %{
          monthly_contact_capacity: capacity,
          subscription_period_start: ~U[2026-05-01 00:00:00Z],
          subscription_period_end: ~U[2026-07-01 00:00:00Z],
          subscription_status: :active
        },
        authorize?: false
      )

    user
  end

  defp enriched_campaign(user, target) do
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)
    {:ok, c} = Campaign.update_filters(c, %{market: :ee}, actor: user)
    {:ok, c} = Campaign.finalize(c, target, actor: user)

    for i <- 1..target do
      company =
        Company.upsert_basic!(%{
          registry_code: "X#{i}",
          market: :ee,
          name: "Co #{i}",
          region: "Tallinn",
          status: :registered
        })

      {:ok, cc} =
        Ash.create(CampaignCompany, %{campaign_id: c.id, company_id: company.id},
          action: :create,
          authorize?: false
        )

      {:ok, _} = CampaignCompany.mark_enriched(cc, authorize?: false)
    end

    c
  end

  test "Topup idles and admits nothing once the contact cap is spent" do
    # capacity 2, then enrich 2 → remaining_capacity is 0.
    user = paid_user(2)
    campaign = enriched_campaign(user, 2)

    user =
      Ash.load!(user, [:remaining_capacity, :remaining_screening], authorize?: false)

    assert user.remaining_capacity == 0

    assert {:ok, :idle} = Topup.run(campaign.id)

    # No new campaign_companies were admitted beyond the 2 enriched ones.
    assert length(CampaignCompany.list_for_campaign!(campaign.id)) == 2
  end
end
