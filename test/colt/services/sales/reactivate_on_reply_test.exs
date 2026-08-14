defmodule Colt.Services.Sales.ReactivateOnReplyTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, StatusEvent}
  alias Colt.Services.Sales.{CreateManualContact, ReactivateOnReply, SetNextAction, SetOutcome}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp setup_contact(attrs \\ %{}) do
    user = seed_user()
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)

    {:ok, contact} =
      CreateManualContact.run(
        campaign.id,
        Map.merge(
          %{
            name: "Jane Tamm",
            company_name: "Kohvik OÜ",
            registry_code: "1#{System.unique_integer([:positive])}",
            market: :ee,
            in_funnel_sales?: true,
            in_funnel_sending?: false
          },
          attrs
        ),
        actor: user
      )

    {user, contact}
  end

  defp reload(contact_id, user) do
    {:ok, contact} = CampaignContact.get(contact_id, actor: user, load: [:sales_bucket])
    contact
  end

  defp next_action_events(contact_id, user) do
    {:ok, thread} = Colt.Resources.Thread.for_contact(contact_id, actor: user)
    {:ok, events} = StatusEvent.list_for_thread(thread.id, actor: user)
    Enum.filter(events, &(&1.kind == :next_action))
  end

  defp in_days(n), do: DateTime.add(DateTime.utc_now(), n * 86_400, :second)

  test "a scheduled contact who replies drops back into Now" do
    {user, contact} = setup_contact()
    {:ok, _} = SetNextAction.run(contact.id, in_days(7), actor: user)

    {:ok, updated} = ReactivateOnReply.run(contact.id)

    assert is_nil(updated.next_action_at)
    assert is_nil(reload(contact.id, user).next_action_at)
    assert reload(contact.id, user).sales_bucket == :now
  end

  test "the feed says why the date went away" do
    {user, contact} = setup_contact()
    {:ok, _} = SetNextAction.run(contact.id, in_days(7), actor: user)

    {:ok, _} = ReactivateOnReply.run(contact.id)

    assert [%{to: nil, reason: "prospect replied"} | _] =
             contact.id |> next_action_events(user) |> Enum.reverse()
  end

  test "a contact already in Now is untouched — no date, no feed noise" do
    {user, contact} = setup_contact()

    assert {:ok, :skipped} = ReactivateOnReply.run(contact.id)
    assert next_action_events(contact.id, user) == []
  end

  # A closed deal's bucket comes from its outcome; reopening it is a human's call.
  test "a won or lost contact is left closed" do
    {user, contact} = setup_contact()
    {:ok, _} = SetNextAction.run(contact.id, in_days(7), actor: user)
    {:ok, _} = SetOutcome.run(contact.id, :won, actor: user)

    assert {:ok, :skipped} = ReactivateOnReply.run(contact.id)
    assert reload(contact.id, user).outcome == :won
  end

  test "a contact outside the sales funnel has no bucket to return to" do
    {user, contact} = setup_contact(%{in_funnel_sales?: false, in_funnel_sending?: true})

    {:ok, _} =
      CampaignContact.set_next_action(contact, in_days(7), actor: user)

    assert {:ok, :skipped} = ReactivateOnReply.run(contact.id)
    assert reload(contact.id, user).next_action_at
  end
end
