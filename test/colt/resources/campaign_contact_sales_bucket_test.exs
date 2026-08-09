defmodule Colt.Resources.CampaignContactSalesBucketTest do
  @moduledoc """
  The bucket calculation is the whole board — every column is derived from it,
  so the boundary cases (dated today, never dated, outcome overriding a date)
  are what keep contacts from disappearing.
  """
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignContact}
  alias Colt.SalesClock
  alias Colt.Services.Sales.{CreateManualContact, SetNextAction, SetOutcome}

  defp seed_user do
    User
    |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp sales_contact(user) do
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

    contact
  end

  defp bucket(contact_id) do
    CampaignContact
    |> Ash.get!(contact_id, load: [:sales_bucket], authorize?: false)
    |> Map.fetch!(:sales_bucket)
  end

  describe "sales_bucket" do
    test "a contact with no next action is Now — untriaged must never hide" do
      user = seed_user()
      contact = sales_contact(user)

      assert contact.next_action_at == nil
      assert bucket(contact.id) == :now
    end

    test "dated today is Now, not Later" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(0), actor: user)

      assert bucket(contact.id) == :now
    end

    test "an overdue date is Now" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(-5), actor: user)

      assert bucket(contact.id) == :now
    end

    test "a date after today is Later" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(1), actor: user)

      assert bucket(contact.id) == :later
    end

    test "an outcome wins over any date" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(3), actor: user)
      {:ok, _} = SetOutcome.run(contact.id, :won, actor: user)

      assert bucket(contact.id) == :won
    end
  end

  describe "SetOutcome" do
    test "closing clears the next action so a reopen lands back in Now" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(10), actor: user)
      {:ok, lost} = SetOutcome.run(contact.id, :lost, reason: "went elsewhere", actor: user)

      assert lost.outcome == :lost
      assert lost.outcome_reason == "went elsewhere"
      assert lost.outcome_at != nil
      assert lost.next_action_at == nil
      assert bucket(contact.id) == :lost

      {:ok, reopened} = SetOutcome.run(contact.id, nil, actor: user)

      assert reopened.outcome == nil
      assert bucket(contact.id) == :now
    end

    test "a blank lost reason is stored as nil, not an empty string" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, lost} = SetOutcome.run(contact.id, :lost, reason: "   ", actor: user)

      assert lost.outcome_reason == nil
    end
  end

  describe "SetNextAction" do
    test "clearing the date returns the contact to Now" do
      user = seed_user()
      contact = sales_contact(user)

      {:ok, _} = SetNextAction.run(contact.id, SalesClock.in_days(4), actor: user)
      assert bucket(contact.id) == :later

      {:ok, cleared} = SetNextAction.run(contact.id, nil, actor: user)

      assert cleared.next_action_at == nil
      assert bucket(contact.id) == :now
    end
  end
end
