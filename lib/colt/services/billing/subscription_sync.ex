defmodule Colt.Services.Billing.SubscriptionSync do
  @moduledoc """
  Translates a verified Stripe webhook event into User state. The app
  doesn't care which plan was bought — only the resulting capacity, the
  current period window, and a coarse status. The `price_capacity` map
  lives in application config.
  """

  alias Colt.Accounts.User

  require Logger

  def run(%Stripe.Event{type: "checkout.session.completed", data: %{object: session}}) do
    customer_id = get(session, :customer)
    user_id = get(session, :client_reference_id)

    cond do
      is_binary(customer_id) and is_binary(user_id) ->
        with {:ok, user} <- Ash.get(User, user_id, authorize?: false),
             {:ok, _} <- Colt.Accounts.set_stripe_customer(user, customer_id, authorize?: false) do
          {:ok, :customer_linked}
        end

      true ->
        {:ok, :ignored}
    end
  end

  def run(%Stripe.Event{type: type, data: %{object: sub}})
      when type in ["customer.subscription.created", "customer.subscription.updated"] do
    apply_subscription(sub)
  end

  def run(%Stripe.Event{type: "customer.subscription.deleted", data: %{object: sub}}) do
    with {:ok, user} <- find_user(sub) do
      {:ok, _} = Colt.Accounts.clear_subscription(user, authorize?: false)
      {:ok, :cleared}
    end
  end

  def run(%Stripe.Event{type: "invoice.paid", data: %{object: invoice}}) do
    case get(invoice, :subscription) do
      sub_id when is_binary(sub_id) ->
        with {:ok, sub} <- Stripe.Subscription.retrieve(sub_id) do
          apply_subscription(sub)
        end

      _ ->
        {:ok, :ignored}
    end
  end

  def run(%Stripe.Event{type: type}) do
    Logger.debug("[billing] ignoring stripe event #{type}")
    {:ok, :ignored}
  end

  defp apply_subscription(sub) do
    with {:ok, user} <- find_user(sub),
         price_id when is_binary(price_id) <- extract_price_id(sub),
         capacity when is_integer(capacity) <- capacity_for(price_id) do
      attrs = %{
        monthly_contact_capacity: capacity,
        subscription_period_start: to_utc(period_bound(sub, :current_period_start)),
        subscription_period_end: to_utc(period_bound(sub, :current_period_end)),
        subscription_status: status_atom(get(sub, :status))
      }

      with {:ok, _} <- Colt.Accounts.apply_subscription(user, attrs, authorize?: false) do
        {:ok, :applied}
      end
    else
      nil ->
        Logger.warning("[billing] subscription with no known price — ignoring")
        {:ok, :ignored}

      other ->
        other
    end
  end

  defp find_user(sub) do
    case get(sub, :customer) do
      customer_id when is_binary(customer_id) ->
        case Colt.Accounts.get_user_by_stripe_customer(customer_id, authorize?: false) do
          {:ok, %User{} = user} -> {:ok, user}
          {:ok, nil} -> {:error, :user_not_found}
          {:error, %Ash.Error.Query.NotFound{}} -> {:error, :user_not_found}
          err -> err
        end

      _ ->
        {:error, :no_customer_id}
    end
  end

  defp extract_price_id(sub) do
    case first_item(sub) do
      nil ->
        nil

      item ->
        price = get(item, :price)
        price && get(price, :id)
    end
  end

  # Stripe API 2025-03-31 (Basil) moved current_period_start/end off the
  # subscription onto each subscription item. Read the item first, fall back
  # to the legacy top-level field for older API versions.
  defp period_bound(sub, key) do
    item_bound(first_item(sub), key) || get(sub, key)
  end

  defp first_item(sub) do
    items = get(sub, :items)
    data = (items && get(items, :data)) || []

    case data do
      [first | _] -> first
      _ -> nil
    end
  end

  defp item_bound(nil, _key), do: nil
  defp item_bound(item, key), do: get(item, key)

  defp capacity_for(price_id) do
    Application.get_env(:colt, Colt.Billing, [])
    |> Keyword.get(:price_capacity, %{})
    |> Map.get(price_id)
  end

  # Stripe webhook objects arrive as typed structs (atom keys) via
  # Stripe.Converter; our tests pass plain string-keyed maps. Reading through
  # this helper supports both — never `obj["key"]`, which raises on structs.
  defp get(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp get(_, _), do: nil

  defp to_utc(nil), do: nil
  defp to_utc(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp to_utc(unix) when is_integer(unix),
    do: unix |> DateTime.from_unix!() |> DateTime.truncate(:second)

  defp status_atom("active"), do: :active
  defp status_atom("trialing"), do: :active
  defp status_atom("past_due"), do: :past_due
  defp status_atom("unpaid"), do: :past_due
  defp status_atom("canceled"), do: :canceled
  defp status_atom("incomplete"), do: :none
  defp status_atom("incomplete_expired"), do: :canceled
  defp status_atom(_), do: :none
end
