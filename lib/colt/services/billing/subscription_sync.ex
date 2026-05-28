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
    customer_id = session["customer"] || session[:customer]
    user_id = session["client_reference_id"] || session[:client_reference_id]

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
    case invoice["subscription"] || invoice[:subscription] do
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
        subscription_period_start: to_utc(get(sub, :current_period_start)),
        subscription_period_end: to_utc(get(sub, :current_period_end)),
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
    items = get(sub, :items)
    data = (items && (items["data"] || items[:data])) || []

    case data do
      [first | _] ->
        price = first["price"] || first[:price]
        price && (price["id"] || price[:id])

      _ ->
        nil
    end
  end

  defp capacity_for(price_id) do
    Application.get_env(:colt, Colt.Billing, [])
    |> Keyword.get(:price_capacity, %{})
    |> Map.get(price_id)
  end

  defp get(map, key) when is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
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
