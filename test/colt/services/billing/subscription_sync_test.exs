defmodule Colt.Services.Billing.SubscriptionSyncTest do
  @moduledoc """
  Proves the Stripe webhook → User state path: after a paid subscription
  event, the user must actually carry capacity + an :active status.
  """
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Services.Billing.SubscriptionSync

  @customer_id "cus_TEST123"
  @price_id "price_TEST_50"

  # Real values captured from a live test-mode invoice.paid event (€159 Growth).
  @real_customer "cus_UdPQUxJJ9DvuCz"
  @real_price "price_1SnE08LKuA0SOQTURcO4VeWD"
  @real_sub "sub_1Te8cQLKuA0SOQTUKXZFLoTt"

  setup do
    prev = Application.get_env(:colt, Colt.Billing, [])

    Application.put_env(
      :colt,
      Colt.Billing,
      Keyword.put(prev, :price_capacity, %{@price_id => 50, @real_price => 200})
    )

    on_exit(fn -> Application.put_env(:colt, Colt.Billing, prev) end)

    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "buyer@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    # Link the Stripe customer the way checkout.session.completed / CheckoutCreate does.
    {:ok, user} = Colt.Accounts.set_stripe_customer(user, @customer_id, authorize?: false)

    %{user: user}
  end

  defp reload(user), do: Ash.get!(User, user.id, authorize?: false)

  # Modern (Basil, 2025-03-31+) subscription shape: period bounds live on the
  # item, NOT at the top level.
  defp sub_object_modern(status) do
    %{
      "id" => "sub_TEST",
      "customer" => @customer_id,
      "status" => status,
      "items" => %{
        "data" => [
          %{
            "price" => %{"id" => @price_id},
            "current_period_start" => 1_700_000_000,
            "current_period_end" => 1_702_592_000
          }
        ]
      }
    }
  end

  # Legacy shape: period bounds at the top level of the subscription.
  defp sub_object_legacy(status) do
    %{
      "id" => "sub_TEST",
      "customer" => @customer_id,
      "status" => status,
      "current_period_start" => 1_700_000_000,
      "current_period_end" => 1_702_592_000,
      "items" => %{"data" => [%{"price" => %{"id" => @price_id}}]}
    }
  end

  defp event(type, object), do: %Stripe.Event{type: type, data: %{object: object}}

  describe "customer.subscription.created" do
    test "attaches capacity + active status to the user", %{user: user} do
      ev = event("customer.subscription.created", sub_object_modern("active"))

      assert {:ok, :applied} = SubscriptionSync.run(ev)

      user = reload(user)
      assert user.monthly_contact_capacity == 50
      assert user.subscription_status == :active
    end

    test "legacy shape sets the period bounds", %{user: user} do
      ev = event("customer.subscription.created", sub_object_legacy("active"))
      assert {:ok, :applied} = SubscriptionSync.run(ev)

      user = reload(user)
      refute is_nil(user.subscription_period_start)
      refute is_nil(user.subscription_period_end)
    end

    test "modern (Basil) shape captures the per-item period bounds", %{user: user} do
      ev = event("customer.subscription.created", sub_object_modern("active"))
      assert {:ok, :applied} = SubscriptionSync.run(ev)

      user = reload(user)
      # Period bounds moved onto items.data[] in Stripe API 2025-03-31+.
      assert user.subscription_period_start == DateTime.from_unix!(1_700_000_000)
      assert user.subscription_period_end == DateTime.from_unix!(1_702_592_000)
    end
  end

  describe "checkout.session.completed alone" do
    test "does it grant the tier, or only link the customer?" do
      fresh =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "fresh@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      session = %{
        "customer" => "cus_FRESH",
        "client_reference_id" => fresh.id,
        "subscription" => "sub_FRESH"
      }

      assert {:ok, _} =
               SubscriptionSync.run(event("checkout.session.completed", session))

      fresh = Ash.get!(User, fresh.id, authorize?: false)
      assert fresh.stripe_customer_id == "cus_FRESH"
      # The tier is NOT applied by this event on its own.
      assert fresh.monthly_contact_capacity == 0
      assert fresh.subscription_status == :none
    end
  end

  describe "incomplete subscription status" do
    test "an 'incomplete' subscription does not read as paid", %{user: user} do
      ev = event("customer.subscription.created", sub_object_modern("incomplete"))
      assert {:ok, :applied} = SubscriptionSync.run(ev)

      user = reload(user)
      # capacity is set, but status is :none — UI gates on :active
      assert user.subscription_status == :none
    end
  end

  describe "real Stripe struct shape (regression: webhook 500 on struct access)" do
    # `Stripe.Webhook.construct_event` runs the payload through
    # `Stripe.Converter`, so `event.data.object` is a TYPED STRUCT with atom
    # keys — not a string-keyed map. The handler must read it via Map access,
    # never `obj["key"]` (which raises `Stripe.Invoice.fetch/2 is undefined`
    # and 500s the webhook, leaving the user linked but with no plan).
    test "applies the plan from the real customer.subscription struct" do
      user =
        User
        |> Ash.Changeset.for_create(:seed, %{email: "real@example.com"}, authorize?: false)
        |> Ash.create!(authorize?: false)

      {:ok, _} = Colt.Accounts.set_stripe_customer(user, @real_customer, authorize?: false)

      # The subscription referenced by the captured €159 invoice.paid event,
      # in the exact struct form construct_event produces.
      sub = %Stripe.Subscription{
        id: @real_sub,
        customer: @real_customer,
        status: "active",
        current_period_start: 1_780_469_378,
        current_period_end: 1_783_061_378,
        items: %Stripe.List{
          object: "list",
          data: [
            %Stripe.SubscriptionItem{
              id: "si_UdPRUDnkccaeMX",
              price: %Stripe.Price{id: @real_price}
            }
          ]
        }
      }

      event = %Stripe.Event{type: "customer.subscription.created", data: %{object: sub}}

      assert {:ok, :applied} = SubscriptionSync.run(event)

      user = reload(user)
      assert user.subscription_status == :active
      assert user.monthly_contact_capacity == 200
      assert user.subscription_period_start == DateTime.from_unix!(1_780_469_378)
      assert user.subscription_period_end == DateTime.from_unix!(1_783_061_378)
    end
  end
end
