defmodule Colt.Jobs.Enrichment.CheckWebsiteTest do
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Jobs.Enrichment.{CheckWebsite, GoogleSearch}
  alias Colt.Resources.{Campaign, CampaignCompany, Company}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp setup_cc do
    user = seed_user()
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)

    company =
      Company.upsert_basic!(%{
        registry_code: "X1",
        market: :ee,
        name: "Co X",
        region: "Tallinn",
        status: :registered
      })

    {:ok, cc} =
      Ash.create(CampaignCompany, %{campaign_id: c.id, company_id: company.id},
        action: :create,
        authorize?: false
      )

    %{user: user, campaign: c, company: company, cc: cc}
  end

  test "no website → enqueues GoogleSearch; CC stays :pending until downstream worker begins" do
    %{cc: cc} = setup_cc()

    assert :ok = CheckWebsite.perform(%Oban.Job{args: %{"campaign_company_id" => cc.id}})

    assert_enqueued(worker: GoogleSearch, args: %{"campaign_company_id" => cc.id})

    cc2 = CampaignCompany.get!(cc.id)
    assert cc2.status == :pending
  end
end
