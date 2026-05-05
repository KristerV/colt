defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex items-center justify-center min-h-[60vh]">
        <p class="text-2xl">Hello.</p>
      </div>
    </Layouts.app>
    """
  end
end
