defmodule Colt.Services.Sending.NextSlot do
  @moduledoc """
  Burst scheduler per docs/email-sending.md §5.2.

  Given an `EmailAccount` and a `not_before` lower bound (UTC), return the
  next valid `scheduled_at` (UTC) honouring:

    * Mon–Fri 09:00–17:00 in the account's local timezone
    * a per-(account, date) burst cap (6..12 sends) and jittered effective
      daily quota
    * 1–5 minute spacing inside a burst, ≥60 minute gap between bursts
    * step 1 floor at 11:00 local (followups ignore the floor)

  Stateless: both `burst_cap_today` and `effective_quota` are derived
  deterministically from `:erlang.phash2({account_id, date})`, so two
  callers in the same day produce the same caps without needing a cache.

  Returns `{:ok, %DateTime{} (UTC)}` on success, `{:error, term}` on
  resource read failure.
  """

  alias Colt.Resources.Email

  @max_loops 60

  @spec run(map(), DateTime.t(), keyword()) :: {:ok, DateTime.t()} | {:error, term()}
  def run(account, not_before, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    step_position = Keyword.get(opts, :step_position, nil)

    tz = account.tz || "Etc/UTC"
    now = DateTime.utc_now()

    base =
      [DateTime.shift_zone!(now, tz), DateTime.shift_zone!(not_before, tz)]
      |> Enum.max(DateTime)
      |> maybe_apply_step1_floor(step_position, tz)
      |> bump_into_workday()

    case loop(base, account, actor, 0) do
      {:ok, local_dt} -> {:ok, DateTime.shift_zone!(local_dt, "Etc/UTC")}
      err -> err
    end
  end

  defp loop(_candidate, _account, _actor, n) when n > @max_loops do
    {:error, :scheduler_loop_exhausted}
  end

  defp loop(candidate, account, actor, n) do
    day_start = start_of_day(candidate)
    day_end = next_day(day_start)

    with {:ok, today_rows} <- list_today(account.id, day_start, day_end, actor) do
      today_count = length(today_rows)
      cap = effective_quota(account, candidate)

      cond do
        today_count >= cap ->
          tomorrow = next_morning(day_start)
          loop(bump_into_workday(tomorrow), account, actor, n + 1)

        today_rows == [] ->
          {:ok, candidate}

        true ->
          last = today_rows |> List.last() |> last_local(account.tz)
          gap_min = DateTime.diff(candidate, last, :second) |> div(60)
          burst_cap = burst_cap_today(account, candidate)

          cond do
            gap_min < 60 and today_count < burst_cap ->
              jitter_min = uniform_in(1..5, account.id, candidate, today_count)
              {:ok, DateTime.add(last, jitter_min * 60, :second)}

            true ->
              next = DateTime.add(last, 60 * 60, :second)
              loop(bump_into_workday(next), account, actor, n + 1)
          end
      end
    end
  end

  defp list_today(account_id, day_start, day_end, actor) do
    Email.list_today_for_account(account_id, to_utc(day_start), to_utc(day_end),
      actor: actor,
      authorize?: actor != nil
    )
    |> case do
      {:ok, rows} -> {:ok, rows}
      rows when is_list(rows) -> {:ok, rows}
      err -> err
    end
  end

  defp last_local(%{scheduled_at: dt}, tz), do: DateTime.shift_zone!(dt, tz || "Etc/UTC")

  defp to_utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")

  defp maybe_apply_step1_floor(dt, 0, tz), do: max_dt(dt, today_at(dt, 11, tz))
  defp maybe_apply_step1_floor(dt, _other, _tz), do: dt

  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  defp today_at(local, hour, tz) do
    {:ok, naive} = NaiveDateTime.new(local.year, local.month, local.day, hour, 0, 0)
    DateTime.from_naive!(naive, tz)
  end

  # Mon–Fri 09:00–17:00 in the candidate's local tz. Outside that window,
  # snap forward to the next valid slot.
  defp bump_into_workday(%DateTime{} = dt) do
    cond do
      Date.day_of_week(DateTime.to_date(dt)) > 5 ->
        dt |> add_days_keep_tz(8 - Date.day_of_week(DateTime.to_date(dt))) |> at_hour(9)

      dt.hour < 9 ->
        at_hour(dt, 9)

      dt.hour >= 17 ->
        dt |> add_days_keep_tz(1) |> at_hour(9) |> bump_into_workday()

      true ->
        dt
    end
  end

  defp at_hour(dt, hour) do
    {:ok, naive} = NaiveDateTime.new(dt.year, dt.month, dt.day, hour, 0, 0)
    DateTime.from_naive!(naive, dt.time_zone)
  end

  defp add_days_keep_tz(dt, days) do
    DateTime.add(dt, days * 86_400, :second)
  end

  defp start_of_day(dt), do: at_hour(dt, 0)
  defp next_day(dt), do: add_days_keep_tz(dt, 1)
  defp next_morning(dt), do: at_hour(dt, 9)

  # Deterministic per (account_id, date) burst cap in 6..12.
  defp burst_cap_today(account, local_dt) do
    seed = :erlang.phash2({account.id, DateTime.to_date(local_dt)})
    6 + rem(seed, 7)
  end

  # Deterministic ±5–15% jitter on the configured daily_quota.
  defp effective_quota(account, local_dt) do
    base = max(account.daily_quota, 0)
    seed = :erlang.phash2({:quota, account.id, DateTime.to_date(local_dt)})
    # Map to [0.85, 1.05]: 21 buckets of 0.01.
    factor = 0.85 + rem(seed, 21) / 100.0
    round(base * factor)
  end

  # Deterministic-ish pick from a range, salted by a counter so consecutive
  # calls inside the same loop step don't all collide on the same minute.
  defp uniform_in(low..high//_, account_id, local_dt, salt) do
    seed = :erlang.phash2({account_id, DateTime.to_date(local_dt), salt})
    low + rem(seed, high - low + 1)
  end
end
