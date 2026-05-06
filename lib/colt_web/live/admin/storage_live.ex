defmodule ColtWeb.Admin.StorageLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:tables, load_tables()) |> assign(:total, total_size())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">Storage</h1>
        </div>

        <div class="card bg-base-200 border border-base-300 max-w-md">
          <div class="card-body">
            <div class="text-xs uppercase tracking-wider opacity-60">Total</div>
            <div class="text-3xl font-mono tabular-nums">{@total}</div>
          </div>
        </div>

        <table class="text-sm font-mono w-full max-w-md">
          <tbody>
            <tr :for={row <- @tables} class="border-b border-base-300">
              <td class="py-1 pr-6">{row.table}</td>
              <td class="py-1 tabular-nums text-right">{row.size}</td>
            </tr>
          </tbody>
        </table>
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
