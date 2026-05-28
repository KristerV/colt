defmodule ColtWeb.StripeWebhookController do
  @moduledoc """
  Receives Stripe webhook events, verifies signature against the raw body
  cached by `ColtWeb.Plugs.StripeBodyReader`, and dispatches to
  `Colt.Services.Billing.SubscriptionSync`.
  """
  use ColtWeb, :controller

  require Logger

  alias Colt.Services.Billing.SubscriptionSync

  def create(conn, _params) do
    secret = Application.fetch_env!(:colt, Colt.Billing)[:webhook_secret]
    payload = conn.assigns[:raw_body] || ""

    [signature | _] = get_req_header(conn, "stripe-signature") ++ [""]

    case Stripe.Webhook.construct_event(payload, signature, secret) do
      {:ok, %Stripe.Event{} = event} ->
        _ = SubscriptionSync.run(event)
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("[stripe] webhook signature invalid: #{inspect(reason)}")
        send_resp(conn, 400, "invalid signature")
    end
  end
end
