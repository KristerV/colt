defmodule Colt.Services.Enrichment.ContactDedupTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignCompany, Company, Person}
  alias Colt.Services.Enrichment.ContactDedup

  @owner "aare.kulli@gmail.com"

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "dedup@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp seed_campaign(user, name) do
    {:ok, c} = Campaign.create_draft(name, actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B", "CTO", :b2b, actor: user)
    c
  end

  defp seed_company(code) do
    Company.upsert_basic!(%{
      registry_code: code,
      market: :ee,
      name: "Co #{code}",
      region: "Tallinn",
      status: :registered
    })
  end

  defp seed_cc(campaign, company) do
    {:ok, cc} =
      Ash.create(CampaignCompany, %{campaign_id: campaign.id, company_id: company.id},
        action: :create,
        authorize?: false
      )

    cc
  end

  # The same human, registered at two different companies — so two Person rows
  # with one address. This is the shape picked_person_id cannot detect.
  defp seed_person(company, email) do
    {:ok, person} = Person.create_from_address(%{company_id: company.id, email: email})
    person
  end

  setup do
    user = seed_user()
    campaign = seed_campaign(user, "Hunt")
    co_a = seed_company("D1")
    co_b = seed_company("D2")

    %{
      user: user,
      campaign: campaign,
      cc_a: seed_cc(campaign, co_a),
      cc_b: seed_cc(campaign, co_b),
      person_a: seed_person(co_a, @owner),
      person_b: seed_person(co_b, @owner)
    }
  end

  test "the same human at two companies really is two Person rows", %{
    person_a: a,
    person_b: b
  } do
    assert a.id != b.id
    assert a.email == b.email
  end

  test "an address is free until someone picks it", %{campaign: c} do
    refute ContactDedup.taken?(c.id, @owner)
  end

  test "picking marks the address taken for everyone else", %{
    campaign: c,
    cc_a: cc_a,
    person_a: person_a
  } do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    assert ContactDedup.taken?(c.id, @owner)
  end

  test "the holder doesn't consider its own pick a duplicate", %{
    campaign: c,
    cc_a: cc_a,
    person_a: person_a
  } do
    {:ok, cc_a} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    refute ContactDedup.taken?(c.id, @owner, cc_a.id)
  end

  test "comparison is case-insensitive", %{campaign: c, cc_a: cc_a, person_a: person_a} do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    assert ContactDedup.taken?(c.id, "Aare.Kulli@Gmail.com")
  end

  test "another campaign may reach the same person", %{
    user: user,
    cc_a: cc_a,
    person_a: person_a
  } do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    other = seed_campaign(user, "Second hunt")
    refute ContactDedup.taken?(other.id, @owner)
  end

  test "the database rejects a second company picking the same address", %{
    cc_a: cc_a,
    cc_b: cc_b,
    person_a: person_a,
    person_b: person_b
  } do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    assert {:error, error} =
             CampaignCompany.set_picked_person(cc_b, person_b.id, @owner, authorize?: false)

    # The contract ResolveContact/ExtractContacts rely on to tell "lost the
    # race" from a real failure. If Ash ever changes the error shape, this is
    # what notices — silently, the race would become a hard job failure.
    assert ContactDedup.duplicate_error?(error)
  end

  test "a duplicate is reported against :campaign_id, so only the constraint name identifies it",
       %{cc_a: cc_a, cc_b: cc_b, person_a: person_a, person_b: person_b} do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    {:error, error} =
      CampaignCompany.set_picked_person(cc_b, person_b.id, @owner, authorize?: false)

    errors = error |> Ash.Error.to_error_class() |> Map.get(:errors, [])

    # Documents the surprise: Ash blames the identity's *first* field, not the
    # one that actually collided.
    assert Enum.any?(errors, &match?(%{field: :campaign_id}, &1))
    refute Enum.any?(errors, &match?(%{field: :picked_email}, &1))
  end

  test "an unrelated uniqueness violation is not mistaken for a duplicate contact", %{
    campaign: campaign,
    cc_a: cc_a
  } do
    # `identity :campaign_company` is [:campaign_id, :company_id] — it also
    # reports against :campaign_id. Matching on the field alone would classify
    # this as a duplicate contact and quietly send the company down the ladder.
    {:error, error} =
      Ash.create(CampaignCompany, %{campaign_id: campaign.id, company_id: cc_a.company_id},
        action: :create,
        authorize?: false
      )

    refute ContactDedup.duplicate_error?(error)
  end

  test "holder names the company already reaching the person", %{
    campaign: c,
    cc_a: cc_a,
    cc_b: cc_b,
    person_a: person_a
  } do
    {:ok, _} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)

    assert {:ok, holder} = ContactDedup.holder(c.id, @owner, cc_b.id)
    assert holder.company.name == "Co D1"
  end

  test "many companies can sit unpicked without colliding on NULL", %{
    campaign: campaign
  } do
    # The uniqueness index spans (campaign_id, picked_email); Postgres treats
    # NULLs as distinct, which is the only reason a campaign can hold thousands
    # of not-yet-resolved rows at once.
    for i <- 1..5 do
      company = seed_company("N#{i}")
      assert %CampaignCompany{picked_email: nil} = seed_cc(campaign, company)
    end

    {:ok, rows} = CampaignCompany.list_for_campaign(campaign.id, authorize?: false)
    assert length(rows) >= 5
  end

  test "clearing a pick releases the address", %{
    campaign: c,
    cc_a: cc_a,
    person_a: person_a
  } do
    {:ok, cc_a} = CampaignCompany.set_picked_person(cc_a, person_a.id, @owner, authorize?: false)
    assert ContactDedup.taken?(c.id, @owner)

    {:ok, _} = CampaignCompany.set_picked_person(cc_a, nil, nil, authorize?: false)
    refute ContactDedup.taken?(c.id, @owner)
  end
end
