defmodule Colt.Services.Sending.NextSlotTest do
  @moduledoc """
  Covers the burst scheduler (docs/email-sending.md §5.2).

  The interesting behaviour is *sequential*: NextSlot is stateless and reads
  the account's already-scheduled rows back out of the DB, so the only way to
  see the shape of a day is to simulate it — call `run/3`, persist the slot it
  hands back, repeat.

  Intended shape of a day (authoritative over the §5.2 pseudocode, which has
  an off-by-concept bug on the burst-membership line): repeating bursts of
  ~6..12 sends spaced 1–5 min apart, separated by >=60 min pauses, until the
  day's effective quota is spent.
  """
  use Colt.DataCase, async: false

  alias Ash.Seed
  alias Colt.Accounts.User

  alias Colt.Resources.{
    Campaign,
    CampaignContact,
    Company,
    EmailAccount,
    OutboundEmail,
    Person,
    Thread
  }

  alias Colt.Services.Sending.NextSlot

  @tz "Europe/Tallinn"

  # Far enough in the future that NextSlot's internal `max(now, not_before)`
  # always resolves to not_before, so nothing here depends on the wall clock.
  @monday ~D[2026-09-14]
  @friday ~D[2026-09-18]
  @saturday ~D[2026-09-19]
  @next_monday ~D[2026-09-21]

  describe "a full simulated day (the burst regression)" do
    test "bursts repeat all day instead of degenerating into hourly singletons" do
      %{account: account} = graph(daily_quota: 40)
      slots = simulate(account, local(@monday, 0, 0), 30)

      bursts = bursts(slots)
      sizes = Enum.map(bursts, &length/1)

      assert length(bursts) >= 3,
             "expected the day to contain at least 3 bursts, got sizes #{inspect(sizes)}"

      multi = Enum.count(sizes, &(&1 >= 3))

      assert multi * 2 > length(sizes),
             "expected most bursts to hold >= 3 sends, got sizes #{inspect(sizes)}"

      # The bug signature: one real burst, then a lonely send every 60 minutes.
      singletons = Enum.count(sizes, &(&1 == 1))

      assert singletons <= 1,
             "expected at most one truncated singleton burst, got sizes #{inspect(sizes)}"
    end

    test "consecutive gaps are either 1..5 min (intra-burst) or >= 60 min (inter-burst)" do
      %{account: account} = graph(daily_quota: 40)
      slots = simulate(account, local(@monday, 0, 0), 30)

      gaps = gaps(slots)

      Enum.each(gaps, fn gap ->
        assert (gap >= 1 and gap <= 5) or gap >= 60,
               "gap of #{gap} min is neither intra-burst (1..5) nor inter-burst (>= 60); " <>
                 "all gaps: #{inspect(gaps, charlists: :as_lists)}"
      end)

      # ...and the tight spacing has to keep happening through each day, not
      # just in that day's opening burst.
      tight = fn g -> Enum.count(g, &(&1 >= 1 and &1 <= 5)) end

      slots
      |> Enum.group_by(&DateTime.to_date/1)
      |> Enum.filter(fn {_date, day_slots} -> length(day_slots) >= 10 end)
      |> Enum.each(fn {date, day_slots} ->
        tail = day_slots |> gaps() |> Enum.take(-5)

        assert tight.(tail) >= 2,
               "expected 1..5 min spacing late on #{date} too, last gaps: #{inspect(tail, charlists: :as_lists)}"
      end)
    end

    test "burst sizes stay in the 6..12 band" do
      %{account: account} = graph(daily_quota: 40)
      slots = simulate(account, local(@monday, 0, 0), 30)

      all_bursts = bursts(slots)
      sizes = Enum.map(all_bursts, &length/1)

      # Each local day's final burst may be cut short — by 17:00, by the day's
      # quota running out, or (for the last day) by the end of the simulation.
      complete =
        all_bursts
        |> Enum.group_by(fn [first | _] -> DateTime.to_date(first) end)
        |> Enum.flat_map(fn {_date, day_bursts} -> Enum.drop(day_bursts, -1) end)
        |> Enum.map(&length/1)

      Enum.each(complete, fn size ->
        assert size >= 6 and size <= 12,
               "burst of #{size} is outside the 6..12 band; all sizes: #{inspect(sizes)}"
      end)

      # The truncation exemption is for the LOWER bound only — a day's final
      # burst may be short, never long. A runaway burst must fail here.
      Enum.each(sizes, fn size ->
        assert size <= 12,
               "burst of #{size} exceeds the 12-send cap; all sizes: #{inspect(sizes)}"
      end)
    end

    test "no slot in a mid-day simulation lands before not_before" do
      %{account: account, thread: thread} = graph(daily_quota: 40)
      not_before = local(@monday, 14, 0)

      # Pre-existing morning sends, the last of which sits inside the 59-minute
      # window before the bound — otherwise the simulation's first call sees an
      # empty day and the whole "last precedes not_before" path never runs.
      for {minute, i} <- Enum.with_index([30, 34, 39, 43, 47]) do
        seed_email(thread, account, i, local(@monday, 13, minute))
      end

      for slot <- simulate(account, not_before, 20, offset: 100) do
        assert DateTime.compare(slot, not_before) != :lt,
               "slot #{slot} is before the not_before bound #{not_before}"
      end
    end
  end

  describe "day-start jitter" do
    # Five days opening at exactly 09:00:00 is a stronger machine fingerprint
    # than the hourly ladder was. The first send of each local day must land at
    # 09:00 + 0..25 min, deterministically seeded like every other pick.
    test "different accounts do not all open the day at 09:00:00" do
      minutes =
        for _ <- 1..8 do
          %{account: account} = graph(daily_quota: 40)
          {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0))
          slot = DateTime.shift_zone!(slot, @tz)

          assert slot.hour == 9 and slot.minute <= 25,
                 "day start #{slot.hour}:#{slot.minute} is outside the 09:00..09:25 window"

          slot.minute
        end

      assert length(Enum.uniq(minutes)) >= 3,
             "expected the day-start minute to vary across accounts, got #{inspect(minutes)}"
    end

    test "consecutive days of one account do not all open at 09:00:00" do
      # quota 8 -> effective 7..8, so 40 sends roll across a full work week.
      %{account: account} = graph(daily_quota: 8)

      starts =
        account
        |> simulate(local(@monday, 0, 0), 40)
        |> Enum.group_by(&DateTime.to_date/1)
        |> Enum.sort_by(fn {date, _} -> date end)
        |> Enum.map(fn {_date, slots} -> List.first(slots) end)

      assert length(starts) >= 4,
             "expected the simulation to span at least 4 local days, got #{length(starts)}"

      Enum.each(starts, fn slot ->
        assert slot.hour == 9 and slot.minute <= 25,
               "day start #{slot} is outside the 09:00..09:25 window"
      end)

      minutes = Enum.map(starts, & &1.minute)

      assert length(Enum.uniq(minutes)) >= 2,
             "expected the day-start minute to vary across days, got #{inspect(minutes)}"
    end

    test "the jittered day start is deterministic for the same account and day" do
      %{account: account} = graph(daily_quota: 40)

      assert {:ok, a} = NextSlot.run(account, local(@monday, 0, 0))
      assert {:ok, b} = NextSlot.run(account, local(@monday, 0, 0))
      assert DateTime.compare(a, b) == :eq
    end

    test "the 11:00 step 1 floor still wins over a jittered 09:xx start" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0), step_position: 0)
      slot_local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.compare(slot_local, local(@monday, 11, 0)) != :lt,
             "step 1 landed at #{slot_local}, before the 11:00 local floor"

      assert slot_local.hour == 11,
             "step 1 landed at #{slot_local}; jitter must not push it past the 11:00 hour"
    end
  end

  describe "the step 1 11:00 floor survives a day roll" do
    # `run/3` applies the floor once and then pipes into `bump_into_workday`,
    # which replaces an out-of-window value wholesale with the next workday's
    # 09:xx open — dropping the floor. Every caller that passes
    # `step_position: 0` uses `DateTime.utc_now()` as the bound
    # (approve_contact.ex, auto_draft_and_approve.ex, auto_approve_campaign.ex),
    # so any first touch approved after 17:00 or over a weekend hits this.
    test "a Friday-evening bound lands on Monday at 11:xx, not 09:xx" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@friday, 18, 30), step_position: 0)
      slot = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(slot) == @next_monday
      assert slot.hour == 11, "step 1 rolled to #{slot}, below the 11:00 floor of its landing day"
    end

    test "a Saturday bound lands on Monday at 11:xx, not 09:xx" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@saturday, 10, 0), step_position: 0)
      slot = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(slot) == @next_monday
      assert slot.hour == 11, "step 1 rolled to #{slot}, below the 11:00 floor of its landing day"
    end

    test "a weekday-evening bound lands on the next day at 11:xx, not 09:xx" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@monday, 18, 0), step_position: 0)
      slot = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(slot) == Date.add(@monday, 1)
      assert slot.hour == 11, "step 1 rolled to #{slot}, below the 11:00 floor of its landing day"
    end

    test "the floor jitter is keyed to the landing date, not the pre-roll date" do
      %{account: account} = graph(daily_quota: 40)

      # Three different bounds, all landing on the same Monday. The floor
      # minute is a property of the day the email is actually sent on, so all
      # three must agree. Seeding on the pre-bump date gives three answers.
      minutes =
        for bound <- [local(@friday, 18, 30), local(@saturday, 10, 0), local(@next_monday, 8, 0)] do
          {:ok, slot} = NextSlot.run(account, bound, step_position: 0)
          slot = DateTime.shift_zone!(slot, @tz)
          assert DateTime.to_date(slot) == @next_monday
          {slot.hour, slot.minute}
        end

      assert length(Enum.uniq(minutes)) == 1,
             "same landing day, same account, but the floor minute differed: #{inspect(minutes)}"
    end

    test "the floor does not leak onto followups rolled over the same boundaries" do
      for bound <- [local(@friday, 18, 30), local(@saturday, 10, 0), local(@monday, 18, 0)] do
        %{account: account} = graph(daily_quota: 40)

        {:ok, slot} = NextSlot.run(account, bound, step_position: 1)
        slot = DateTime.shift_zone!(slot, @tz)

        assert slot.hour == 9,
               "followup from bound #{bound} landed at #{slot}; the 11:00 floor is step-1 only"
      end
    end
  end

  describe "jitter is real, not a token offset" do
    test "the step 1 floor minute varies across accounts and stays inside 11:00..11:25" do
      minutes =
        sample_minutes(20, 40, fn account, _thread ->
          {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0), step_position: 0)
          slot = DateTime.shift_zone!(slot, @tz)

          assert slot.hour == 11 and slot.minute <= 25,
                 "step 1 floor at #{slot} is outside the 11:00..11:25 window"

          slot.minute
        end)

      assert_real_jitter(minutes, "step 1 floor")
    end

    test "the day-open minute spans a meaningful part of 0..25" do
      minutes =
        sample_minutes(20, 40, fn account, _thread ->
          {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0))
          DateTime.shift_zone!(slot, @tz).minute
        end)

      assert_real_jitter(minutes, "day open")
    end

    test "the quota roll-over lands on a jittered open, not a flat 09:00" do
      minutes =
        sample_minutes(20, 4, fn account, thread ->
          # effective_quota = round(4 * [0.85, 1.05]) -> 3..4, so 5 rows is over.
          for i <- 0..4, do: seed_email(thread, account, i, local(@monday, 9, i))

          {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0))
          slot = DateTime.shift_zone!(slot, @tz)

          assert DateTime.to_date(slot) == Date.add(@monday, 1)
          assert slot.hour == 9 and slot.minute <= 25

          slot.minute
        end)

      assert_real_jitter(minutes, "quota roll-over open")
    end

    test "a weekend roll lands on a jittered open, not a flat 09:00" do
      minutes =
        sample_minutes(20, 40, fn account, _thread ->
          {:ok, slot} = NextSlot.run(account, local(@saturday, 10, 0))
          slot = DateTime.shift_zone!(slot, @tz)

          assert DateTime.to_date(slot) == @next_monday
          assert slot.hour == 9 and slot.minute <= 25

          slot.minute
        end)

      assert_real_jitter(minutes, "weekend roll open")
    end

    test "a 17:00-wall roll lands on a jittered open, not a flat 09:00" do
      minutes =
        sample_minutes(20, 40, fn account, _thread ->
          {:ok, slot} = NextSlot.run(account, local(@monday, 18, 0))
          slot = DateTime.shift_zone!(slot, @tz)

          assert DateTime.to_date(slot) == Date.add(@monday, 1)
          assert slot.hour == 9 and slot.minute <= 25

          slot.minute
        end)

      assert_real_jitter(minutes, "17:00-wall roll open")
    end
  end

  describe "sub-minute jitter" do
    # Every slot landing on :00 seconds is the same fingerprint class as the
    # flat 09:00:00 open, one resolution down. Slots carry a deterministic
    # 0..59 second offset, on every path that can produce a slot.
    test "the second-of-minute varies across accounts on the day-open path" do
      seconds =
        sample_minutes(20, 40, fn account, _thread ->
          {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0))
          DateTime.shift_zone!(slot, @tz).second
        end)

      assert_second_jitter(seconds, "day open")
    end

    test "the second-of-minute varies across a whole simulated day" do
      # Covers the paths a single-call test cannot reach: intra-burst,
      # new-burst and the rolls in between.
      %{account: account} = graph(daily_quota: 40)

      seconds =
        account
        |> simulate(local(@monday, 0, 0), 30)
        |> Enum.map(& &1.second)

      assert_second_jitter(seconds, "simulated day")
    end

    test "the second offset is deterministic for the same account and rows" do
      %{account: account, thread: thread} = graph(daily_quota: 40)

      for {minute, i} <- Enum.with_index([12, 15, 19]) do
        seed_email(thread, account, i, local(@monday, 10, minute))
      end

      assert {:ok, a} = NextSlot.run(account, local(@monday, 0, 0))
      assert {:ok, b} = NextSlot.run(account, local(@monday, 0, 0))

      assert DateTime.compare(a, b) == :eq
      assert a.second == b.second
    end
  end

  describe "long local days (DST fall-back)" do
    # `next_day/1` adds 86_400 *absolute* seconds. Africa/Cairo ends DST on the
    # last Thursday of October at 24:00, so 2026-10-29 is 25 hours long and
    # `next_day(start_of_day(candidate))` lands at 23:00 of the SAME date. The
    # quota roll-over then re-proposes the same day forever. Unreachable in
    # EU/US only because their fall-back is always a Sunday.
    @cairo "Africa/Cairo"
    # 2026-10-28 Wed, 24h local day. 2026-10-29 Thu, 25h local day.
    @cairo_normal ~D[2026-10-28]
    @cairo_long ~D[2026-10-29]

    test "the quota roll-over survives a 25-hour local day" do
      %{account: account, thread: thread} = graph(daily_quota: 4, tz: @cairo)

      # effective_quota = round(4 * [0.85, 1.05]) -> 3..4, so 5 rows is over.
      for i <- 0..4 do
        seed_email(thread, account, i, local(@cairo_long, 9, i, @cairo))
      end

      assert {:ok, slot} = NextSlot.run(account, local(@cairo_long, 0, 0, @cairo))

      assert DateTime.to_date(DateTime.shift_zone!(slot, @cairo)) == Date.add(@cairo_long, 1),
             "roll-over from the 25-hour day did not land on the next calendar date"
    end

    test "control: the same roll-over on the adjacent 24-hour local day works" do
      %{account: account, thread: thread} = graph(daily_quota: 4, tz: @cairo)

      for i <- 0..4 do
        seed_email(thread, account, i, local(@cairo_normal, 9, i, @cairo))
      end

      assert {:ok, slot} = NextSlot.run(account, local(@cairo_normal, 0, 0, @cairo))

      assert DateTime.to_date(DateTime.shift_zone!(slot, @cairo)) == Date.add(@cairo_normal, 1)
    end
  end

  describe "not_before is read as an instant, not a representation" do
    # `:utc_datetime_usec` values read back from Postgres carry precision 6, so
    # an exactly-on-the-minute bound arrives as {0, 6} rather than {0, 0} and
    # `ceil_minute/1`'s guard misses it, adding a spurious minute. Reachable
    # from send_one.ex (sent_at + whole days) and defer_followup.ex.
    test "microsecond precision alone does not change the slot" do
      %{account: account} = graph(daily_quota: 40)

      bound = local(@monday, 10, 0)
      assert bound.microsecond == {0, 0}
      usec_bound = %{bound | microsecond: {0, 6}}

      assert DateTime.compare(bound, usec_bound) == :eq

      assert {:ok, a} = NextSlot.run(account, bound)
      assert {:ok, b} = NextSlot.run(account, usec_bound)

      assert DateTime.compare(a, b) == :eq,
             "same instant, different precision, different slot: #{a} vs #{b}"
    end
  end

  describe "the not_before lower bound" do
    test "never returns a slot before not_before when the last send precedes the bound" do
      %{account: account, thread: thread} = graph(daily_quota: 40)
      not_before = local(@monday, 14, 0)

      # `last` sits inside the 59-minute window *before* the bound — the window
      # in which `gap_min < 60` holds but `last + 1..5 min` is still early.
      for {minute, i} <- Enum.with_index([30, 33, 37, 41, 45]) do
        seed_email(thread, account, i, local(@monday, 13, minute))
      end

      {:ok, slot} = NextSlot.run(account, not_before)

      assert DateTime.compare(slot, not_before) != :lt,
             "expected slot >= #{not_before}, got #{slot} " <>
               "(#{DateTime.diff(not_before, slot, :second) |> div(60)} min early)"
    end

    test "the step 1 11:00 floor holds even when the day already has earlier rows" do
      %{account: account, thread: thread} = graph(daily_quota: 40)

      for {minute, i} <- Enum.with_index([20, 26, 31, 38, 45]) do
        seed_email(thread, account, i, local(@monday, 10, minute))
      end

      {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0), step_position: 0)
      slot_local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.compare(slot_local, local(@monday, 11, 0)) != :lt,
             "step 1 landed at #{slot_local.hour}:#{slot_local.minute}, before the 11:00 local floor"
    end
  end

  describe "working-hours window" do
    test "a Friday-evening lower bound lands on the next Monday morning" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@friday, 18, 30))
      local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(local) == @next_monday
      assert local.hour == 9
    end

    test "a Saturday lower bound lands on the next Monday morning" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@saturday, 10, 0))
      local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(local) == @next_monday
      assert local.hour == 9
    end

    test "every slot of a simulated day sits Mon-Fri 09:00-17:00 in the account tz" do
      %{account: account} = graph(daily_quota: 40)

      for slot <- simulate(account, local(@monday, 0, 0), 30) do
        assert Date.day_of_week(DateTime.to_date(slot)) <= 5
        assert slot.hour >= 9 and slot.hour < 17
      end
    end
  end

  describe "step 1 (step_position: 0) 11:00 floor" do
    test "step 0 is never scheduled before 11:00 local" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0), step_position: 0)
      local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(local) == @monday
      assert local.hour == 11
    end

    test "followups ignore the 11:00 floor" do
      %{account: account} = graph(daily_quota: 40)

      {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0), step_position: 1)
      local = DateTime.shift_zone!(slot, @tz)

      assert DateTime.to_date(local) == @monday
      assert local.hour == 9
    end
  end

  describe "daily quota" do
    # RED for a second, independent reason: the quota-exhausted branch calls
    # `next_morning(day_start)`, which is `at_hour(today_00:00, 9)` — i.e. it
    # re-proposes *today* 09:00 and never advances the date, so the loop spins
    # until :scheduler_loop_exhausted.
    test "rolls to the next workday at 09:00 once the day's effective quota is spent" do
      %{account: account, thread: thread} = graph(daily_quota: 4)

      # effective_quota = round(4 * [0.85, 1.05]) -> 3..4, so 5 rows is always over.
      for i <- 0..4 do
        seed_email(thread, account, i, local(@monday, 9, i))
      end

      {:ok, slot} = NextSlot.run(account, local(@monday, 0, 0))
      local = DateTime.shift_zone!(slot, @tz)

      # The DATE is what pins the roll-over bug. The minute is deliberately
      # unpinned: a rolled-to day is still a day start, so it carries the
      # 09:00 + 0..25 min jitter.
      assert DateTime.to_date(local) == Date.add(@monday, 1)
      assert local.hour == 9
      assert local.minute <= 25
    end
  end

  describe "determinism" do
    test "two calls against identical state return the same slot" do
      %{account: account, thread: thread} = graph(daily_quota: 40)

      for i <- 0..2 do
        seed_email(thread, account, i, local(@monday, 9, i))
      end

      assert {:ok, a} = NextSlot.run(account, local(@monday, 0, 0))
      assert {:ok, b} = NextSlot.run(account, local(@monday, 0, 0))
      assert DateTime.compare(a, b) == :eq
    end
  end

  # ── simulation helpers ──

  # Ask for a slot, persist a row at that slot, repeat `count` times.
  # Returns the slots in the account's local tz, in scheduling order.
  defp simulate(account, not_before, count, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)

    Enum.map(0..(count - 1), fn i ->
      {:ok, slot} = NextSlot.run(account, not_before)
      seed_email(account.thread, account, offset + i, slot)
      DateTime.shift_zone!(slot, @tz)
    end)
  end

  # Build `count` independent accounts and collect one minute from each.
  defp sample_minutes(count, quota, fun) do
    for _ <- 1..count do
      %{account: account, thread: thread} = graph(daily_quota: quota)
      fun.(account, thread)
    end
  end

  # A 0..25 uniform draw over 20 accounts gives ~13 distinct values and a
  # near-full spread; these thresholds clear that comfortably while failing
  # any token offset such as `rem(phash2(...), 3)`.
  defp assert_real_jitter(minutes, label) do
    distinct = length(Enum.uniq(minutes))
    spread = Enum.max(minutes) - Enum.min(minutes)

    assert distinct >= 8,
           "#{label}: only #{distinct} distinct minutes across #{length(minutes)} accounts — " <>
             "#{inspect(Enum.sort(minutes))}"

    assert spread >= 12,
           "#{label}: minute spread of #{spread} is too narrow to be a 0..25 draw — " <>
             "#{inspect(Enum.sort(minutes))}"
  end

  # A 0..59 uniform draw over 20+ samples gives ~17 distinct values and a
  # near-full spread; these thresholds clear that comfortably while failing
  # a flat :00 or any token offset.
  defp assert_second_jitter(seconds, label) do
    distinct = length(Enum.uniq(seconds))
    spread = Enum.max(seconds) - Enum.min(seconds)

    assert distinct >= 8,
           "#{label}: only #{distinct} distinct second-values across #{length(seconds)} slots — " <>
             "#{inspect(Enum.sort(seconds))}"

    assert spread >= 30,
           "#{label}: second spread of #{spread} is too narrow to be a 0..59 draw — " <>
             "#{inspect(Enum.sort(seconds))}"
  end

  # Whole minutes between consecutive slots. Slots carry a cosmetic 0..59
  # second offset on top of the nominal whole-minute grid; measure on the
  # grid, or a descending second-value turns a 60 min pause into 59.
  defp whole_minute(%DateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}

  defp gaps(slots) do
    slots
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      DateTime.diff(whole_minute(b), whole_minute(a), :second) |> div(60)
    end)
  end

  # A burst = a maximal run of consecutive sends each < 60 min after the previous.
  defp bursts([]), do: []

  defp bursts([first | rest]) do
    {bursts, current} =
      Enum.reduce(rest, {[], [first]}, fn slot, {done, [prev | _] = current} ->
        if DateTime.diff(whole_minute(slot), whole_minute(prev), :second) |> div(60) < 60 do
          {done, [slot | current]}
        else
          {[Enum.reverse(current) | done], [slot]}
        end
      end)

    Enum.reverse([Enum.reverse(current) | bursts])
  end

  defp local(date, hour, minute, tz \\ @tz) do
    {:ok, naive} = NaiveDateTime.new(date.year, date.month, date.day, hour, minute, 0)

    naive
    |> DateTime.from_naive!(tz)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  # ── fixtures (Ash.Seed bypasses create actions/policies/validations) ──

  defp graph(opts) do
    n = System.unique_integer([:positive])
    user = Seed.seed!(User, %{email: "owner-#{n}@liid.app"})
    company = Seed.seed!(Company, %{name: "Acme #{n}", registry_code: "EE#{n}", market: :ee})

    person =
      Seed.seed!(Person, %{name: "Mart Tamm", email: "mart-#{n}@acme.ee", company_id: company.id})

    campaign = Seed.seed!(Campaign, %{name: "Camp #{n}", owner_id: user.id})

    contact =
      Seed.seed!(CampaignContact, %{
        campaign_id: campaign.id,
        person_id: person.id,
        status: :sending
      })

    thread = Seed.seed!(Thread, %{campaign_contact_id: contact.id})

    account =
      Seed.seed!(EmailAccount, %{
        user_id: user.id,
        provider: :imap,
        address: "send-#{n}@liid.app",
        tz: Keyword.get(opts, :tz, @tz),
        daily_quota: Keyword.fetch!(opts, :daily_quota),
        status: :healthy
      })

    # `simulate/3` needs somewhere to hang its rows; one row per step_position
    # on a single thread satisfies the :step_per_thread identity.
    %{user: user, thread: thread, account: Map.put(account, :thread, thread)}
  end

  defp seed_email(thread, account, step_position, scheduled_at) do
    Seed.seed!(OutboundEmail, %{
      thread_id: thread.id,
      email_account_id: account.id,
      step_position: step_position,
      status: :scheduled,
      scheduled_at: scheduled_at
    })
  end
end
