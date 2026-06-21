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
          <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">
            Tracking <em>domain</em>
          </h1>
          <p class="text-[13px] text-ink55 mt-2 max-w-[640px] leading-[1.55]">
            Site-wide CNAME used by every campaign with open or click tracking on. Set up once at your DNS provider, then enter it here — all campaigns flipping tracking on will route opens and link redirects through this hostname.
          </p>
        </div>

        <form
          phx-submit="save"
          class="border border-border rounded-[11px] bg-card p-5 md:p-6 max-w-[640px] space-y-4"
          style="box-shadow:var(--shadow-card)"
        >
          <label class="block text-[10px] font-semibold uppercase tracking-[0.08em] text-ink55">
            Hostname
          </label>
          <input
            type="text"
            name="domain"
            value={@domain}
            placeholder="track.your-domain.com"
            class="w-full px-3 py-2 border border-border bg-card text-[13px] text-ink rounded-[8px] outline-none focus:border-accentRing"
          />
          <div class="text-[12px] text-ink55 leading-[1.55]">
            Configure a CNAME record at your DNS provider pointing this hostname to <span class="text-ink70">tracking.nylas.com</span>. After DNS propagates, Nylas will sign and serve the tracking pixel + link redirector from your hostname.
          </div>
          <div :if={@error} class="text-[12px] text-red">{@error}</div>
          <div class="flex items-center gap-3">
            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded-[8px] px-[18px] py-[10px] text-[12px] font-semibold bg-accent text-white cursor-pointer hover:opacity-90"
            >
              Save
            </button>
            <span :if={@saved_at} class="text-[11px] text-ink55 tabular-nums">
              saved {Calendar.strftime(@saved_at, "%H:%M:%S")}
            </span>
          </div>
        </form>

        <div class="text-[12px] text-ink55 max-w-[640px] leading-[1.55]">
          Current value: <span class="text-ink">{(@domain != "" && @domain) || "—"}</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
