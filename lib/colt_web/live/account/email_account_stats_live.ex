defmodule ColtWeb.Account.EmailAccountStatsLive do
  @moduledoc """
  Per-account sending stats: daily volume bars over a ±14 day window
  plus a scatter "pattern map" of time-of-day × day. Pulls a single
  windowed read of OutboundEmail rows and aggregates in memory.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.{EmailAccount, OutboundEmail}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @window_days 14

  def mount(%{"account_id" => account_id}, _session, socket) do
    actor = socket.assigns.current_user

    case EmailAccount.get(account_id, actor: actor) do
      {:ok, account} ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Stats — %{address}", address: account.address),
           account: account
         )
         |> load_stats()}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/email-accounts")}
    end
  end

  defp load_stats(socket) do
    account = socket.assigns.account
    actor = socket.assigns.current_user
    tz = account.tz || "Etc/UTC"

    today = DateTime.now!(tz) |> DateTime.to_date()
    from_date = Date.add(today, -@window_days)
    to_date = Date.add(today, @window_days + 1)

    from_dt = date_start_utc(from_date, tz)
    to_dt = date_start_utc(to_date, tz)

    rows =
      OutboundEmail.list_for_account_window!(
        account.id,
        from_dt,
        to_dt,
        actor: actor,
        load: [thread: [campaign_contact: [:person, :campaign]]]
      )

    points =
      Enum.map(rows, fn r ->
        ts = r.sent_at || r.scheduled_at
        local = DateTime.shift_zone!(ts, tz)
        date = DateTime.to_date(local)
        hour_frac = local.hour + local.minute / 60.0 + local.second / 3600.0

        cc = r.thread && r.thread.campaign_contact
        to_addr = (cc && cc.person && cc.person.email) || "—"
        campaign = (cc && cc.campaign && cc.campaign.name) || "—"

        %{
          date: date,
          hour: hour_frac,
          status: r.status,
          local_dt: local,
          to: to_addr,
          campaign: campaign
        }
      end)

    days =
      for offset <- -@window_days..@window_days do
        d = Date.add(today, offset)

        bucket =
          Enum.reduce(points, %{sent: 0, fail: 0, sched: 0}, fn p, acc ->
            if p.date == d do
              case p.status do
                :sent -> %{acc | sent: acc.sent + 1}
                s when s in [:failed, :bounced] -> %{acc | fail: acc.fail + 1}
                :scheduled -> %{acc | sched: acc.sched + 1}
                _ -> acc
              end
            else
              acc
            end
          end)

        Map.put(bucket, :date, d)
      end

    window_sent = Enum.sum(Enum.map(days, & &1.sent))

    window_scheduled_ahead =
      days
      |> Enum.filter(&(Date.compare(&1.date, today) != :lt))
      |> Enum.map(& &1.sched)
      |> Enum.sum()

    avg7 =
      days
      |> Enum.filter(fn d ->
        Date.compare(d.date, today) == :lt and
          Date.compare(d.date, Date.add(today, -7)) != :lt
      end)
      |> Enum.map(& &1.sent)
      |> case do
        [] -> 0.0
        xs -> Enum.sum(xs) / 7
      end

    max_day = days |> Enum.map(&(&1.sent + &1.fail + &1.sched)) |> Enum.max(fn -> 0 end)

    assign(socket,
      tz: tz,
      today: today,
      days: days,
      points: points,
      window_sent: window_sent,
      window_scheduled_ahead: window_scheduled_ahead,
      avg7: avg7,
      max_day: max(max_day, 1),
      window_days: @window_days
    )
  end

  defp date_start_utc(date, tz) do
    {:ok, dt} = DateTime.new(date, ~T[00:00:00.000000], tz)
    DateTime.shift_zone!(dt, "Etc/UTC")
  end

  # ── render ────────────────────────────────────────────────────────────
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:email_accounts}>
      <div class="max-w-[900px] w-full pb-16">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline kicker={gettext("Account · %{address}", address: @account.address)}>
            {raw(gettext("Sending <em>pattern</em>."))}
          </Liid.headline>

          <.link navigate={~p"/email-accounts"} class="no-underline">
            <Liid.btn size={:small} mono>
              <Liid.icon name="arrow" size={11} /> {gettext("All accounts")}
            </Liid.btn>
          </.link>
        </div>

        <div class="mb-7 grid grid-cols-3 gap-px bg-rule border border-rule rounded-[2px] overflow-hidden">
          <.stat_tile
            label={gettext("Sent · 28d window")}
            big={"#{@window_sent}"}
            sub={gettext("in tz %{tz}", tz: @tz)}
            accent
          />
          <.stat_tile
            label={gettext("Daily average · last 7d")}
            big={daily_avg_label(@avg7)}
            sub={gettext("sent / day")}
          />
          <.stat_tile
            label={gettext("Scheduled ahead")}
            big={"#{@window_scheduled_ahead}"}
            sub={gettext("next %{days}d", days: @window_days)}
          />
        </div>

        <section class="mb-7 border border-rule rounded-[2px] bg-paper p-5">
          <div class="flex items-center justify-between mb-4">
            <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">
              {gettext("Volume · ±%{days} days", days: @window_days)}
            </div>
            <.legend />
          </div>
          <.volume_bars days={@days} today={@today} max_day={@max_day} />
        </section>

        <section class="border border-rule rounded-[2px] bg-paper p-5">
          <div class="flex items-center justify-between mb-4">
            <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">
              {gettext("Pattern · time of day × day")}
            </div>
            <.legend />
          </div>
          <.scatter_map
            points={@points}
            today={@today}
            window_days={@window_days}
            from_addr={@account.address}
          />
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp daily_avg_label(avg) when is_float(avg) do
    :erlang.float_to_binary(avg, decimals: 1)
  end

  defp daily_avg_label(n), do: "#{n}"

  attr :label, :string, required: true
  attr :big, :string, required: true
  attr :sub, :string, default: nil
  attr :accent, :boolean, default: false

  defp stat_tile(assigns) do
    ~H"""
    <div class="px-6 py-5 bg-paper">
      <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55 mb-2">{@label}</div>
      <div
        class="font-serif text-[42px] font-normal leading-none tracking-[-0.02em] tabular-nums"
        style={@accent && "color: var(--accent);"}
      >
        {@big}
      </div>
      <div :if={@sub} class="mt-2 font-mono text-[11px] text-ink55 tracking-[0.04em]">{@sub}</div>
    </div>
    """
  end

  defp legend(assigns) do
    ~H"""
    <div class="flex items-center gap-4 font-mono text-[10px] tracking-[0.06em] uppercase text-ink55">
      <span class="inline-flex items-center gap-1.5">
        <span class="w-2 h-2 rounded-full" style="background: var(--accent);"></span> {gettext("sent")}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="w-2 h-2 rounded-full bg-fail"></span> {gettext("failed")}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="w-2 h-2 rounded-full" style="background: var(--ink55);"></span> {gettext(
          "scheduled"
        )}
      </span>
    </div>
    """
  end

  # ── volume bars (±14d) ─────────────────────────────────────────────────
  attr :days, :list, required: true
  attr :today, :any, required: true
  attr :max_day, :integer, required: true

  defp volume_bars(assigns) do
    n = length(assigns.days)
    width = 820
    height = 300
    plot_top = 16
    plot_bot = 260
    plot_left = 34
    plot_right = width - 8
    plot_w = plot_right - plot_left
    plot_h = plot_bot - plot_top
    slot = plot_w / n
    bar_w = slot * 0.78
    min_unit_h = plot_h / max(assigns.max_day, 1)

    bars =
      assigns.days
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        cx = plot_left + slot * i + slot / 2
        x = cx - bar_w / 2
        total_units = assigns.max_day

        scale = fn count ->
          if count > 0, do: max(count / total_units * plot_h, 4.0), else: 0
        end

        sent_h = scale.(d.sent)
        fail_h = scale.(d.fail)
        sched_h = scale.(d.sched)

        sent_y = plot_bot - sent_h
        fail_y = sent_y - fail_h
        sched_y = fail_y - sched_h

        %{
          date: d.date,
          x: x,
          cx: cx,
          bar_w: bar_w,
          sent: d.sent,
          fail: d.fail,
          sched: d.sched,
          sent_y: sent_y,
          sent_h: sent_h,
          fail_y: fail_y,
          fail_h: fail_h,
          sched_y: sched_y,
          sched_h: sched_h,
          is_today: Date.compare(d.date, assigns.today) == :eq,
          total: d.sent + d.fail + d.sched
        }
      end)

    _ = min_unit_h

    today_bar = Enum.find(bars, & &1.is_today)
    today_x = today_bar && today_bar.cx

    assigns =
      assign(assigns,
        width: width,
        height: height,
        plot_top: plot_top,
        plot_bot: plot_bot,
        plot_left: plot_left,
        plot_right: plot_right,
        bars: bars,
        today_x: today_x,
        max_day: assigns.max_day
      )

    ~H"""
    <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full h-auto" preserveAspectRatio="none">
      <line
        x1={@plot_left}
        y1={@plot_bot}
        x2={@plot_right}
        y2={@plot_bot}
        stroke="var(--rule)"
        stroke-width="1"
      />
      <line
        :if={@today_x}
        x1={@today_x}
        y1={@plot_top}
        x2={@today_x}
        y2={@plot_bot}
        stroke="var(--ink20)"
        stroke-width="1"
        stroke-dasharray="2 3"
      />

      <text
        x={@plot_left - 4}
        y={@plot_top + 8}
        text-anchor="end"
        font-family="JetBrains Mono, monospace"
        font-size="9"
        fill="var(--ink40)"
      >
        {@max_day}
      </text>
      <text
        x={@plot_left - 4}
        y={@plot_bot}
        text-anchor="end"
        font-family="JetBrains Mono, monospace"
        font-size="9"
        fill="var(--ink40)"
      >
        0
      </text>

      <%= for b <- @bars do %>
        <rect
          x={b.x}
          y={@plot_top}
          width={b.bar_w}
          height={@plot_bot - @plot_top}
          fill="var(--paperAlt)"
          opacity={if b.is_today, do: "1", else: "0.6"}
        />
        <rect
          :if={b.sched_h > 0}
          x={b.x}
          y={b.sched_y}
          width={b.bar_w}
          height={b.sched_h}
          fill="var(--ink55)"
          fill-opacity="0.85"
        />
        <rect
          :if={b.fail_h > 0}
          x={b.x}
          y={b.fail_y}
          width={b.bar_w}
          height={b.fail_h}
          fill="var(--fail)"
        />
        <rect
          :if={b.sent_h > 0}
          x={b.x}
          y={b.sent_y}
          width={b.bar_w}
          height={b.sent_h}
          fill="var(--accent)"
        />

        <text
          :if={b.total > 0}
          x={b.cx}
          y={b.sched_y - 4}
          text-anchor="middle"
          font-family="JetBrains Mono, monospace"
          font-size="9"
          fill="var(--ink55)"
        >
          {b.total}
        </text>

        <text
          :if={rem(b.date.day, 5) == 0 or b.is_today}
          x={b.cx}
          y={@plot_bot + 14}
          text-anchor="middle"
          font-family="JetBrains Mono, monospace"
          font-size="9"
          fill={if b.is_today, do: "var(--accent)", else: "var(--ink55)"}
        >
          {date_label(b.date)}
        </text>
      <% end %>
    </svg>
    """
  end

  defp date_label(date) do
    "#{pad2(date.month)}/#{pad2(date.day)}"
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"

  # ── scatter pattern map ───────────────────────────────────────────────
  attr :points, :list, required: true
  attr :today, :any, required: true
  attr :window_days, :integer, required: true
  attr :from_addr, :string, required: true

  defp scatter_map(assigns) do
    width = 820
    plot_left = 56
    plot_right = width - 12
    plot_top = 12
    plot_bot = 500
    plot_w = plot_right - plot_left
    plot_h = plot_bot - plot_top
    n_cols = assigns.window_days * 2 + 1
    col_w = plot_w / n_cols
    height = plot_bot + 24

    col_of = fn date ->
      diff = Date.diff(date, assigns.today)
      assigns.window_days + diff
    end

    from_addr = assigns[:from_addr] || "—"

    dot_for = fn p ->
      col = col_of.(p.date)

      if col >= 0 and col < n_cols do
        x = plot_left + col * col_w + col_w / 2
        y = plot_top + p.hour / 24.0 * plot_h

        tip =
          [
            Calendar.strftime(p.local_dt, "%Y-%m-%d %H:%M"),
            gettext("from %{addr}", addr: from_addr),
            gettext("to %{addr}", addr: p.to),
            gettext("campaign: %{campaign}", campaign: p.campaign),
            gettext("status: %{status}", status: to_string(p.status))
          ]
          |> Enum.join("\n")

        {:ok, %{x: x, y: y, status: p.status, tip: tip}}
      else
        :skip
      end
    end

    dots =
      assigns.points
      |> Enum.map(dot_for)
      |> Enum.flat_map(fn
        {:ok, d} -> [d]
        :skip -> []
      end)

    hour_ticks = [0, 6, 12, 18, 24]
    today_col = assigns.window_days

    cols =
      for offset <- -assigns.window_days..assigns.window_days do
        d = Date.add(assigns.today, offset)
        col = assigns.window_days + offset
        cx = plot_left + col * col_w + col_w / 2
        %{date: d, cx: cx, col: col, is_today: offset == 0}
      end

    assigns =
      assign(assigns,
        width: width,
        height: height,
        plot_left: plot_left,
        plot_right: plot_right,
        plot_top: plot_top,
        plot_bot: plot_bot,
        plot_w: plot_w,
        plot_h: plot_h,
        col_w: col_w,
        dots: dots,
        hour_ticks: hour_ticks,
        cols: cols,
        today_col: today_col
      )

    ~H"""
    <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full h-auto" preserveAspectRatio="none">
      <%= for h <- @hour_ticks do %>
        <% y = @plot_top + h / 24.0 * @plot_h %>
        <line
          x1={@plot_left}
          y1={y}
          x2={@plot_right}
          y2={y}
          stroke="var(--rule)"
          stroke-width="0.5"
        />
        <text
          x={@plot_left - 8}
          y={y + 3}
          text-anchor="end"
          font-family="JetBrains Mono, monospace"
          font-size="9"
          fill="var(--ink55)"
        >
          {pad2(h)}:00
        </text>
      <% end %>

      <%= for c <- @cols do %>
        <line
          :if={c.is_today}
          x1={c.cx}
          y1={@plot_top}
          x2={c.cx}
          y2={@plot_bot}
          stroke="var(--ink20)"
          stroke-width="1"
          stroke-dasharray="2 3"
        />
        <text
          :if={rem(c.date.day, 5) == 0 or c.is_today}
          x={c.cx}
          y={@plot_bot + 14}
          text-anchor="middle"
          font-family="JetBrains Mono, monospace"
          font-size="9"
          fill={if c.is_today, do: "var(--accent)", else: "var(--ink55)"}
        >
          {date_label(c.date)}
        </text>
      <% end %>

      <line
        x1={@plot_left}
        y1={@plot_bot}
        x2={@plot_right}
        y2={@plot_bot}
        stroke="var(--rule)"
        stroke-width="0.5"
      />

      <%= for d <- @dots do %>
        <g>
          <title>{d.tip}</title>
          <%= case d.status do %>
            <% :sent -> %>
              <circle cx={d.x} cy={d.y} r="4" fill="var(--accent)" fill-opacity="0.9" />
            <% s when s in [:failed, :bounced] -> %>
              <circle cx={d.x} cy={d.y} r="4" fill="var(--fail)" fill-opacity="0.9" />
            <% :scheduled -> %>
              <circle cx={d.x} cy={d.y} r="4" fill="var(--ink55)" fill-opacity="0.85" />
            <% _ -> %>
          <% end %>
        </g>
      <% end %>
    </svg>
    """
  end
end
