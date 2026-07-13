defmodule ColtWeb.Admin.CompaniesLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Company
  alias Colt.Services.Ingest.Lt.Sodra.ManualHeadcountRefresh
  alias ColtWeb.Admin.Summary
  require Ash.Query

  @max_sodra_size 200 * 1024 * 1024

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:markets, load_market_stats())
      |> allow_upload(:sodra_zip,
        accept: ~w(.zip application/zip),
        max_entries: 1,
        max_file_size: @max_sodra_size
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
          Companies by <em>market</em>
        </h1>

        <div class="flex items-center gap-3">
          <.link navigate="/admin/oban" class="text-[13px] text-accent hover:underline">
            View Oban &rarr;
          </.link>
        </div>

        <div
          class="border border-border rounded-[11px] bg-card overflow-x-auto"
          style="box-shadow:var(--shadow-card)"
        >
          <table class="w-full text-[13px]">
            <thead>
              <tr class="text-left text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55 bg-paperAlt border-b border-border">
                <th class="px-3 py-2">Market</th>
                <th class="px-3 py-2 text-right">Active</th>
                <th class="px-3 py-2 text-right">With ≥1 report</th>
                <th class="px-3 py-2 text-right">With employees</th>
                <th class="px-3 py-2 text-right">With NACE code</th>
                <th class="px-3 py-2 text-right w-px"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={m <- @markets}
                class="border-b border-border last:border-b-0 hover:bg-paperAlt"
              >
                <td class="px-3 py-1.5 text-ink">{market_label(m.market)}</td>
                <td :for={s <- m.stats} class="px-3 py-1.5 text-right tabular-nums text-ink70">
                  {format(s.value)}
                </td>
                <td class="px-3 py-1.5 text-right">
                  <button
                    type="button"
                    phx-click="schedule_ingest"
                    phx-value-market={Atom.to_string(m.market)}
                    class="bg-accent text-white text-[11px] font-semibold rounded-[8px] px-3 py-1.5 cursor-pointer hover:opacity-90"
                  >
                    Schedule
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          class="border border-border rounded-[11px] bg-card p-5 max-w-[560px]"
          style="box-shadow:var(--shadow-card)"
        >
          <h2 class="text-[15px] font-semibold tracking-[-0.01em] text-ink m-0">
            Refresh <em>Lithuanian</em> headcount
          </h2>
          <p class="mt-2 text-[13px] leading-[1.55] text-ink70">
            Download the per-employer insured-persons ZIP from <a
              href="https://atvira.sodra.lt/en-eur/"
              target="_blank"
              rel="noopener"
              class="text-accent hover:underline"
            >Sodra open data</a>, then upload it here to refresh Lithuanian employee counts.
          </p>

          <form phx-change="validate_sodra" phx-submit="upload_sodra" autocomplete="off" class="mt-4">
            <div class="flex flex-wrap items-center gap-3">
              <.live_file_input upload={@uploads.sodra_zip} class="sr-only" />
              <label
                for={@uploads.sodra_zip.ref}
                class="inline-flex items-center px-3 py-1.5 text-[12px] font-semibold border border-border bg-card rounded-[8px] text-ink70 cursor-pointer hover:bg-paperAlt hover:text-ink"
              >
                Choose ZIP
              </label>
              <button
                type="submit"
                disabled={@uploads.sodra_zip.entries == []}
                class="bg-accent text-white text-[12px] font-semibold rounded-[8px] px-3 py-1.5 cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                Import &amp; refresh
              </button>
            </div>

            <div :for={entry <- @uploads.sodra_zip.entries} class="mt-3 text-[12px] text-ink70">
              {entry.client_name}
              <span :for={err <- upload_errors(@uploads.sodra_zip, entry)} class="ml-2 text-red">
                {sodra_error(err)}
              </span>
            </div>
          </form>
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

  def handle_event("validate_sodra", _params, socket), do: {:noreply, socket}

  def handle_event("upload_sodra", _params, socket) do
    results =
      consume_uploaded_entries(socket, :sodra_zip, fn %{path: tmp_path}, _entry ->
        dest =
          Path.join(System.tmp_dir!(), "sodra_upload_#{System.unique_integer([:positive])}.zip")

        result =
          try do
            File.cp!(tmp_path, dest)
            ManualHeadcountRefresh.run(dest)
          rescue
            e -> {:error, Exception.message(e)}
          after
            File.rm(dest)
          end

        {:ok, result}
      end)

    case results do
      [{:ok, %{processed: processed, updated: updated}}] ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Sodra headcount imported: #{format(processed)} report rows, #{format(updated)} companies updated."
         )}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Sodra import failed: #{inspect(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded.")}
    end
  end

  defp sodra_error(:too_large), do: "File is too large (max 200 MB)."
  defp sodra_error(:not_accepted), do: "Only .zip files are accepted."
  defp sodra_error(:too_many_files), do: "Upload a single file."
  defp sodra_error(err), do: to_string(err)

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
          %{label: "With employee count", value: count(:with_employees, market)},
          %{label: "With NACE code", value: count(:with_nace_code, market)}
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
