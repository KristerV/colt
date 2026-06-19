defmodule ColtWeb.Sending.SettingsLive do
  @moduledoc """
  Campaign-level sending settings: open/click tracking and the auto-approve
  toggle. Per-sequence controls (boost, enable, structure, writing) live in
  the Sequences view.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}
  on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        {:ok,
         assign(socket,
           page_title: gettext("Settings — %{name}", name: campaign.name),
           campaign: campaign,
           tracking_on?: campaign.tracking_opens? || campaign.tracking_clicks?,
           saved_at: nil
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("toggle_auto_approve", _params, socket) do
    campaign = socket.assigns.campaign

    {:ok, campaign} =
      Campaign.set_auto_approve_on(campaign, !campaign.auto_approve_on?,
        actor: socket.assigns.current_user
      )

    # Turning it on: kick the starter now so the schedule fills up while the
    # user watches, instead of waiting for the hourly cron.
    if campaign.auto_approve_on?, do: Colt.Jobs.AutoApproveCampaign.enqueue(campaign.id)

    {:noreply, socket |> assign(campaign: campaign) |> mark_saved()}
  end

  def handle_event("toggle_panic", _params, socket) do
    campaign = socket.assigns.campaign

    {:ok, campaign} =
      Campaign.set_panic(campaign, !campaign.panic_switch_on, actor: socket.assigns.current_user)

    {:noreply, socket |> assign(campaign: campaign) |> mark_saved()}
  end

  def handle_event("toggle_tracking", %{"field" => field}, socket) do
    campaign = socket.assigns.campaign

    {opens, clicks} =
      case field do
        "opens" -> {!campaign.tracking_opens?, campaign.tracking_clicks?}
        "clicks" -> {campaign.tracking_opens?, !campaign.tracking_clicks?}
      end

    {:ok, campaign} =
      Campaign.set_tracking(campaign, opens, clicks, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(campaign: campaign, tracking_on?: opens || clicks)
     |> mark_saved()}
  end

  defp mark_saved(socket), do: assign(socket, saved_at: DateTime.utc_now())

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:settings}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[760px] mx-auto pb-16">
        <Liid.headline
          kicker={gettext("Sending · Settings")}
          sub={gettext("Campaign-wide sending controls. Per-variant tuning lives under Variants.")}
        >
          {raw(gettext("Sending <em>settings</em>."))}
        </Liid.headline>

        <.section_divider label={gettext("Tracking")} />
        <.setting_row
          label={gettext("Open tracking")}
          hint={gettext("Pixel embedded in every email. Requires a CNAME you set up yourself.")}
        >
          <.toggle on={@campaign.tracking_opens?} field="opens" />
        </.setting_row>
        <.setting_row
          label={gettext("Click tracking")}
          hint={gettext("Wraps every link through a redirector on the same CNAME.")}
        >
          <.toggle on={@campaign.tracking_clicks?} field="clicks" />
        </.setting_row>
        <.cname_card :if={@tracking_on?} domain={Colt.AppSettings.tracking_domain()} />

        <.section_divider label={gettext("Approval")} />
        <.setting_row
          label={gettext("Auto-approve drafts")}
          hint={
            gettext(
              "New contacts skip the editor: a job picks an active variant (fair rotation), writes it, and schedules it. Turn it on once you're happy with a couple of variants."
            )
          }
        >
          <.auto_toggle on={@campaign.auto_approve_on?} />
        </.setting_row>

        <.section_divider label={gettext("Emergency")} />
        <.setting_row
          label={gettext("Pause all sending")}
          hint={
            gettext(
              "Halts every scheduled email immediately. The system also trips this on its own if bounces spike, to protect your domain. Turn off to resume."
            )
          }
        >
          <.panic_toggle on={@campaign.panic_switch_on} />
        </.setting_row>

        <div class="mt-10 flex flex-wrap items-center gap-4">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/sending-accounts"}
            class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] border border-ink20 rounded-sharp no-underline text-ink"
          >
            {gettext("Sending accounts")} <Liid.icon name="arrow" />
          </.link>
          <span :if={@saved_at} class="font-mono text-[11px] text-ink40">
            {gettext("saved %{at}", at: Calendar.strftime(@saved_at, "%H:%M:%S"))}
          </span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true

  defp section_divider(assigns) do
    ~H"""
    <div class="mt-10 mb-4 pb-2 border-b border-rule font-mono text-[10px] tracking-[0.14em] uppercase text-ink55">
      {@label}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp setting_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_auto] gap-6 py-3.5 border-b border-rule items-center">
      <div>
        <div class="text-[13px] text-ink font-medium mb-0.5">{@label}</div>
        <div :if={@hint} class="text-[12px] text-ink55 leading-[1.5]">{@hint}</div>
      </div>
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :on, :boolean, required: true
  attr :field, :string, required: true

  defp toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_tracking"
      phx-value-field={@field}
      class={[
        "relative inline-block w-[34px] h-[18px] rounded-full cursor-pointer transition-colors",
        if(@on, do: "", else: "bg-ink20")
      ]}
      style={@on && "background: var(--accent);"}
      aria-pressed={@on}
    >
      <span
        class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-paper transition-all"
        style={"left: #{if @on, do: 18, else: 2}px; box-shadow: 0 1px 2px rgba(0,0,0,0.2);"}
      />
    </button>
    """
  end

  attr :on, :boolean, required: true

  defp panic_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_panic"
      data-confirm={if not @on, do: gettext("Pause all sending for this campaign now?")}
      class="relative inline-block w-[34px] h-[18px] rounded-full cursor-pointer transition-colors"
      style={
        if @on,
          do: "background: var(--fail);",
          else: "background: color-mix(in oklch, var(--fail) 25%, transparent);"
      }
      aria-pressed={@on}
      title={
        if @on,
          do: gettext("Sending is paused. Click to resume."),
          else: gettext("Sending is on. Click to pause everything.")
      }
    >
      <span
        class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-paper transition-all"
        style={"left: #{if @on, do: 18, else: 2}px; box-shadow: 0 1px 2px rgba(0,0,0,0.2);"}
      />
    </button>
    """
  end

  attr :domain, :any, default: nil

  defp cname_card(assigns) do
    ~H"""
    <div class="mt-3.5 p-5 bg-paperAlt border border-rule rounded-[2px]">
      <div class="flex items-baseline justify-between mb-3.5">
        <div>
          <div class="text-[13px] text-ink font-medium">{gettext("Tracking CNAME")}</div>
          <div class="text-[12px] text-ink55 mt-0.5">
            {raw(
              gettext(
                "Required for opens/clicks. One CNAME at your DNS provider, reused across all sending accounts. Configure under <span class=\"font-mono text-ink70\">/admin/tracking-domain</span>."
              )
            )}
          </div>
        </div>
        <span class="font-mono text-[10px] tracking-[0.06em] uppercase text-ink40 px-2 py-0.5 border border-ink20 rounded-[2px]">
          {if @domain, do: gettext("set"), else: gettext("unset")}
        </span>
      </div>
    </div>
    """
  end

  attr :on, :boolean, required: true

  defp auto_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_auto_approve"
      data-confirm={
        if not @on,
          do:
            gettext(
              "Turn on auto-approve? New contacts will be written and sent without your review."
            )
      }
      class={[
        "relative inline-block w-[34px] h-[18px] rounded-full cursor-pointer transition-colors",
        if(@on, do: "", else: "bg-ink20")
      ]}
      style={@on && "background: var(--accent);"}
      aria-pressed={@on}
    >
      <span
        class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-paper transition-all"
        style={"left: #{if @on, do: 18, else: 2}px; box-shadow: 0 1px 2px rgba(0,0,0,0.2);"}
      />
    </button>
    """
  end
end
