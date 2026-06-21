defmodule ColtWeb.Admin.StorageLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  alias ColtWeb.Admin.Summary

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:tables, load_tables()) |> assign(:total, total_size())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
          Database <em>storage</em>
        </h1>

        <div
          class="bg-card border border-border rounded-[11px] max-w-md p-5"
          style="box-shadow:var(--shadow-card)"
        >
          <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">Total</div>
          <div class="text-[27px] font-bold tabular-nums leading-none tracking-[-0.02em] text-ink mt-2">
            {@total}
          </div>
        </div>

        <div
          class="border border-border rounded-[11px] bg-card max-w-md overflow-hidden"
          style="box-shadow:var(--shadow)"
        >
          <table class="text-[13px] w-full">
            <tbody>
              <tr
                :for={row <- @tables}
                class="border-b border-border last:border-b-0 hover:bg-paperAlt"
              >
                <td class="px-4 py-1.5 text-ink">{row.table}</td>
                <td class="px-4 py-1.5 tabular-nums text-right text-ink70">{row.size}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def total_size do
    %Postgrex.Result{rows: [[bytes]]} =
      Colt.Repo.query!(
        """
        SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r' AND n.nspname = 'public'
        """,
        []
      )

    format_gb(bytes)
  end

  defp load_tables do
    %Postgrex.Result{rows: rows} =
      Colt.Repo.query!(
        """
        SELECT c.relname, pg_total_relation_size(c.oid)::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r' AND n.nspname = 'public'
        ORDER BY pg_total_relation_size(c.oid) DESC
        """,
        []
      )

    Enum.map(rows, fn [name, bytes] -> %{table: name, size: format_gb(bytes)} end)
  end

  defp format_gb(bytes) do
    gb = bytes / 1024 / 1024 / 1024
    :erlang.float_to_binary(gb, decimals: 3) <> " GB"
  end
end
