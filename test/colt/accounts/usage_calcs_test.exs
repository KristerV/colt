defmodule Colt.Accounts.UsageCalcsTest do
  @moduledoc """
  Confirms the usage calcs/aggregate compile to valid SQL and derive the
  20:1 screening allowance off the contact cap.
  """
  use Colt.DataCase, async: false

  alias Colt.Accounts.User

  defp paid_user(capacity) do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "u#{capacity}@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, user} =
      Colt.Accounts.apply_subscription(
        user,
        %{
          monthly_contact_capacity: capacity,
          subscription_period_start: ~U[2026-05-01 00:00:00Z],
          subscription_period_end: ~U[2026-06-01 00:00:00Z],
          subscription_status: :active
        },
        authorize?: false
      )

    user
  end

  test "screening allowance is 20x the contact cap; usage starts empty" do
    user =
      paid_user(50)
      |> Ash.load!(
        [
          :remaining_capacity,
          :monthly_screening_capacity,
          :remaining_screening,
          :enriched_this_period_count,
          :screened_this_period_count
        ],
        authorize?: false
      )

    assert user.monthly_contact_capacity == 50
    assert user.monthly_screening_capacity == 1_000
    assert user.enriched_this_period_count == 0
    assert user.screened_this_period_count == 0
    assert user.remaining_capacity == 50
    assert user.remaining_screening == 1_000
  end

  test "paid?/1 reflects active status + positive capacity" do
    assert User.paid?(paid_user(50))

    unpaid =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "free@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    refute User.paid?(unpaid)
  end
end
