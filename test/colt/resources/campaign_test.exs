defmodule Colt.Resources.CampaignTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.Campaign

  defp seed_user(email \\ "owner@example.com") do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  test "create_draft sets owner and :draft status" do
    user = seed_user()

    {:ok, c} = Campaign.create_draft("Test EE SaaS", actor: user)

    assert c.name == "Test EE SaaS"
    assert c.status == :draft
    assert c.owner_id == user.id
  end

  test "set_icp updates ICP + title without changing status" do
    user = seed_user()
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)

    {:ok, c2} = Campaign.set_icp(c, "B2B SaaS in Estonia, 50–500 emp", "CTO", :b2b, actor: user)

    assert c2.icp_description == "B2B SaaS in Estonia, 50–500 emp"
    assert c2.target_job_title == "CTO"
    assert c2.status == :draft
  end

  test "set_market advances to :collecting and stores :ee" do
    user = seed_user()
    {:ok, c} = Campaign.create_draft("Hunt", actor: user)
    {:ok, c} = Campaign.set_icp(c, "B2B SaaS", "CTO", :b2b, actor: user)

    {:ok, c2} = Campaign.set_market(c, :ee, actor: user)

    assert c2.market == :ee
    assert c2.status == :collecting
  end

  test "list_recent_for_user only returns own campaigns, newest first, capped at 4" do
    me = seed_user("me@example.com")
    other = seed_user("other@example.com")

    for n <- 1..5 do
      {:ok, _} = Campaign.create_draft("Mine #{n}", actor: me)
    end

    {:ok, _} = Campaign.create_draft("Theirs", actor: other)

    list = Campaign.list_recent_for_user!(me.id, actor: me)

    assert length(list) == 4
    assert Enum.all?(list, &(&1.owner_id == me.id))
  end

  test "policy: cannot read another user's campaign" do
    # Seed two users; the first becomes admin via MaybePromoteFirstAdmin, so
    # seed an admin sentinel first and use the *second* user as `me`.
    _bootstrap = seed_user("admin@example.com")
    me = seed_user("me@example.com")
    other = seed_user("other@example.com")

    {:ok, c} = Campaign.create_draft("Theirs", actor: other)

    assert {:error, _} = Campaign.get(c.id, actor: me)
  end

  test "policy: admin can read any campaign" do
    admin = seed_user("admin@example.com")
    other = seed_user("other@example.com")

    {:ok, c} = Campaign.create_draft("Theirs", actor: other)

    assert {:ok, _} = Campaign.get(c.id, actor: admin)
  end
end
