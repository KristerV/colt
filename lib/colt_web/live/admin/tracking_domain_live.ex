defmodule ColtWeb.Admin.TrackingDomainLive do
  use ColtWeb, :live_view

  alias ColtWeb.Admin.Summary

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admin · Tracking domain",
       domain: Colt.AppSettings.tracking_domain() || "",
       saved_at: nil,
       error: nil
     )}
  end

  def handle_event("save", %{"domain" => raw}, socket) do
    case Colt.AppSettings.put_tracking_domain(raw) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           domain: Colt.AppSettings.tracking_domain() || "",
           saved_at: DateTime.utc_now(),
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Couldn't save: #{inspect(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />

        <div>
          <h1 class="text-3xl font-semibold">Tracking domain</h1>
          <p class="text-[13px] text-ink55 mt-2 max-w-[640px] leading-[1.55]">
            Site-wide CNAME used by every campaign with open or click tracking on. Set up once at your DNS provider, then enter it here — all campaigns flipping tracking on will route opens and link redirects through this hostname.
          </p>
        </div>

        <form
          phx-submit="save"
          class="border border-rule rounded-[2px] bg-paper p-6 max-w-[640px] space-y-4"
        >
          <label class="block font-mono text-[10px] uppercase tracking-[0.12em] text-ink55">
            Hostname
          </label>
          <input
            type="text"
            name="domain"
            value={@domain}
            placeholder="track.your-domain.com"
            class="w-full px-3 py-2 border border-ink20 bg-paper text-[13px] font-mono text-ink rounded-[2px] outline-none"
          />
          <div class="text-[12px] text-ink55 leading-[1.55]">
            Configure a CNAME record at your DNS provider pointing this hostname to <span class="font-mono text-ink70">tracking.nylas.com</span>. After DNS propagates, Nylas will sign and serve the tracking pixel + link redirector from your hostname.
          </div>
          <div :if={@error} class="text-[12px] text-fail">{@error}</div>
          <div class="flex items-center gap-3">
            <button
              type="submit"
              class="inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[12px] font-medium bg-ink text-paper border-ink cursor-pointer"
            >
              Save
            </button>
            <span :if={@saved_at} class="font-mono text-[11px] text-ink55">
              saved {Calendar.strftime(@saved_at, "%H:%M:%S")}
            </span>
          </div>
        </form>

        <div class="text-[12px] text-ink55 max-w-[640px] leading-[1.55]">
          Current value: <span class="font-mono text-ink">{(@domain != "" && @domain) || "—"}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
