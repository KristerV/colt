defmodule ColtWeb.AdminLive do
  use ColtWeb, :live_view

  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-3xl font-semibold">Admin</h1>

        <Summary.tile_grid tiles={@admin_tiles} />
      </div>
    </Layouts.app>
    """
  end
end
