defmodule Colt.Services.Sales.ClaimContactTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, StatusEvent}
  alias Colt.Services.Sales.{ClaimContact, CreateManualContact}

  defp seed_user(email) do
    User
    |> Ash.Changeset.for_create(:seed, %{email: email}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp setup_contact do
    owner = seed_user("owner@example.com")
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: owner)

    {:ok, contact} =
      CreateManualContact.run(
        campaign.id,
        %{
          name: "Jane Tamm",
          company_name: "Kohvik OÜ",
          registry_code: "1#{System.unique_integer([:positive])}",
          market: :ee,
          in_funnel_sales?: true,
          in_funnel_sending?: false
        },
        actor: owner
      )

    {owner, contact}
  end

  defp assigned_events(contact_id, actor) do
    {:ok, thread} = Colt.Resources.Thread.for_contact(contact_id, actor: actor)
    {:ok, events} = StatusEvent.list_for_thread(thread.id, actor: actor)
    Enum.filter(events, &(&1.kind == :assigned))
  end

  test "claiming assigns the acting user" do
    {owner, contact} = setup_contact()

    {:ok, claimed} = ClaimContact.run(contact.id, actor: owner)

    assert claimed.assigned_to_id == owner.id
  end

  test "claiming again overwrites whoever had it before — no contest" do
    {owner, contact} = setup_contact()
    # Not the campaign owner, so must be an admin to touch it (mirrors the
    # sales funnel LiveView, which is admin-only).
    {:ok, other} = Colt.Accounts.grant_admin(seed_user("teammate@example.com"), authorize?: false)

    {:ok, _} = ClaimContact.run(contact.id, actor: owner)
    {:ok, reclaimed} = ClaimContact.run(contact.id, actor: other)

    assert reclaimed.assigned_to_id == other.id
  end

  test "the feed records who it was assigned to" do
    {owner, contact} = setup_contact()

    {:ok, _} = ClaimContact.run(contact.id, actor: owner)

    assert [%{from: nil, to: "owner@example.com"}] = assigned_events(contact.id, owner)
  end
end
