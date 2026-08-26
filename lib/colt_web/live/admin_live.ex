defmodule ColtWeb.AdminLive do
  use ColtWeb, :live_view

  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6 max-w-xl mx-auto">
        <Summary.summary_groups tiles={@admin_tiles} current_path={@admin_current_path} />
      </div>
    </Layouts.app>
    """
  end
end
