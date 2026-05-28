defmodule Colt.Services.Billing.PortalCreate do
  @moduledoc """
  Creates a Stripe Billing Portal session so the user can change plan,
  update card, or cancel. Returns the hosted portal URL.
  """

  alias Colt.Accounts.User

  def run(%User{stripe_customer_id: nil}, _return_url),
    do: {:error, :no_stripe_customer}

  def run(%User{stripe_customer_id: customer_id}, return_url) when is_binary(return_url) do
    with {:ok, session} <-
           Stripe.BillingPortal.Session.create(%{
             customer: customer_id,
             return_url: return_url
           }) do
      {:ok, %{url: session.url}}
    end
  end
end
