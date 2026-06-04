defmodule Colt.Jobs.Enrichment.CheckWebsiteSuppressionTest do
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Jobs.Enrichment.{CheckWebsite, FetchLanding, GoogleSearch}
  alias Colt.Resources.{Campaign, CampaignCompany, Company, SuppressedDomain}

  defp setup_cc(website_url) do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    {:ok, c} = Campaign.set_market(c, :ee, actor: user)

    company =
      Company.upsert_basic!(%{
        registry_code: "X1",
        market: :ee,
        name: "Co X",
        region: "Tallinn",
        status: :registered
      })

    {:ok, company} = Company.set_website(company, website_url, :registry)

    {:ok, cc} =
      Ash.create(CampaignCompany, %{campaign_id: c.id, company_id: company.id},
        action: :create,
        authorize?: false
      )

    %{campaign: c, company: company, cc: cc}
  end

  test "suppressed website domain terminates :excluded and enqueues no downstream work" do
    %{campaign: c, cc: cc} = setup_cc("https://www.acme.com")
    {:ok, _} = SuppressedDomain.create(c.id, "acme.com", authorize?: false)

    assert :ok = CheckWebsite.perform(%Oban.Job{args: %{"campaign_company_id" => cc.id}})

    refute_enqueued(worker: FetchLanding)
    refute_enqueued(worker: GoogleSearch)

    assert %{status: :excluded, rejection_reason: "already contacted"} =
             CampaignCompany.get!(cc.id)
  end
end
