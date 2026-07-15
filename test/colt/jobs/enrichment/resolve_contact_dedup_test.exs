defmodule Colt.Jobs.Enrichment.ResolveContactDedupTest do
  @moduledoc """
  The end-to-end guarantee: one human gets at most one email per campaign, even
  when they registered several of the companies we're targeting.

  Stays offline by pre-setting `registry_email_kind`, so the address classifier
  never runs.
  """
  use Colt.DataCase, async: false
  use Oban.Testing, repo: Colt.Repo

  alias Colt.Accounts.User
  alias Colt.Jobs.Enrichment.{ResolveContact, VerifyEmail}
  alias Colt.Resources.{Campaign, CampaignCompany, Company, Person}

  @owner "aare.kulli@gmail.com"

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "rc@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_company(code, attrs) do
    company =
      Company.upsert_basic!(%{
        registry_code: code,
        market: :ee,
        name: "Co #{code}",
        region: "Tallinn",
        status: :registered
      })

    {:ok, company} =
      Ash.update(company, %{registry_email: attrs.registry_email},
        action: :patch_details,
        authorize?: false
      )

    case attrs[:generic_email] do
      nil ->
        company

      email ->
        {:ok, company} = Company.set_generic_email(company, email, authorize?: false)
        company
    end
  end

  defp seed_cc(campaign, company) do
    {:ok, cc} =
      Ash.create(CampaignCompany, %{campaign_id: campaign.id, company_id: company.id},
        action: :create,
        authorize?: false
      )

    cc
  end

  defp run(cc, args \\ %{}) do
    perform_job(ResolveContact, Map.merge(%{"campaign_company_id" => cc.id}, args))
  end

  defp reload(cc), do: CampaignCompany.get!(cc.id, authorize?: false)

  setup do
    user = seed_user()
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)

    {:ok, campaign} =
      Campaign.set_icp(
        campaign,
        "",
        "",
        :both,
        %{reach_owner?: true, reach_title?: false, reach_generic?: true, require_website?: false},
        actor: user
      )

    # Same human behind both companies — the exact shape from the EE import,
    # where 180 addresses are the registry contact for 2+ companies.
    co_a = seed_company("R1", %{registry_email: @owner})
    co_b = seed_company("R2", %{registry_email: @owner, generic_email: "info@r2.ee"})

    for co <- [co_a, co_b] do
      {:ok, _} = Company.set_registry_email_kind(co, :personal, authorize?: false)
    end

    %{campaign: campaign, cc_a: seed_cc(campaign, co_a), cc_b: seed_cc(campaign, co_b)}
  end

  test "the first company reaches the owner", %{cc_a: cc_a} do
    assert :ok = run(cc_a)

    cc_a = reload(cc_a)
    assert cc_a.picked_email == @owner
    assert {:ok, %Person{email: @owner}} = Person.get(cc_a.picked_person_id)
    assert_enqueued(worker: VerifyEmail, args: %{campaign_company_id: cc_a.id})
  end

  test "the second company does not email the same human again", %{cc_a: cc_a, cc_b: cc_b} do
    assert :ok = run(cc_a)
    assert :ok = run(cc_b)

    cc_b = reload(cc_b)
    refute cc_b.picked_email == @owner
    refute_enqueued(worker: VerifyEmail, args: %{campaign_company_id: cc_b.id})
  end

  test "instead it drops to its own generic inbox", %{cc_a: cc_a, cc_b: cc_b} do
    assert :ok = run(cc_a)
    assert :ok = run(cc_b)

    # The owner rung missed on a duplicate, so the ladder advanced rather than
    # writing the company off.
    assert_enqueued(
      worker: ResolveContact,
      args: %{campaign_company_id: cc_b.id, rung: "generic"}
    )

    assert :ok = run(cc_b, %{"rung" => "generic"})

    cc_b = reload(cc_b)
    assert cc_b.picked_email == "info@r2.ee"
    assert_enqueued(worker: VerifyEmail, args: %{campaign_company_id: cc_b.id})
  end

  test "with no fallback rung, a duplicate ends the company and says why", %{
    campaign: campaign,
    cc_a: cc_a,
    cc_b: cc_b
  } do
    {:ok, _} =
      Ash.update(campaign, %{reach_generic?: false},
        action: :set_icp,
        authorize?: false
      )

    assert :ok = run(cc_a)
    assert :ok = run(cc_b)

    cc_b = reload(cc_b)
    assert cc_b.status == :no_contacts
    assert cc_b.rejection_reason =~ @owner
    assert cc_b.rejection_reason =~ "already being contacted"
    # Names the company holding the address, so the user can see it isn't a bug.
    assert cc_b.rejection_reason =~ "Co R1"
  end

  test "a different campaign may still reach the same human", %{cc_a: cc_a} do
    assert :ok = run(cc_a)

    user2 = seed_user_named("other@example.com")
    {:ok, c2} = Campaign.create_draft("Second", actor: user2)

    {:ok, c2} =
      Campaign.set_icp(c2, "", "", :both, %{reach_owner?: true, reach_title?: false},
        actor: user2
      )

    {:ok, co_a} = Company.get(cc_a.company_id)
    cc = seed_cc(c2, co_a)

    assert :ok = run(cc)
    assert reload(cc).picked_email == @owner
  end

  defp seed_user_named(email) do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end
end
