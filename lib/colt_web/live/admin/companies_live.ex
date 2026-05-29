defmodule ColtWeb.Admin.CompaniesLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Company
  alias ColtWeb.Admin.Summary
  require Ash.Query

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :markets, load_market_stats())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-3xl font-semibold">Companies</h1>

        <div class="flex items-center gap-3">
          <.link navigate="/admin/oban" class="text-sm opacity-60 hover:opacity-100 font-mono">
            View Oban &rarr;
          </.link>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-sm font-mono border border-base-300">
            <thead class="bg-base-200">
              <tr class="text-left text-xs uppercase tracking-wider opacity-70">
                <th class="px-3 py-2 font-medium">Market</th>
                <th class="px-3 py-2 font-medium text-right">Active</th>
                <th class="px-3 py-2 font-medium text-right">With ≥1 report</th>
                <th class="px-3 py-2 font-medium text-right">With employees</th>
                <th class="px-3 py-2 font-medium text-right w-px"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @markets} class="border-t border-base-300">
                <td class="px-3 py-1.5">{market_label(m.market)}</td>
                <td :for={s <- m.stats} class="px-3 py-1.5 text-right tabular-nums">
                  {format(s.value)}
                </td>
                <td class="px-3 py-1.5 text-right">
                  <button
                    type="button"
                    phx-click="schedule_ingest"
                    phx-value-market={Atom.to_string(m.market)}
                    class="btn btn-xs btn-primary rounded-none"
                  >
                    Schedule
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("schedule_ingest", %{"market" => market_str}, socket) do
    market = String.to_existing_atom(market_str)

    case Colt.Markets.job_for(market) do
      nil ->
        {:noreply, put_flash(socket, :error, "No ingest job configured for #{market_str}.")}

      worker ->
        schedule_job(socket, worker, market_label(market))
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

  defp format(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")

  defp market_label(market) when is_atom(market) do
    case Enum.find(Colt.Markets.all(), &(&1.market == market)) do
      %{name: name, code: code} -> "#{name} (#{code})"
      nil -> market |> to_string() |> String.upcase()
    end
  end

  defp load_market_stats do
    %Postgrex.Result{rows: rows} =
      Colt.Repo.query!("SELECT DISTINCT market FROM companies ORDER BY market", [])

    Enum.map(rows, fn [market_str] ->
      market = String.to_existing_atom(market_str)

      %{
        market: market,
        stats: [
          %{label: "Active", value: count(:active, market)},
          %{label: "With ≥1 annual report", value: count(:with_annual_report, market)},
          %{label: "With employee count", value: count(:with_employees, market)}
        ]
      }
    end)
  end

  defp count(action, market) do
    Company
    |> Ash.Query.for_read(action)
    |> Ash.Query.filter(market == ^market)
    |> Ash.count!()
  end
end
