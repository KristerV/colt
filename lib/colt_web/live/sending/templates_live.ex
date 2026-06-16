defmodule ColtWeb.Sending.TemplatesLive do
  @moduledoc """
  Admin-only template browser — left list of templates (the §6.2 outreach
  classifications), right pane showing the openers classified into the
  selected template. Mirrors the sending-funnel two-pane layout.

  A "template" is a distinct `template_label` among the campaign's labeled
  openers (step 0). Usage count is how many openers carry that label —
  one per contact the writer wrote it for.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, OutboundEmail}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        templates = load_templates(campaign.id, actor)

        socket =
          socket
          |> assign(
            page_title: gettext("Templates — %{name}", name: campaign.name),
            campaign: campaign,
            templates: templates,
            selected_label: templates |> List.first() |> then(&(&1 && &1.label))
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("select_template", %{"label" => label}, socket) do
    {:noreply, assign(socket, selected_label: label)}
  end

  # ── Data ─────────────────────────────────────────────────────────────

  defp load_templates(campaign_id, actor) do
    OutboundEmail.list_labeled_openers_for_campaign!(campaign_id,
      actor: actor,
      load: [thread: [campaign_contact: [person: :company]]]
    )
    # Openers arrive newest-first; group_by preserves that order, so the
    # representative angle/ask/offer comes from the most recent opener.
    |> Enum.group_by(& &1.template_label)
    |> Enum.map(fn {label, [example | _] = openers} ->
      %{
        label: label,
        angle: example.template_angle,
        ask: example.template_ask,
        offer: example.template_offer,
        count: length(openers),
        openers: openers
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp selected_template(templates, label) do
    Enum.find(templates, &(&1.label == label))
  end

  defp person(opener) do
    opener.thread && opener.thread.campaign_contact && opener.thread.campaign_contact.person
  end

  defp effective_subject(opener), do: opener.user_subject || opener.ai_subject || ""
  defp effective_body(opener), do: opener.user_body || opener.ai_body || ""

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    assigns =
      assign(assigns, :selected, selected_template(assigns.templates, assigns.selected_label))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:templates}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="flex flex-col h-[calc(100vh-120px)]">
        <div class="px-7 pt-6 pb-4">
          <Liid.headline kicker={gettext("Admin · Templates")}>
            {raw(gettext("Which <em class=\"text-accent\">approaches</em> the writer is betting on."))}
          </Liid.headline>
        </div>

        <div class="grid grid-cols-[360px_1fr] flex-1 min-h-0 border-t border-rule">
          <.template_list templates={@templates} selected_label={@selected_label} />
          <%= if @selected do %>
            <.template_pane template={@selected} />
          <% else %>
            <.empty_pane />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :templates, :list, required: true
  attr :selected_label, :any, required: true

  defp template_list(assigns) do
    ~H"""
    <div class="border-r border-rule overflow-y-auto bg-paper">
      <div class="px-4 py-3 border-b border-rule font-mono text-[10px] tracking-[0.04em] text-ink55 sticky top-0 bg-paper z-10">
        {gettext("%{n} templates", n: length(@templates))}
      </div>
      <%= if @templates == [] do %>
        <div class="px-4 py-6 text-[13px] text-ink55">
          {gettext("No templates yet — they appear once openers are approved and classified.")}
        </div>
      <% end %>
      <%= for t <- @templates do %>
        <% active? = @selected_label == t.label %>
        <button
          phx-click="select_template"
          phx-value-label={t.label}
          class={[
            "w-full text-left px-4 py-3 border-b border-rule relative cursor-pointer block",
            if(active?, do: "bg-paperAlt", else: "bg-paper hover:bg-paperAlt")
          ]}
        >
          <span
            :if={active?}
            class="absolute left-0 top-1 bottom-1 w-[2px]"
            style="background: var(--accent);"
          />
          <div class="flex items-baseline justify-between gap-3">
            <span class="font-mono text-[13px] text-ink truncate">{t.label}</span>
            <span
              class="font-mono text-[12px] tabular-nums text-ink shrink-0"
              title={gettext("times used")}
            >
              {t.count}×
            </span>
          </div>
          <div :if={t.angle} class="mt-1 text-[12px] text-ink55 line-clamp-2">
            {t.angle}
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  attr :template, :map, required: true

  defp template_pane(assigns) do
    ~H"""
    <div class="flex flex-col min-h-0 bg-paper">
      <div class="px-7 py-4 border-b border-rule">
        <div class="flex items-baseline justify-between gap-4">
          <span class="font-mono text-[15px] text-ink">{@template.label}</span>
          <span class="font-mono text-[11px] tracking-[0.04em] uppercase text-ink55">
            {gettext("used %{n}×", n: @template.count)}
          </span>
        </div>
        <dl class="mt-3 grid grid-cols-[64px_1fr] gap-x-4 gap-y-1.5 text-[13px]">
          <.axis label={gettext("Angle")} value={@template.angle} />
          <.axis label={gettext("Ask")} value={@template.ask} />
          <.axis label={gettext("Offer")} value={@template.offer} />
        </dl>
      </div>

      <div class="flex-1 overflow-y-auto px-7 py-6 flex flex-col gap-5">
        <.opener_card :for={o <- @template.openers} opener={o} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp axis(assigns) do
    ~H"""
    <dt class="font-mono text-[10px] tracking-[0.1em] uppercase text-ink40 pt-0.5">{@label}</dt>
    <dd class="text-ink70">{@value || "—"}</dd>
    """
  end

  attr :opener, :map, required: true

  defp opener_card(assigns) do
    assigns =
      assigns
      |> assign(:person, person(assigns.opener))
      |> assign(:subject, effective_subject(assigns.opener))
      |> assign(:body, effective_body(assigns.opener))

    ~H"""
    <div class="border border-rule rounded-[2px] bg-paperAlt">
      <div class="px-4 py-2.5 border-b border-rule flex items-baseline justify-between gap-3">
        <div class="min-w-0">
          <div class="text-[13px] text-ink truncate">{(@person && @person.name) || "—"}</div>
          <div class="text-[12px] text-ink55 truncate">
            {[@person && @person.title, @person && @person.company && @person.company.name]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(" · ")}
          </div>
        </div>
        <span
          :if={@opener.user_subject || @opener.user_body}
          class="font-mono text-[9px] tracking-[0.1em] uppercase text-ink40 shrink-0"
          title={gettext("the user edited this opener")}
        >
          {gettext("edited")}
        </span>
      </div>
      <div class="px-4 py-3">
        <div class="text-[13px] text-ink font-medium">{@subject}</div>
        <div class="mt-2 text-[13px] text-ink70 whitespace-pre-wrap">{@body}</div>
      </div>
    </div>
    """
  end

  defp empty_pane(assigns) do
    ~H"""
    <div class="flex items-center justify-center bg-paper text-[13px] text-ink55">
      {gettext("Select a template to see the openers written with it.")}
    </div>
    """
  end
end
