defmodule Colt.Services.Billing.CheckoutCreate do
  @moduledoc """
  Creates a Stripe Checkout Session for an authenticated user against a
  specific `price_id`. Ensures the user has a Stripe customer first.
  Returns the hosted checkout URL.
  """

  alias Colt.Accounts.User

  def run(%User{} = user, price_id, success_url, cancel_url)
      when is_binary(price_id) and is_binary(success_url) and is_binary(cancel_url) do
    with {:ok, user} <- ensure_customer(user),
         {:ok, session} <- create_session(user, price_id, success_url, cancel_url) do
      {:ok, %{url: session.url, session_id: session.id, user: user}}
    end
  end

  defp ensure_customer(%User{stripe_customer_id: id} = user) when is_binary(id),
    do: {:ok, user}

  defp ensure_customer(%User{} = user) do
    with {:ok, %Stripe.Customer{id: customer_id}} <-
           Stripe.Customer.create(%{
             email: to_string(user.email),
             metadata: %{user_id: user.id}
           }),
         {:ok, updated} <-
           Colt.Accounts.set_stripe_customer(user, customer_id, authorize?: false) do
      {:ok, updated}
    end
  end

  defp create_session(user, price_id, success_url, cancel_url) do
    Stripe.Checkout.Session.create(%{
      mode: "subscription",
      customer: user.stripe_customer_id,
      client_reference_id: user.id,
      success_url: success_url,
      cancel_url: cancel_url,
      line_items: [%{price: price_id, quantity: 1}],
      allow_promotion_codes: true,
      tax_id_collection: %{enabled: true},
      billing_address_collection: "required",
      customer_update: %{name: "auto", address: "auto"}
    })
  end
end
