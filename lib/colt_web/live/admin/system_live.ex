defmodule ColtWeb.Admin.SystemLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @tick_ms 1000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :cpu_sup.util([:detailed, :per_cpu])
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok, socket |> assign(:stats, read_stats()) |> assign(:tick_ms, @tick_ms)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :stats, read_stats())}
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

  # ---- readers ----

  defp read_stats do
    disks = read_disks()

    %{
      cpu: read_cpu(),
      ram: read_ram(),
      disks: disks,
      summary_disk: pick_summary_disk(disks),
      beam: read_beam()
    }
  end

  defp pick_summary_disk([]), do: %{mount: "/", percent: 0}

  defp pick_summary_disk(disks) do
    Enum.find(disks, &(&1.mount == "/")) || Enum.max_by(disks, & &1.percent)
  end

  defp read_cpu do
    aggregate = safe_cpu_util([:detailed])
    per_cpu = safe_cpu_util([:detailed, :per_cpu])

    %{busy: agg, steal: steal, wait: wait, idle: idle} = decode_cpu(aggregate)

    %{
      busy: agg,
      steal: steal,
      wait: wait,
      idle: idle,
      per_cpu: decode_per_cpu(per_cpu),
      cores: :erlang.system_info(:logical_processors),
      load1: :cpu_sup.avg1() / 256,
      load5: :cpu_sup.avg5() / 256,
      load15: :cpu_sup.avg15() / 256
    }
  end

  defp safe_cpu_util(opts) do
    :cpu_sup.util(opts)
  rescue
    _ -> nil
  end

  defp decode_cpu({_cpus, busy, non_busy, _opts}) do
    %{
      busy: sum_kw(busy),
      steal: Keyword.get(non_busy, :steal, 0.0),
      wait: Keyword.get(non_busy, :wait, 0.0),
      idle: Keyword.get(non_busy, :idle, 0.0)
    }
  end

  defp decode_cpu(_), do: %{busy: 0.0, steal: 0.0, wait: 0.0, idle: 0.0}

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
