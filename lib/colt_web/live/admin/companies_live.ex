defmodule ColtWeb.Admin.CompaniesLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Company
  require Ash.Query

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :markets, load_market_stats())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">Companies</h1>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <button
            type="button"
            phx-click="schedule_rik_ingest"
            class="btn btn-primary btn-sm rounded-none"
          >
            Schedule rik.ee ingestion
          </button>
          <.link navigate="/admin/oban" class="text-sm opacity-60 hover:opacity-100 font-mono">
            View Oban &rarr;
          </.link>
        </div>

        <div :for={m <- @markets} class="space-y-3">
          <div class="text-xs uppercase tracking-wider opacity-60 font-mono">
            {market_label(m.market)}
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <.stat :for={s <- m.stats} label={s.label} value={s.value} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("schedule_rik_ingest", _params, socket) do
    case Colt.Jobs.RikIngest.new(%{}) |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "rik.ee ingestion already scheduled or running.")}

      {:ok, %Oban.Job{}} ->
        {:noreply, put_flash(socket, :info, "rik.ee ingestion job scheduled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not schedule job: #{inspect(reason)}")}
    end
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body">
        <div class="text-xs uppercase tracking-wider opacity-60">{@label}</div>
        <div class="text-3xl font-mono tabular-nums">{format(@value)}</div>
      </div>
    </div>
    """
  end

  defp format(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")

  defp market_label(:ee), do: "Estonia (EE)"
  defp market_label(:fi), do: "Finland (FI)"
  defp market_label(:lv), do: "Latvia (LV)"
  defp market_label(:lt), do: "Lithuania (LT)"
  defp market_label(:se), do: "Sweden (SE)"
  defp market_label(:no), do: "Norway (NO)"
  defp market_label(other), do: other |> to_string() |> String.upcase()

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
