defmodule Colt.Services.Sending.NextSlot do
  @moduledoc """
  Burst scheduler per docs/email-sending.md §5.2.

  Given an `EmailAccount` and a `not_before` lower bound (UTC), return the
  next valid `scheduled_at` (UTC) honouring:

    * Mon–Fri 09:00–17:00 in the account's local timezone
    * a jittered effective daily quota (`round(quota × 0.85..1.05)`)
    * repeating bursts all day: 1–5 minute spacing inside a burst, then a
      60–90 minute pause, then the next burst — until the quota is spent
    * a per-*burst* cap in 6..12, so a day reads "5 now, 9 later, 7 later"
      rather than one burst of N and hourly singletons after it
    * a jittered **day start**: the first send of a local day lands at
      09:00 + 0..25 min, never flat 09:00:00 — five identical 09:00:00
      opens across a week is a machine fingerprint. Applies to every day
      the account opens, including days reached by quota roll-over and by
      the 17:00 wall.
    * step 1 floor at 11:00 local, jittered the same way to 11:00 + 0..25
      min (distinct seed salt, so a day's 09:xx and 11:xx picks don't
      correlate). The floor is applied *after* every workday bump, so it
      holds on whatever day the email actually lands on — a Friday-evening
      or weekend bound rolls to Monday 11:xx, not Monday 09:xx — and its
      jitter is seeded on that **landing** date, so two different bounds
      landing on the same day get the same floor minute. Followups ignore
      the floor.
    * a sub-minute jitter: every returned slot carries a deterministic
      0..59 second offset (own salt). All internal scheduling math runs on
      a whole-minute grid — rows read back from the DB are truncated to
      the minute — and the offset is *set* on the way out rather than
      added, so seconds never accumulate across a burst and the 1..5 /
      60..90 minute bands stay exact.

  All day arithmetic moves whole **calendar** days (`Date.add/2` + the
  wall-clock time), never `n × 86_400` absolute seconds: a DST fall-back day
  can be 25 hours long (e.g. `Africa/Cairo` ends DST on a *Thursday*), and an
  absolute-seconds add then leaves the date unchanged — which made the quota
  roll-over re-propose the same day until `@max_loops` and made the day's
  closing bound land an hour early, under-counting the day's rows. Local
  times that a zone skips or repeats are resolved to the first instant after
  the gap / the earlier of the ambiguous pair, so no path can raise.

  `run/3` is a function of the *instant* it is given, not of that instant's
  representation: an on-the-minute bound is left alone whether it arrives with
  microsecond precision 0 (`{0, 0}`) or 6 (`{0, 6}`, as `:utc_datetime_usec`
  columns read back from Postgres do).

  Stateless: the current burst's size and index are *derived from the
  already-scheduled rows* (walk today's rows backwards while consecutive
  gaps stay under 60 min), never from a counter. The per-burst cap, the
  inter-burst pause, the effective quota and every jitter are derived
  deterministically from `:erlang.phash2/1` over a seed tuple containing
  the account id and the local date (or the local slot, for the second
  offset), so two callers looking at the same rows produce the same slot
  without a cache.

  Returns `{:ok, %DateTime{} (UTC)}` on success, `{:error, term}` on
  resource read failure.
  """

  alias Colt.Resources.OutboundEmail

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
      |> ceil_minute()
      |> advance(account, step_position)

    case loop(base, account, actor, step_position, 0) do
      {:ok, local_dt} -> {:ok, local_dt |> with_second_jitter(account) |> to_utc()}
      err -> err
    end
  end

  defp loop(_candidate, _account, _actor, _step_position, n) when n > @max_loops do
    {:error, :scheduler_loop_exhausted}
  end

  defp loop(candidate, account, actor, step_position, n) do
    day_start = start_of_day(candidate)
    day_end = next_day(day_start)

    with {:ok, today_rows} <- list_today(account.id, day_start, day_end, actor) do
      today_count = length(today_rows)
      cap = effective_quota(account, candidate)

      cond do
        today_count >= cap ->
          # Roll to the *next* day's jittered 09:xx open — `at_hour(day_start,
          # 9)` alone would re-propose today and spin until @max_loops.
          tomorrow = day_start |> next_day() |> day_open(account)
          loop(advance(tomorrow, account, step_position), account, actor, step_position, n + 1)

        today_rows == [] ->
          {:ok, candidate}

        true ->
          locals = Enum.map(today_rows, &last_local(&1, account.tz))
          last = List.last(locals)
          {burst_size, burst_index} = current_burst(locals)
          gap_min = DateTime.diff(candidate, last, :second) |> div(60)
          burst_cap = burst_cap(account, candidate, burst_index)

          jitter_min = uniform_in(1..5, account.id, candidate, today_count)
          proposed = DateTime.add(last, jitter_min * 60, :second)

          cond do
            # `last` can sit *before* the caller's lower bound (gap_min < 60
            # covers that whole window), and `last + 1..5min` would then land
            # before `not_before` — sending a followup early, or a step 1
            # before its 11:00 floor. Fall through to the new-burst branch,
            # which clamps with `max_dt(candidate, ...)`.
            gap_min < 60 and burst_size < burst_cap and
                DateTime.compare(proposed, candidate) != :lt ->
              # A burst can run into the 17:00 wall; roll it rather than
              # emitting an out-of-window slot.
              if in_workday?(proposed) do
                {:ok, proposed}
              else
                loop(
                  advance(proposed, account, step_position),
                  account,
                  actor,
                  step_position,
                  n + 1
                )
              end

            true ->
              # Start a new burst after a jittered 60–90 minute pause, but
              # never roll backward from the caller's candidate.
              pause_min = burst_pause(account, candidate, burst_index)
              next_burst = DateTime.add(last, pause_min * 60, :second)

              next_candidate =
                candidate |> max_dt(next_burst) |> advance(account, step_position)

              if DateTime.to_date(next_candidate) == DateTime.to_date(candidate) do
                {:ok, next_candidate}
              else
                loop(next_candidate, account, actor, step_position, n + 1)
              end
          end
      end
    end
  end

  # Walk today's rows (ascending) backwards from the last one, counting the
  # consecutive rows whose gap to their predecessor is < 60 min. Returns
  # `{size_of_current_burst, index_of_current_burst}` where the index counts
  # the completed bursts that precede it today.
  defp current_burst(locals) do
    gaps =
      locals
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> DateTime.diff(b, a, :second) |> div(60) end)

    trailing = gaps |> Enum.reverse() |> Enum.take_while(&(&1 < 60)) |> length()
    breaks = Enum.count(gaps, &(&1 >= 60))

    {trailing + 1, breaks}
  end

  defp list_today(account_id, day_start, day_end, actor) do
    OutboundEmail.list_today_for_account(account_id, to_utc(day_start), to_utc(day_end),
      actor: actor,
      authorize?: actor != nil
    )
    |> case do
      {:ok, rows} -> {:ok, rows}
      rows when is_list(rows) -> {:ok, rows}
      err -> err
    end
  end

  # Rows come back carrying their cosmetic 0..59 second offset. All burst
  # math (gaps, pauses, the 1..5 min spacing) runs on the nominal
  # whole-minute grid, so truncate here — otherwise a nominal 60 min pause
  # measures 59 min whenever the seconds descend, and the burst-membership
  # test (`gap < 60`) silently merges two bursts.
  defp last_local(%{scheduled_at: dt}, tz),
    do: dt |> DateTime.shift_zone!(tz || "Etc/UTC") |> truncate_minute()

  defp to_utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")

  # Snap into the workday first, *then* floor. Order matters: a bump can
  # move the slot to another day entirely (weekend, 17:00 wall, quota
  # roll-over), and flooring first would let the bump discard the floor and
  # replace it with that day's 09:xx open. Flooring after also seeds the
  # floor jitter on the landing date rather than the pre-roll one.
  #
  # This cannot loop: the floor only ever moves a slot to 11:00..11:25 on a
  # day that is already a workday, which is inside the window.
  defp advance(dt, account, step_position) do
    dt |> bump_into_workday(account) |> maybe_apply_step1_floor(step_position, account)
  end

  # The 11:00 floor is jittered to 11:00 + 0..25 min for the same
  # anti-fingerprint reason as the day start, under its own salt. It stays
  # inside the 11th hour, so it always wins over a jittered 09:xx open.
  defp maybe_apply_step1_floor(dt, 0, account) do
    floor_dt = dt |> at_hour(11) |> add_minutes(jitter(:step1_floor, account, dt))
    max_dt(dt, floor_dt)
  end

  defp maybe_apply_step1_floor(dt, _other, _account), do: dt

  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  # Mon–Fri 09:00–17:00 in the candidate's local tz. Outside that window,
  # snap forward to the next valid slot.
  defp bump_into_workday(%DateTime{} = dt, account) do
    cond do
      Date.day_of_week(DateTime.to_date(dt)) > 5 ->
        # `add_days_keep_tz` moves whole calendar days, so the landing date is
        # always the intended Monday; the re-check is kept as a cheap
        # belt-and-braces guard on the DST-adjusted 09:xx open.
        dt
        |> add_days_keep_tz(8 - Date.day_of_week(DateTime.to_date(dt)))
        |> day_open(account)
        |> bump_into_workday(account)

      dt.hour < 9 ->
        day_open(dt, account)

      dt.hour >= 17 ->
        dt |> add_days_keep_tz(1) |> day_open(account) |> bump_into_workday(account)

      true ->
        dt
    end
  end

  defp at_hour(dt, hour) do
    from_local(DateTime.to_date(dt), Time.new!(hour, 0, 0), dt.time_zone)
  end

  # Advance by CALENDAR days, keeping the wall-clock time. Adding `days *
  # 86_400` absolute seconds is wrong on any local day that is not exactly
  # 24 hours: on a 25-hour DST fall-back day it lands at 23:00 of the *same*
  # date, which silently breaks every caller that relies on the date
  # changing (the quota roll-over spun until `@max_loops`, and `day_end`
  # closed an hour early so `list_today` under-counted).
  defp add_days_keep_tz(dt, days) do
    dt
    |> DateTime.to_date()
    |> Date.add(days)
    |> from_local(DateTime.to_time(dt), dt.time_zone)
  end

  # Build a local datetime totally: a wall-clock time can be skipped (spring
  # forward) or repeated (fall back) in a zone. Take the first instant after
  # a gap and the earlier of an ambiguous pair, so the scheduler never
  # raises on a DST boundary.
  defp from_local(%Date{} = date, %Time{} = time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, dt} -> dt
      {:ambiguous, first, _second} -> first
      {:gap, _just_before, just_after} -> just_after
    end
  end

  defp in_workday?(%DateTime{} = dt) do
    Date.day_of_week(DateTime.to_date(dt)) <= 5 and dt.hour >= 9 and dt.hour < 17
  end

  defp start_of_day(dt), do: at_hour(dt, 0)
  defp next_day(dt), do: add_days_keep_tz(dt, 1)

  # The account's opening slot for `dt`'s local day: 09:00 + 0..25 min.
  defp day_open(dt, account) do
    dt |> at_hour(9) |> add_minutes(jitter(:day_open, account, dt))
  end

  defp add_minutes(dt, minutes), do: DateTime.add(dt, minutes * 60, :second)

  defp truncate_minute(%DateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}

  # Round the caller's bound *up* to a whole minute so every candidate the
  # scheduler reasons about sits on the minute grid. Rounding up (not down)
  # is what keeps `slot >= not_before` true once the cosmetic second offset
  # is set on the way out.
  # The guard matches on the *value* of the microsecond field, never on its
  # precision: `:utc_datetime_usec` bounds read back from Postgres carry
  # precision 6, so an exactly-on-the-minute instant arrives as `{0, 6}`.
  # Matching `{0, 0}` alone let it fall through and gain a spurious minute,
  # making `run/3` a function of the representation instead of the instant.
  defp ceil_minute(%DateTime{second: 0, microsecond: {0, _}} = dt), do: dt
  defp ceil_minute(%DateTime{} = dt), do: dt |> truncate_minute() |> add_minutes(1)

  # Every slot landing on :00 seconds is the same fingerprint class as a flat
  # 09:00:00 open, one resolution down. SET (never add) a deterministic 0..59
  # second offset on the finished slot: adding would accumulate across a
  # burst — each row is read back and stepped from — and drift the 1..5 min
  # band. The offset is non-negative and the slot is already a whole minute,
  # so the `not_before` lower bound still holds.
  defp with_second_jitter(%DateTime{} = dt, account) do
    seed = :erlang.phash2({:second_of_minute, account.id, truncate_minute(dt)})
    %{truncate_minute(dt) | second: rem(seed, 60)}
  end

  # Deterministic 0..25 minute offset per (salt, account_id, date).
  defp jitter(salt, account, local_dt) do
    rem(:erlang.phash2({salt, account.id, DateTime.to_date(local_dt)}), 26)
  end

  # Deterministic per (account_id, date, burst_index) cap in 6..12, so each
  # burst of the day gets its own size instead of repeating one number.
  defp burst_cap(account, local_dt, burst_index) do
    seed = :erlang.phash2({account.id, DateTime.to_date(local_dt), burst_index})
    6 + rem(seed, 7)
  end

  # Deterministic per (account_id, date, burst_index) pause in 60..90 min.
  defp burst_pause(account, local_dt, burst_index) do
    seed = :erlang.phash2({:pause, account.id, DateTime.to_date(local_dt), burst_index})
    60 + rem(seed, 31)
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
