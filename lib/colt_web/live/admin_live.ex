defmodule ColtWeb.AdminLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tiles, tiles())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-3xl font-semibold">Admin</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <.link
            :for={tile <- @tiles}
            navigate={tile.path}
            class="card bg-base-200 hover:bg-base-300 border border-base-300 transition-colors"
          >
            <div class="card-body">
              <div class="text-xs uppercase tracking-wider opacity-60">{tile.kicker}</div>
              <div class="text-xl font-semibold">{tile.title}</div>
              <div class="text-sm font-mono tabular-nums opacity-70">{tile.value}</div>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp tiles do
    [
      %{
        kicker: "Data",
        title: "Companies",
        value: format_int(Ash.count!(Colt.Resources.Company)),
        path: "/admin/companies"
      },
      %{
        kicker: "Database",
        title: "Storage",
        value: ColtWeb.Admin.StorageLive.total_size(),
        path: "/admin/storage"
      }
    ]
  end

  defp format_int(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")
end
