defmodule Colt.Services.Sales.SetChecklistItemTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, ChecklistItem, ContactChecklistItem}
  alias Colt.Services.Sales.{CreateManualContact, SeedChecklist, SetChecklistItem}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp setup_contact do
    user = seed_user()
    {:ok, campaign} = Campaign.create_draft("Hunt", actor: user)

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
        actor: user
      )

    {user, campaign, contact}
  end

  defp ticks(contact_id, user) do
    {:ok, rows} = ContactChecklistItem.list_for_contact(contact_id, actor: user)
    rows
  end

  test "no rows exist until an item is actually ticked" do
    {user, campaign, contact} = setup_contact()
    {:ok, _} = SeedChecklist.run(campaign.id, actor: user)

    assert ticks(contact.id, user) == []
  end

  test "ticking creates a row, unticking keeps the row but clears done_at" do
    {user, campaign, contact} = setup_contact()
    {:ok, [first | _]} = SeedChecklist.run(campaign.id, actor: user)

    {:ok, ticked} = SetChecklistItem.run(contact.id, first.id, true, actor: user)
    assert ticked.done_at != nil
    assert ticked.checklist_item_id == first.id

    {:ok, unticked} = SetChecklistItem.run(contact.id, first.id, false, actor: user)
    assert unticked.done_at == nil

    # Still one row, not two — the second call updated rather than inserted.
    assert length(ticks(contact.id, user)) == 1
  end

  test "deleting a checklist item takes its ticks with it" do
    {user, campaign, contact} = setup_contact()
    {:ok, [first | _]} = SeedChecklist.run(campaign.id, actor: user)
    {:ok, _} = SetChecklistItem.run(contact.id, first.id, true, actor: user)

    assert length(ticks(contact.id, user)) == 1

    :ok = ChecklistItem.destroy(first, actor: user)

    assert ticks(contact.id, user) == []
  end

  test "SeedChecklist is explicit, so it stacks rather than no-ops" do
    {user, campaign, _contact} = setup_contact()

    {:ok, first} = SeedChecklist.run(campaign.id, actor: user)
    {:ok, _second} = SeedChecklist.run(campaign.id, actor: user)

    {:ok, all} = ChecklistItem.list_for_campaign(campaign.id, actor: user)
    assert length(all) == 2 * length(first)
  end
end
