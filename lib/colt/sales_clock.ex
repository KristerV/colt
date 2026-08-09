defmodule Colt.SalesClock do
  @moduledoc """
  The sales funnel's notion of "today".

  Bucketing is a **calendar-day** question, not a timestamp one: something
  dated today is work for today, so it belongs in Now from midnight — not from
  whatever o'clock its timestamp happens to carry. That needs a timezone, and
  the app already standardises on Europe/Tallinn (see
  `Colt.Services.EmailAccount.ImportMailboxes`).

  Everything that compares a `next_action_at` to today goes through here, so
  the board's chips and the `:sales_bucket` calculation can never disagree.
  """

  @tz "Europe/Tallinn"

  @doc "Today's date in the sales funnel's timezone."
  def today, do: DateTime.utc_now() |> to_local_date()

  @doc "The local calendar date a UTC timestamp falls on."
  def to_local_date(%DateTime{} = dt), do: dt |> DateTime.shift_zone!(@tz) |> DateTime.to_date()

  @doc """
  Whole days from today to `dt` — negative when overdue, 0 when due today.
  """
  def days_from_today(%DateTime{} = dt), do: Date.diff(to_local_date(dt), today())

  @doc """
  A local calendar date as a UTC timestamp, anchored at 09:00 local so a
  picked date always reads back as the day the user picked.
  """
  def at_start_of_workday(%Date{} = date) do
    date
    |> DateTime.new!(~T[09:00:00], @tz)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  @doc "`n` days from today, as a UTC timestamp at 09:00 local."
  def in_days(n) when is_integer(n), do: today() |> Date.add(n) |> at_start_of_workday()
end
