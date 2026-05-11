defmodule ColtWeb.Admin.SystemLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @tick_ms 1000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :cpu_sup.util([:detailed, :per_cpu])
      :timer.send_interval(@tick_ms, :tick)
    end

    prev = sample_diskstats()
    {stats, _} = read_stats(prev, @tick_ms)

    {:ok,
     socket
     |> assign(:stats, stats)
     |> assign(:prev_diskstats, prev)
     |> assign(:tick_ms, @tick_ms)}
  end

  def handle_info(:tick, socket) do
    {stats, next_prev} = read_stats(socket.assigns.prev_diskstats, @tick_ms)
    {:noreply, socket |> assign(:stats, stats) |> assign(:prev_diskstats, next_prev)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">System</h1>
          <p class="text-xs opacity-60 mt-1 font-mono">refreshing every {@tick_ms}ms</p>
        </div>

        <section class="grid grid-cols-3 gap-4">
          <.summary label="CPU" value={pct(@stats.cpu.busy)} accent={busy_accent(@stats.cpu.busy)} />
          <.summary
            label="RAM"
            value={pct(@stats.ram.used_pct)}
            accent={ram_accent(@stats.ram.used_pct)}
          />
          <.summary
            label={"Disk " <> @stats.summary_disk.mount}
            value={"#{@stats.summary_disk.percent}%"}
            accent={disk_accent(@stats.summary_disk.percent)}
          />
        </section>

        <section class="space-y-3">
          <h2 class="text-xs uppercase tracking-wider opacity-60">CPU</h2>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric
              label="App busy"
              value={pct(@stats.cpu.busy)}
              accent={busy_accent(@stats.cpu.busy)}
            />
            <.metric
              label="Steal"
              value={pct(@stats.cpu.steal)}
              accent={steal_accent(@stats.cpu.steal)}
            />
            <.metric label="Wait" value={pct(@stats.cpu.wait)} />
            <.metric label="Idle" value={pct(@stats.cpu.idle)} />
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric label="Load 1m" value={load(@stats.cpu.load1)} />
            <.metric label="Load 5m" value={load(@stats.cpu.load5)} />
            <.metric label="Load 15m" value={load(@stats.cpu.load15)} />
            <.metric label="vCPUs" value={Integer.to_string(@stats.cpu.cores)} />
          </div>

          <table :if={@stats.cpu.per_cpu != []} class="text-sm font-mono w-full max-w-xl mt-3">
            <thead>
              <tr class="text-xs uppercase tracking-wider opacity-60">
                <th class="text-left py-1">vCPU</th>
                <th class="text-right py-1">busy</th>
                <th class="text-right py-1">steal</th>
                <th class="text-right py-1">wait</th>
                <th class="text-right py-1">idle</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={c <- @stats.cpu.per_cpu} class="border-t border-base-300">
                <td class="py-1">{c.id}</td>
                <td class="py-1 tabular-nums text-right">{pct(c.busy)}</td>
                <td class="py-1 tabular-nums text-right">{pct(c.steal)}</td>
                <td class="py-1 tabular-nums text-right">{pct(c.wait)}</td>
                <td class="py-1 tabular-nums text-right">{pct(c.idle)}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="space-y-3">
          <h2 class="text-xs uppercase tracking-wider opacity-60">Memory</h2>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric label="System used" value={pct(@stats.ram.used_pct)} />
            <.metric label="Used" value={mb(@stats.ram.used)} />
            <.metric label="Available" value={mb(@stats.ram.available)} />
            <.metric label="Total" value={mb(@stats.ram.total)} />
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric label="BEAM total" value={mb(@stats.ram.beam_total)} />
            <.metric label="Processes" value={mb(@stats.ram.beam_processes)} />
            <.metric label="Binary" value={mb(@stats.ram.beam_binary)} />
            <.metric label="ETS" value={mb(@stats.ram.beam_ets)} />
          </div>
        </section>

        <section :if={@stats.disks != []} class="space-y-3">
          <h2 class="text-xs uppercase tracking-wider opacity-60">Disk</h2>

          <table class="text-sm font-mono w-full max-w-2xl">
            <thead>
              <tr class="text-xs uppercase tracking-wider opacity-60">
                <th class="text-left py-1">mount</th>
                <th class="text-right py-1">used</th>
                <th class="text-right py-1">total</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={d <- @stats.disks} class="border-t border-base-300">
                <td class="py-1">{d.mount}</td>
                <td class={[
                  "py-1 tabular-nums text-right",
                  d.percent >= 85 && "text-error font-semibold"
                ]}>
                  {d.percent}%
                </td>
                <td class="py-1 tabular-nums text-right">{gb(d.total_kb * 1024)}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section :if={@stats.disk_io != []} class="space-y-3">
          <h2 class="text-xs uppercase tracking-wider opacity-60">Disk I/O</h2>
          <p class="text-[11px] opacity-60 font-mono">
            %util = fraction of time the device had I/O in flight. ~100% means saturated.
          </p>

          <table class="text-sm font-mono w-full max-w-4xl">
            <thead>
              <tr class="text-xs uppercase tracking-wider opacity-60">
                <th class="text-left py-1">device</th>
                <th class="text-right py-1">read MB/s</th>
                <th class="text-right py-1">write MB/s</th>
                <th class="text-right py-1">r/s</th>
                <th class="text-right py-1">w/s</th>
                <th class="text-right py-1">in-flight</th>
                <th class="text-right py-1">%util</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={d <- @stats.disk_io} class="border-t border-base-300">
                <td class="py-1">{d.name}</td>
                <td class="py-1 tabular-nums text-right">{mbps(d.read_bps)}</td>
                <td class="py-1 tabular-nums text-right">{mbps(d.write_bps)}</td>
                <td class="py-1 tabular-nums text-right">{rate(d.read_iops)}</td>
                <td class="py-1 tabular-nums text-right">{rate(d.write_iops)}</td>
                <td class="py-1 tabular-nums text-right">{d.in_flight}</td>
                <td class={[
                  "py-1 tabular-nums text-right",
                  util_accent(d.util_pct)
                ]}>
                  {pct(d.util_pct)}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="space-y-3">
          <h2 class="text-xs uppercase tracking-wider opacity-60">BEAM</h2>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric
              label="Processes"
              value={"#{@stats.beam.processes} / #{@stats.beam.process_limit}"}
            />
            <.metric label="Run queue" value={Integer.to_string(@stats.beam.run_queue)} />
            <.metric label="Schedulers" value={Integer.to_string(@stats.beam.schedulers)} />
            <.metric label="Atoms" value={Integer.to_string(@stats.beam.atoms)} />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :accent, :string, default: nil

  defp metric(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4">
        <div class="text-[10px] uppercase tracking-wider opacity-60">{@label}</div>
        <div class={["text-xl font-mono tabular-nums mt-1", @accent]}>{@value}</div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :accent, :string, default: nil

  defp summary(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-5">
        <div class="text-xs uppercase tracking-wider opacity-60">{@label}</div>
        <div class={["text-4xl font-mono tabular-nums mt-2", @accent]}>{@value}</div>
      </div>
    </div>
    """
  end

  # ---- formatters ----

  defp pct(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1) <> "%"
  defp pct(_), do: "—"

  defp load(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp load(_), do: "—"

  defp mb(n) when is_integer(n), do: "#{div(n, 1024 * 1024)} MB"
  defp mb(_), do: "—"

  defp gb(n) when is_integer(n),
    do: :erlang.float_to_binary(n / 1024 / 1024 / 1024, decimals: 1) <> " GB"

  defp gb(_), do: "—"

  defp busy_accent(n) when n >= 80, do: "text-error"
  defp busy_accent(_), do: nil

  defp steal_accent(n) when n >= 20, do: "text-error"
  defp steal_accent(n) when n >= 5, do: "text-warning"
  defp steal_accent(_), do: nil

  defp ram_accent(n) when n >= 90, do: "text-error"
  defp ram_accent(n) when n >= 75, do: "text-warning"
  defp ram_accent(_), do: nil

  defp disk_accent(n) when n >= 90, do: "text-error"
  defp disk_accent(n) when n >= 75, do: "text-warning"
  defp disk_accent(_), do: nil

  defp util_accent(n) when n >= 80, do: "text-error"
  defp util_accent(n) when n >= 50, do: "text-warning"
  defp util_accent(_), do: nil

  defp mbps(bps) when is_number(bps),
    do: :erlang.float_to_binary(bps / 1024 / 1024, decimals: 1)

  defp mbps(_), do: "—"

  defp rate(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 0)
  defp rate(_), do: "—"

  # ---- readers ----

  defp read_stats(prev_diskstats, tick_ms) do
    disks = read_disks()
    next_diskstats = sample_diskstats()
    disk_io = diff_diskstats(prev_diskstats, next_diskstats, tick_ms)

    stats = %{
      cpu: read_cpu(),
      ram: read_ram(),
      disks: disks,
      disk_io: disk_io,
      summary_disk: pick_summary_disk(disks),
      beam: read_beam()
    }

    {stats, next_diskstats}
  end

  defp pick_summary_disk([]), do: %{mount: "/", percent: 0}

  defp pick_summary_disk(disks) do
    Enum.find(disks, &(&1.mount == "/")) || Enum.max_by(disks, & &1.percent)
  end

  # `:cpu_sup.util/1` reports utilization since the previous call on this node,
  # so calling it twice per tick makes the second call measure only the
  # microseconds between the two — yielding bogus 100%/0% per-core readings.
  # Sample once and derive the aggregate from the per-cpu list.
  defp read_cpu do
    per_cpu = decode_per_cpu(safe_cpu_util([:detailed, :per_cpu]))
    agg = aggregate_per_cpu(per_cpu)

    %{
      busy: agg.busy,
      steal: agg.steal,
      wait: agg.wait,
      idle: agg.idle,
      per_cpu: per_cpu,
      cores: :erlang.system_info(:logical_processors),
      load1: :cpu_sup.avg1() / 256,
      load5: :cpu_sup.avg5() / 256,
      load15: :cpu_sup.avg15() / 256
    }
  end

  defp aggregate_per_cpu([]), do: %{busy: 0.0, steal: 0.0, wait: 0.0, idle: 0.0}

  defp aggregate_per_cpu(list) do
    n = length(list)

    list
    |> Enum.reduce(%{busy: 0.0, steal: 0.0, wait: 0.0, idle: 0.0}, fn c, acc ->
      %{
        busy: acc.busy + c.busy,
        steal: acc.steal + c.steal,
        wait: acc.wait + c.wait,
        idle: acc.idle + c.idle
      }
    end)
    |> Map.new(fn {k, v} -> {k, v / n} end)
  end

  defp safe_cpu_util(opts) do
    :cpu_sup.util(opts)
  rescue
    _ -> nil
  end

  defp decode_per_cpu(list) when is_list(list) do
    Enum.map(list, fn {id, busy, non_busy, _opts} ->
      %{
        id: id,
        busy: sum_kw(busy),
        steal: Keyword.get(non_busy, :steal, 0.0),
        wait: Keyword.get(non_busy, :wait, 0.0),
        idle: Keyword.get(non_busy, :idle, 0.0)
      }
    end)
  end

  defp decode_per_cpu(_), do: []

  defp sum_kw(kw), do: Enum.reduce(kw, 0.0, fn {_, v}, a -> a + v end)

  defp read_ram do
    data = :memsup.get_system_memory_data()
    total = Keyword.get(data, :total_memory) || Keyword.get(data, :system_total_memory) || 0
    free = Keyword.get(data, :free_memory, 0)
    cached = Keyword.get(data, :cached_memory, 0)
    buffered = Keyword.get(data, :buffered_memory, 0)
    available = Keyword.get(data, :available_memory) || free + cached + buffered
    used = max(total - available, 0)

    used_pct = if total > 0, do: used * 100 / total, else: 0.0

    beam = :erlang.memory()

    %{
      total: total,
      used: used,
      available: available,
      used_pct: used_pct,
      beam_total: Keyword.get(beam, :total, 0),
      beam_processes: Keyword.get(beam, :processes, 0),
      beam_binary: Keyword.get(beam, :binary, 0),
      beam_ets: Keyword.get(beam, :ets, 0)
    }
  end

  defp read_disks do
    :disksup.get_disk_data()
    |> Enum.map(fn {mount, total_kb, percent} ->
      %{mount: to_string(mount), total_kb: total_kb, percent: percent}
    end)
    |> Enum.sort_by(& &1.mount)
  rescue
    _ -> []
  end

  # /proc/diskstats fields (per `Documentation/admin-guide/iostats.rst`):
  #   1 major, 2 minor, 3 name,
  #   4 reads done, 5 reads merged, 6 sectors read, 7 ms reading,
  #   8 writes done, 9 writes merged, 10 sectors written, 11 ms writing,
  #   12 ios in flight, 13 ms doing io (busy time), 14 weighted ms doing io
  # Sectors are 512 bytes.
  @sector_bytes 512

  defp sample_diskstats do
    case File.read("/proc/diskstats") do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_diskstat_line/1)
        |> Enum.filter(&keep_device?/1)
        |> Map.new(&{&1.name, &1})

      _ ->
        %{}
    end
  end

  defp parse_diskstat_line(line) do
    case String.split(line) do
      [_maj, _min, name, r, _rm, rs, _rt, w, _wm, ws, _wt, inflight, busy_ms | _] ->
        with {r, ""} <- Integer.parse(r),
             {rs, ""} <- Integer.parse(rs),
             {w, ""} <- Integer.parse(w),
             {ws, ""} <- Integer.parse(ws),
             {inflight, ""} <- Integer.parse(inflight),
             {busy_ms, ""} <- Integer.parse(busy_ms) do
          [
            %{
              name: name,
              reads: r,
              sectors_read: rs,
              writes: w,
              sectors_written: ws,
              in_flight: inflight,
              busy_ms: busy_ms
            }
          ]
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  # Skip partitions/loop/ram/zram — show physical devices and dm-* volumes only.
  defp keep_device?(%{name: name}) do
    cond do
      String.starts_with?(name, "loop") -> false
      String.starts_with?(name, "ram") -> false
      String.starts_with?(name, "zram") -> false
      # nvme0n1p1 (partition) → skip; nvme0n1 (device) → keep
      Regex.match?(~r/^nvme\d+n\d+p\d+$/, name) -> false
      # sda1/sdb2 partitions → skip; sda/sdb → keep
      Regex.match?(~r/^sd[a-z]+\d+$/, name) -> false
      true -> true
    end
  end

  defp diff_diskstats(prev, _next, _tick_ms) when map_size(prev) == 0, do: []

  defp diff_diskstats(prev, next, tick_ms) do
    secs = tick_ms / 1000

    next
    |> Enum.flat_map(fn {name, n} ->
      case Map.fetch(prev, name) do
        {:ok, p} -> [compute_disk_rate(name, p, n, secs)]
        :error -> []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp compute_disk_rate(name, prev, next, secs) do
    dr = max(next.reads - prev.reads, 0)
    dw = max(next.writes - prev.writes, 0)
    drs = max(next.sectors_read - prev.sectors_read, 0)
    dws = max(next.sectors_written - prev.sectors_written, 0)
    dbusy = max(next.busy_ms - prev.busy_ms, 0)

    %{
      name: name,
      read_iops: dr / secs,
      write_iops: dw / secs,
      read_bps: drs * @sector_bytes / secs,
      write_bps: dws * @sector_bytes / secs,
      in_flight: next.in_flight,
      util_pct: min(dbusy / (secs * 1000) * 100, 100.0)
    }
  end

  defp read_beam do
    %{
      processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: :erlang.system_info(:schedulers_online),
      atoms: :erlang.system_info(:atom_count)
    }
  end
end
