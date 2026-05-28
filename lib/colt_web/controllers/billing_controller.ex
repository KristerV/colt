defmodule ColtWeb.BillingController do
  @moduledoc """
  Stripe redirect endpoints. Hosted Checkout and Billing Portal both
  require a server-side `redirect(external: url)` after creating a
  session, so they live here rather than in a LiveView.
  """
  use ColtWeb, :controller

  alias Colt.Services.Billing.{CheckoutCreate, PortalCreate}

  def checkout(%{assigns: %{current_user: nil}} = conn, _params),
    do: redirect(conn, to: ~p"/sign-in")

  def checkout(conn, %{"price_id" => price_id}) do
    user = conn.assigns.current_user

    success_url = url(~p"/billing") <> "?status=success"
    cancel_url = url(~p"/pricing") <> "?status=canceled"

    case CheckoutCreate.run(user, price_id, success_url, cancel_url) do
      {:ok, %{url: url}} ->
        redirect(conn, external: url)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not start checkout: #{inspect(reason)}")
        |> redirect(to: ~p"/pricing")
    end
  end

  def portal(%{assigns: %{current_user: nil}} = conn, _params),
    do: redirect(conn, to: ~p"/sign-in")

  def portal(conn, _params) do
    user = conn.assigns.current_user

    case PortalCreate.run(user, url(~p"/billing")) do
      {:ok, %{url: url}} ->
        redirect(conn, external: url)

      {:error, :no_stripe_customer} ->
        conn
        |> put_flash(:error, "No active subscription — pick a plan first.")
        |> redirect(to: ~p"/pricing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not open billing portal: #{inspect(reason)}")
        |> redirect(to: ~p"/billing")
    end
  end
end
