defmodule Colt.Services.Billing.RevenueSync do
  @moduledoc """
  Pull paid Stripe invoices for every Stripe-linked client and upsert them as
  `:subscription` rows in `Colt.Resources.RevenueEntry` (deduped on the Stripe
  invoice id, so re-running is idempotent). Clients who pay outside Stripe are
  untouched — their revenue is entered by hand as `:invoice` / `:manual` rows.
  """

  alias Colt.Accounts
  alias Colt.Resources.RevenueEntry

  require Logger

  @page_limit 100

  def run do
    with {:ok, users} <- Accounts.users_with_stripe_customer(authorize?: false),
         {:ok, entries} <- sync_users(users) do
      {:ok, %{clients: length(users), entries: entries}}
    end
  end

  defp sync_users(users) do
    entries = Enum.reduce(users, 0, fn user, acc -> acc + sync_user(user) end)
    {:ok, entries}
  end

  defp sync_user(%{id: user_id, stripe_customer_id: customer_id}) when is_binary(customer_id) do
    case Stripe.Invoice.list(%{customer: customer_id, status: :paid, limit: @page_limit}) do
      {:ok, %{data: invoices} = page} ->
        maybe_warn_truncated(page, customer_id)

        invoices
        |> Enum.filter(&paid?/1)
        |> Enum.map(&upsert_invoice(&1, user_id))
        |> Enum.count(&match?({:ok, _}, &1))

      {:error, reason} ->
        Logger.warning("[revenue_sync] stripe list failed for #{customer_id}: #{inspect(reason)}")
        0
    end
  end

  defp sync_user(_), do: 0

  defp paid?(%{amount_paid: paid}) when is_integer(paid), do: paid > 0
  defp paid?(_), do: false

  defp upsert_invoice(invoice, user_id) do
    RevenueEntry.upsert_stripe(
      %{
        user_id: user_id,
        month: invoice_month(invoice),
        amount_usd: Decimal.div(Decimal.new(invoice.amount_paid), 100),
        stripe_invoice_id: invoice.id
      },
      authorize?: false
    )
  end

  defp invoice_month(%{created: unix}) when is_integer(unix) do
    unix |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m")
  end

  defp maybe_warn_truncated(%{has_more: true}, customer_id) do
    Logger.warning(
      "[revenue_sync] >#{@page_limit} paid invoices for #{customer_id}; only the latest page synced"
    )
  end

  defp maybe_warn_truncated(_, _), do: :ok
end
