defmodule ColtWeb.Admin.CountriesLive do
  use ColtWeb, :live_view

  alias Colt.Markets
  alias Colt.Resources.Company
  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :countries, load_countries())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
          Companies by <em>country</em>
        </h1>

        <p class="text-[13px] text-ink70 max-w-[68ch]">
          Every country in the registry plus every country declared in <code>config :colt, :markets</code>. Config decides what users are offered —
          a country is only in the campaign picker and live on the landing when it's <strong>available</strong>. Counts are memoized 24h; recompute to see an ingest that just landed.
        </p>

        <div class="flex items-center gap-3">
          <.link navigate="/admin/oban" class="text-[13px] text-accent hover:underline">
            View Oban &rarr;
          </.link>
          <button
            type="button"
            phx-click="refresh_stats"
            class="border border-border rounded-[8px] px-3 py-1.5 text-[11px] font-semibold text-ink70 hover:bg-paperAlt cursor-pointer phx-click-loading:opacity-50"
          >
            Recompute from live data
          </button>
        </div>

        <div
          class="border border-border rounded-[11px] bg-card overflow-x-auto"
          style="box-shadow:var(--shadow-card)"
        >
          <table class="w-full text-[13px]">
            <thead>
              <tr class="text-left text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55 bg-paperAlt border-b border-border">
                <th class="px-3 py-2">Country</th>
                <th class="px-3 py-2">Offered to users</th>
                <th class="px-3 py-2 text-right">Active</th>
                <th class="px-3 py-2 text-right">With ≥1 report</th>
                <th class="px-3 py-2 text-right">With employees</th>
                <th class="px-3 py-2 text-right">With NACE code</th>
                <th class="px-3 py-2 text-right w-px"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={c <- @countries}
                class="border-b border-border last:border-b-0 hover:bg-paperAlt"
              >
                <td class="px-3 py-1.5 text-ink whitespace-nowrap">{c.label}</td>
                <td class="px-3 py-1.5"><.status_chip country={c} /></td>
                <td
                  :for={value <- c.counts}
                  class="px-3 py-1.5 text-right tabular-nums text-ink70"
                >
                  {format(value)}
                </td>
                <td class="px-3 py-1.5 text-right">
                  <button
                    :if={c.job?}
                    type="button"
                    phx-click="schedule_ingest"
                    phx-value-market={Atom.to_string(c.market)}
                    class="bg-accent text-white text-[11px] font-semibold rounded-[8px] px-3 py-1.5 cursor-pointer hover:opacity-90"
                  >
                    Schedule
                  </button>
                  <span :if={not c.job?} class="text-[11px] text-inkFaint">No ingest</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :country, :map, required: true

  # Four states, but only two are mistakes: offered with nothing behind it (users
  # get an empty result set) and data sitting behind a flag nobody flipped.
  defp status_chip(%{country: %{status: :live}} = assigns) do
    ~H"""
    <span class={chip_class("bg-green-50 text-green-700 border-green-200")}>
      <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span> Available
    </span>
    """
  end

  defp status_chip(%{country: %{status: :available_no_data}} = assigns) do
    ~H"""
    <span class={chip_class("bg-red-50 text-red-700 border-red-200")}>
      <span class="w-1.5 h-1.5 rounded-full bg-red-500"></span> Available · no data
    </span>
    """
  end

  defp status_chip(%{country: %{status: :data_not_offered}} = assigns) do
    ~H"""
    <span class={chip_class("bg-amber-50 text-amber-700 border-amber-200")}>
      <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span> Has data · not offered
    </span>
    """
  end

  defp status_chip(%{country: %{status: :undeclared}} = assigns) do
    ~H"""
    <span class={chip_class("bg-amber-50 text-amber-700 border-amber-200")}>
      <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span> Not in config
    </span>
    """
  end

  defp status_chip(assigns) do
    ~H"""
    <span class={chip_class("bg-paperAlt text-ink55 border-border")}>Not available</span>
    """
  end

  defp chip_class(colors) do
    "inline-flex items-center gap-1.5 border rounded-[8px] px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap #{colors}"
  end

  def handle_event("refresh_stats", _params, socket) do
    Company.refresh_market_stats()
    Company.analyze()

    socket =
      socket
      |> assign(:countries, load_countries())
      |> assign(:admin_tiles, Summary.tiles())

    {:noreply, socket}
  end

  def handle_event("schedule_ingest", %{"market" => market_str}, socket) do
    market = String.to_existing_atom(market_str)

    case Markets.job_for(market) do
      nil ->
        {:noreply, put_flash(socket, :error, "No ingest job configured for #{market_str}.")}

      worker ->
        schedule_job(socket, worker, Markets.label(market))
    end
  end

  defp schedule_job(socket, worker, label) do
    case worker.new(%{}) |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "#{label} ingestion already scheduled or running.")}

      {:ok, %Oban.Job{}} ->
        {:noreply, put_flash(socket, :info, "#{label} ingestion job scheduled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not schedule job: #{inspect(reason)}")}
    end
  end

  defp format(nil), do: "—"
  defp format(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")

  # Config order first (it's the source of truth and the order the landing renders
  # in), then any market carrying rows that config no longer declares.
  defp load_countries do
    stats = Map.new(Company.market_stats!(), &{&1.market, &1})

    declared = Enum.map(Markets.all(), &build_row(&1.market, &1.available, stats[&1.market]))

    undeclared =
      stats
      |> Map.drop(Markets.atoms())
      |> Enum.map(fn {market, row} -> build_row(market, false, row) end)
      |> Enum.sort_by(& &1.market)

    declared ++ undeclared
  end

  defp build_row(market, available, stats) do
    %{
      market: market,
      label: Markets.label(market),
      available: available,
      job?: Markets.job_for(market) != nil,
      status: status(market, available, stats),
      counts: counts(stats)
    }
  end

  defp counts(nil), do: [nil, nil, nil, nil]

  defp counts(stats),
    do: [stats.active, stats.with_annual_report, stats.with_employees, stats.with_nace_code]

  defp status(market, available, stats) do
    data? = stats != nil and stats.active > 0

    cond do
      Markets.get(market) == nil -> :undeclared
      available and data? -> :live
      available -> :available_no_data
      data? -> :data_not_offered
      true -> :unavailable
    end
  end
end
