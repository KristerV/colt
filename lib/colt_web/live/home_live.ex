defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Home")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-[760px]">
        <Liid.headline
          kicker="00 / Home"
          sub="No campaigns yet. Start a hunt to pull a candidate list, narrow with filters, and ship a CSV."
        >
          Welcome to <em>Liid</em>.
        </Liid.headline>

        <div class="mt-14 flex items-center gap-4">
          <Liid.btn variant={:primary} mono>
            New campaign <Liid.icon name="arrow" />
          </Liid.btn>
          <span class="font-mono text-[11px] text-ink40 tracking-[0.04em]">
            campaigns wizard ships in phase 2
          </span>
        </div>

        <div class="mt-20 border-t border-rule pt-6">
          <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink40 mb-4">
            Recent
          </div>
          <div class="text-[13px] text-ink55 italic">
            Nothing here yet.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
