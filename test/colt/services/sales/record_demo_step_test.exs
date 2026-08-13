defmodule Colt.Services.Sales.RecordDemoStepTest do
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact, StatusEvent}
  alias Colt.Services.Sales.{CreateManualContact, RecordDemoStep}

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

    {user, contact}
  end

  defp demo_events(contact_id, user) do
    {:ok, thread} = Colt.Resources.Thread.for_contact(contact_id, actor: user)
    {:ok, events} = StatusEvent.list_for_thread(thread.id, actor: user)
    Enum.filter(events, &(&1.kind == :demo))
  end

  defp reload(contact_id, user) do
    {:ok, contact} = CampaignContact.get(contact_id, actor: user)
    contact
  end

  test "each step stamps the contact and writes one feed entry" do
    {user, contact} = setup_contact()

    :ok = RecordDemoStep.run(contact.id, :started)
    :ok = RecordDemoStep.run(contact.id, :completed)
    :ok = RecordDemoStep.run(contact.id, :cta, cta_kind: "tahab kõnet")

    reloaded = reload(contact.id, user)
    assert reloaded.demo_started_at
    assert reloaded.demo_completed_at
    assert reloaded.demo_cta_at

    assert ["started", "completed", "cta"] = Enum.map(demo_events(contact.id, user), & &1.to)
  end

  test "the CTA entry carries which button was clicked" do
    {user, contact} = setup_contact()

    :ok = RecordDemoStep.run(contact.id, :cta, cta_kind: "tahab kõnet")

    assert [%{to: "cta", reason: "tahab kõnet"}] = demo_events(contact.id, user)
  end

  # A prospect who reloads the deck and hits Play again has not started twice.
  test "replaying the deck neither restamps nor repeats itself in the feed" do
    {user, contact} = setup_contact()

    :ok = RecordDemoStep.run(contact.id, :started)
    first = reload(contact.id, user).demo_started_at

    :ok = RecordDemoStep.run(contact.id, :started)
    :ok = RecordDemoStep.run(contact.id, :started)

    assert reload(contact.id, user).demo_started_at == first
    assert [%{to: "started"}] = demo_events(contact.id, user)
  end

  # Playback must never break on a bad `?c=`, and the deck doesn't check first.
  test "an unknown contact is a no-op rather than an error" do
    assert :ok = RecordDemoStep.run(Ash.UUID.generate(), :started)
  end
end
