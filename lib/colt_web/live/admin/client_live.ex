defmodule ColtWeb.Admin.ClientLive do
  @moduledoc """
  One client, end to end: is the money working, are they using the product,
  and where exactly do they get stuck. Built as call prep — the top panel is
  the sentences you'd open with.
  """
  use ColtWeb, :live_view

  alias Colt.Accounts
  alias Colt.Resources.{Company, Person, RevenueEntry}
  alias Colt.Services.Admin.{ClientHealth, ClientIdentityMatch, ClientProfile}
  alias Colt.Services.Billing.RevenueSync
  alias ColtWeb.Components.{AdminFormat, Liid, MoneyChart}

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:user_id, id)
     |> assign(:modal, nil)
     |> assign(:search, nil)
     |> assign(:results, %{companies: [], persons: []})
     |> assign(:revenue_form, new_revenue_form())
     |> auto_link()
     |> load()}
  end

  # --- events ---------------------------------------------------------------

  def handle_event("refresh", _params, socket) do
    ClientProfile.refresh(socket.assigns.user_id)
    {:noreply, socket |> put_flash(:info, "Recomputed") |> load()}
  end

  def handle_event("sync_stripe", _params, socket) do
    case RevenueSync.run() do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Stripe revenue synced") |> reload()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Sync failed: #{inspect(reason)}")}
    end
  end

  def handle_event("open_identity", _params, socket),
    do: {:noreply, assign(socket, :modal, :identity)}

  def handle_event("open_revenue", %{"month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:modal, {:revenue, month})
     |> assign(:revenue_form, new_revenue_form(month))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, socket |> assign(:modal, nil) |> close_search()}
  end

  def handle_event("save_profile", %{"profile" => params}, socket) do
    attrs = Map.new(params, fn {k, v} -> {k, blank_to_nil(v)} end)

    case Accounts.admin_set_profile(socket.assigns.profile.user, attrs, authorize?: false) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Saved") |> assign(:modal, nil) |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save — check the values")}
    end
  end

  def handle_event("open_search", _params, socket), do: {:noreply, assign(socket, :search, "")}

  def handle_event("close_search", _params, socket), do: {:noreply, close_search(socket)}

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search, q) |> assign(:results, lookup(q))}
  end

  def handle_event("link", params, socket) do
    attrs = %{
      person_id: params["person_id"],
      company_id: params["company_id"] || person_company_id(params["person_id"])
    }

    link(socket, attrs, "Linked")
  end

  def handle_event("unlink", _params, socket) do
    link(socket, %{person_id: nil, company_id: nil}, "Unlinked")
  end

  def handle_event("add_revenue", %{"revenue" => params}, socket) do
    attrs = %{
      user_id: socket.assigns.user_id,
      month: params["month"],
      amount_usd: params["amount_usd"],
      source: params["source"],
      note: blank_to_nil(params["note"])
    }

    case RevenueEntry.record_manual(attrs, authorize?: false) do
      {:ok, _} ->
        # Stay open on the same month — recording two lines for one month
        # (a subscription plus a one-off invoice) is the common case.
        {:noreply,
         socket
         |> put_flash(:info, "Revenue recorded")
         |> assign(:revenue_form, new_revenue_form(params["month"]))
         |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record revenue — check the values")}
    end
  end

  def handle_event("delete_revenue", %{"id" => id}, socket) do
    with {:ok, entry} <- RevenueEntry.get_by_id(id, authorize?: false),
         :ok <- RevenueEntry.delete(entry, authorize?: false) do
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete that entry")}
    end
  end

  # --- data -----------------------------------------------------------------

  defp load(socket) do
    {:ok, profile} = ClientProfile.run(socket.assigns.user_id)
    {:ok, health} = ClientHealth.run(profile)

    socket
    |> assign(:profile, profile)
    |> assign(:health, health)
    |> assign(:page_title, "Admin · " <> to_string(profile.user.email))
    |> assign(:chart, MoneyChart.build(profile.months))
  end

  # Anything that changes stored data has to bust the 24h cache before reloading.
  defp reload(socket) do
    ClientProfile.refresh(socket.assigns.user_id)
    load(socket)
  end

  # If we've never linked this client, try to recognise them from our own
  # enrichment data by their sign-up address. Only ever writes when there's no
  # link yet, so a deliberate unlink stays unlinked.
  defp auto_link(socket) do
    with {:ok, user} <- Accounts.get_user(socket.assigns.user_id, authorize?: false),
         true <- is_nil(user.person_id) and is_nil(user.company_id),
         {:ok, %{person: person, company: company}} <- ClientIdentityMatch.run(user),
         {:ok, _} <-
           Accounts.admin_link_identity(
             user,
             %{person_id: person.id, company_id: company && company.id},
             authorize?: false
           ) do
      ClientProfile.refresh(socket.assigns.user_id)
    end

    socket
  end

  defp link(socket, attrs, message) do
    case Accounts.admin_link_identity(socket.assigns.profile.user, attrs, authorize?: false) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, message) |> close_search() |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not link that record")}
    end
  end

  defp close_search(socket) do
    socket |> assign(:search, nil) |> assign(:results, %{companies: [], persons: []})
  end

  defp lookup(q) when byte_size(q) < 2, do: %{companies: [], persons: []}

  defp lookup(q) do
    %{
      companies: Company.search!(q, authorize?: false),
      persons: Person.search!(q, authorize?: false)
    }
  end

  defp person_company_id(nil), do: nil

  defp person_company_id(person_id) do
    case Person.get(person_id, authorize?: false) do
      {:ok, %{company_id: company_id}} -> company_id
      _ -> nil
    end
  end

  # --- render ---------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-4">
        <.client_header profile={@profile} />
        <.talking_points health={@health} />
        <.funnel profile={@profile} />
        <MoneyChart.money_chart chart={@chart} label="revenue vs cost · last 12 months" />
        <.month_table months={@profile.months} />
        <.campaigns campaigns={@profile.campaigns} />
        <.identity identity={@profile.identity} />
      </div>

      <.identity_modal
        :if={@modal == :identity}
        identity={@profile.identity}
        search={@search}
        results={@results}
      />
      <.revenue_modal
        :if={match?({:revenue, _}, @modal)}
        entries={@profile.entries}
        form={@revenue_form}
      />
    </Layouts.app>
    """
  end

  # --- header ---------------------------------------------------------------

  attr :profile, :map, required: true

  defp client_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div class="min-w-0">
        <.link
          navigate={~p"/admin/clients"}
          class="text-[11px] text-ink55 hover:text-accent no-underline"
        >
          ← all clients
        </.link>
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink mt-1 truncate">
          {@profile.user.email}
          <span :if={@profile.user.is_admin} class="text-[13px] font-normal text-ink40">· admin</span>
        </h1>
      </div>

      <div class="flex items-center gap-4">
        <button
          type="button"
          class="text-[12px] font-medium text-accent hover:underline cursor-pointer flex items-center gap-1.5"
          phx-click="sync_stripe"
        >
          <Liid.icon name="refresh" size={13} /> Sync Stripe
        </button>
        <button
          type="button"
          class="text-[12px] font-medium text-accent hover:underline cursor-pointer flex items-center gap-1.5"
          phx-click="refresh"
        >
          <Liid.icon name="refresh" size={13} /> Refresh
        </button>
      </div>
    </div>
    """
  end

  # The facts you'd read out on the phone. Given real weight — these used to be
  # a faint grey run-on line and were the first thing to get lost.
  attr :tone, :atom, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-baseline gap-1.5 rounded-[8px] border px-2.5 py-1.5 text-[13px] font-semibold tabular-nums",
      chip_class(@tone)
    ]}>
      <span class="text-[9.5px] uppercase tracking-[0.08em] font-semibold opacity-60">
        {@label}
      </span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp chip_class(:good), do: "bg-green-soft border-green/30 text-green"
  defp chip_class(:warn), do: "bg-amber-soft border-amber/30 text-amber"
  defp chip_class(:bad), do: "bg-red-soft border-red/30 text-red"
  defp chip_class(:accent), do: "bg-accent-soft border-accent-ring text-accent"
  defp chip_class(:neutral), do: "bg-card border-border text-ink"

  defp status_tone(:active), do: :good
  defp status_tone(:past_due), do: :bad
  defp status_tone(:canceled), do: :warn
  defp status_tone(_), do: :neutral

  defp plan_tone(capacity) when is_integer(capacity) and capacity > 0, do: :accent
  defp plan_tone(_), do: :neutral

  defp plan_text(capacity) do
    case {Colt.Billing.plan_label(capacity), Colt.Billing.monthly_eur(capacity)} do
      {nil, _} -> "none"
      {name, 0} -> name
      {name, eur} -> "#{name} · €#{eur}/mo"
    end
  end

  # --- talking points -------------------------------------------------------

  attr :health, :list, required: true

  defp talking_points(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] p-5"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-3">
        what to talk about
      </div>
      <ul class="space-y-2 m-0 p-0 list-none">
        <li :for={s <- @health} class="flex items-start gap-2.5 text-[13.5px] text-ink">
          <span class={["w-2 h-2 rounded-full mt-[6px] shrink-0", dot_class(s.tone)]}></span>
          <span>{s.text}</span>
        </li>
        <li :if={@health == []} class="text-[13px] text-ink40">
          nothing stands out — no campaigns, no spend, no signal yet
        </li>
      </ul>
    </div>
    """
  end

  defp dot_class(:bad), do: "bg-red"
  defp dot_class(:warn), do: "bg-amber"
  defp dot_class(:good), do: "bg-green"

  # --- funnel ---------------------------------------------------------------

  attr :profile, :map, required: true

  defp funnel(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] p-5 md:p-6"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-4">
        where they get stuck · all campaigns
      </div>

      <div class="flex items-center gap-2 flex-wrap mb-5">
        <.chip tone={status_tone(@profile.user.subscription_status)} label="status">
          {@profile.user.subscription_status}
        </.chip>
        <.chip tone={plan_tone(@profile.user.monthly_contact_capacity)} label="plan">
          {plan_text(@profile.user.monthly_contact_capacity)}
        </.chip>
        <.chip tone={:neutral} label="registered">
          {AdminFormat.date(@profile.user.inserted_at)} · {@profile.activity.registered_days_ago}d
        </.chip>
        <.chip :if={@profile.usage.period_end} tone={:neutral} label="renews">
          {AdminFormat.date(@profile.usage.period_end)}
        </.chip>
        <.chip
          tone={if @profile.activity.email_accounts_ok > 0, do: :good, else: :bad}
          label="inboxes"
        >
          {@profile.activity.email_accounts_ok} of {@profile.activity.email_accounts} working
        </.chip>
      </div>

      <div class="flex items-stretch gap-1.5 overflow-x-auto">
        <.funnel_step
          :for={step <- @profile.funnel.steps}
          step={step}
          worst={@profile.funnel.worst}
        />
      </div>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :worst, :atom, default: nil

  defp funnel_step(assigns) do
    ~H"""
    <div class={[
      "flex-1 min-w-[104px] rounded-[8px] border px-3 py-2.5",
      if(@step.key == @worst,
        do: "border-amber bg-amber-soft",
        else: "border-border bg-bg-soft"
      )
    ]}>
      <div class="text-[19px] font-bold tabular-nums tracking-[-0.02em] text-ink leading-none">
        {AdminFormat.int(@step.count)}
      </div>
      <div class="text-[10.5px] text-ink55 mt-1.5">{@step.label}</div>
      <div class={[
        "text-[10.5px] tabular-nums mt-0.5 font-semibold",
        if(@step.key == @worst, do: "text-amber", else: "text-ink40")
      ]}>
        {drop_text(@step.drop)}
      </div>
    </div>
    """
  end

  # The share lost coming into this step. Non-breaking space keeps the first
  # block (which has no predecessor) the same height as the rest.
  defp drop_text(drop) when is_integer(drop) and drop > 0, do: "−#{drop}%"
  defp drop_text(drop) when is_integer(drop), do: "no drop"
  defp drop_text(_), do: " "

  # --- months ---------------------------------------------------------------

  attr :months, :list, required: true

  defp month_table(assigns) do
    ~H"""
    <div
      class="border border-border rounded-[11px] bg-card overflow-x-auto"
      style="box-shadow:var(--shadow-card)"
    >
      <div class="px-3 py-2.5 border-b border-border text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
        month by month
      </div>
      <table class="text-[12px] w-full min-w-[560px]">
        <thead>
          <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
            <th class="text-left px-3 py-2">month</th>
            <th class="text-right px-3 py-2">screened</th>
            <th class="text-right px-3 py-2">enriched</th>
            <th class="text-right px-3 py-2">emailed</th>
            <th class="text-right px-3 py-2">interested</th>
            <th class="text-right px-3 py-2">profit</th>
            <th class="w-8"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={m <- Enum.reverse(@months)}
            class="border-b border-border last:border-b-0 hover:bg-paperAlt group"
          >
            <td class="px-3 py-1.5 tabular-nums text-ink">{m.month}</td>
            <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
              {AdminFormat.int(m.screened)}
            </td>
            <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
              {AdminFormat.int(m.enriched)}
            </td>
            <td class="px-3 py-1.5 text-right tabular-nums text-ink70">
              {AdminFormat.int(m.emailed)}
            </td>
            <td class={[
              "px-3 py-1.5 text-right tabular-nums font-semibold",
              if(m.interested > 0, do: "text-green", else: "text-ink40")
            ]}>
              {m.interested}
            </td>
            <td class={[
              "px-3 py-1.5 text-right tabular-nums font-medium",
              AdminFormat.profit_class(m.profit)
            ]}>
              {AdminFormat.signed(m.profit)}
            </td>
            <td class="px-2 py-1.5 text-right">
              <button
                type="button"
                title={"record revenue for #{m.month}"}
                class="text-ink40 hover:text-accent cursor-pointer opacity-0 group-hover:opacity-100 focus:opacity-100"
                phx-click="open_revenue"
                phx-value-month={m.month}
              >
                +$
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # --- campaigns ------------------------------------------------------------

  attr :campaigns, :list, required: true

  defp campaigns(assigns) do
    ~H"""
    <div>
      <div class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55 mb-2">
        campaigns · counts are contacts, not messages · click through to the funnel
      </div>
      <div
        class="border border-border rounded-[11px] bg-card overflow-x-auto"
        style="box-shadow:var(--shadow-card)"
      >
        <table class="text-[12px] w-full min-w-[720px]">
          <thead>
            <tr class="border-b border-border bg-paperAlt text-[10px] font-semibold uppercase tracking-[0.06em] text-ink55">
              <th class="text-left px-3 py-2">name</th>
              <th class="text-left px-3 py-2">created</th>
              <th class="text-right px-3 py-2">companies</th>
              <th class="text-right px-3 py-2">enriched</th>
              <th class="text-right px-3 py-2">emailed</th>
              <th class="text-right px-3 py-2">replied</th>
              <th class="text-right px-3 py-2">interested</th>
              <th class="text-right px-3 py-2">cost</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={c <- @campaigns}
              class="border-b border-border last:border-b-0 hover:bg-paperAlt cursor-pointer"
              phx-click={JS.navigate(~p"/campaigns/#{c.id}/funnel")}
            >
              <td class="px-3 py-2 text-ink font-medium truncate max-w-[16rem]">{c.name}</td>
              <td class="px-3 py-2 tabular-nums text-ink55">{AdminFormat.date(c.inserted_at)}</td>
              <td class="px-3 py-2 text-right tabular-nums text-ink70">
                {AdminFormat.int(c.total_count)}
              </td>
              <td class="px-3 py-2 text-right tabular-nums text-ink70">{c.done_count}</td>
              <td class="px-3 py-2 text-right tabular-nums text-ink70">{c.sent_contacts_count}</td>
              <td class="px-3 py-2 text-right tabular-nums text-ink70">
                {c.replied_contacts_count}
              </td>
              <td class={[
                "px-3 py-2 text-right tabular-nums font-semibold",
                if(c.interested_contacts_count > 0, do: "text-green", else: "text-ink40")
              ]}>
                {c.interested_contacts_count}
              </td>
              <td class="px-3 py-2 text-right tabular-nums text-ink70">
                {AdminFormat.money(c.cost_usd || 0)}
              </td>
            </tr>
            <tr :if={@campaigns == []}>
              <td colspan="8" class="px-3 py-8 text-center text-ink40">
                no campaigns — they've never started
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # --- identity -------------------------------------------------------------

  attr :identity, :map, required: true

  # A card, not a form. Everything editable lives behind the click.
  defp identity(assigns) do
    ~H"""
    <button
      type="button"
      class="w-full text-left bg-card border border-border rounded-[11px] p-5 md:p-6 cursor-pointer hover:border-border-strong"
      style="box-shadow:var(--shadow-card)"
      phx-click="open_identity"
    >
      <div class="flex items-center justify-between gap-3 mb-3">
        <span class="text-[10.5px] uppercase tracking-[0.08em] font-semibold text-ink55">
          company &amp; contact
        </span>
        <span class="text-[11px] text-accent">edit</span>
      </div>

      <div :if={@identity.company_name || @identity.full_name} class="space-y-2">
        <div class="text-[17px] font-bold text-ink">{@identity.company_name || "—"}</div>

        <div class="text-[12px] text-ink55 tabular-nums">
          {join_facts([@identity.company_reg_code, @identity.country, @identity.website])}
        </div>

        <div :if={@identity.company} class="text-[12px] text-ink55 tabular-nums">
          {join_facts([
            @identity.company.industry_code && "NACE #{@identity.company.industry_code}",
            @identity.company.revenue_latest &&
              "rev #{AdminFormat.int(@identity.company.revenue_latest)}",
            @identity.company.employees_latest &&
              "#{@identity.company.employees_latest} employees"
          ])}
        </div>

        <div class="text-[13.5px] text-ink font-medium">
          {join_facts([@identity.full_name, @identity.title, @identity.phone])}
        </div>

        <p
          :if={@identity.company && @identity.company.ai_summary}
          class="text-[13px] text-ink70 leading-[1.5] m-0 max-w-[65ch]"
        >
          {@identity.company.ai_summary}
        </p>

        <div
          :if={@identity.notes}
          class="text-[13px] text-ink border border-amber/30 bg-amber-soft rounded-[8px] px-3 py-2 whitespace-pre-wrap"
        >
          {@identity.notes}
        </div>

        <div :if={@identity.auto_matched?} class="text-[10.5px] text-ink40">
          auto-matched — their sign-up address is a contact we enriched
        </div>
      </div>

      <div
        :if={is_nil(@identity.company_name) and is_nil(@identity.full_name)}
        class="text-[13px] text-ink40"
      >
        nothing on file — click to search our data or fill it in
      </div>
    </button>
    """
  end

  defp join_facts(values), do: values |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  attr :identity, :map, required: true
  attr :search, :string, default: nil
  attr :results, :map, required: true

  defp identity_modal(assigns) do
    ~H"""
    <.modal title="Company & contact">
      <div class="flex items-center gap-3 text-[11px] mb-4">
        <button
          type="button"
          class="text-accent hover:underline cursor-pointer"
          phx-click={if @search, do: "close_search", else: "open_search"}
        >
          {if @search, do: "cancel search", else: "search our data…"}
        </button>
        <button
          :if={@identity.person || @identity.company}
          type="button"
          class="text-ink55 hover:text-red cursor-pointer"
          phx-click="unlink"
        >
          unlink
        </button>
      </div>

      <div :if={@search} class="mb-4">
        <form phx-change="search" phx-submit="search">
          <input
            name="q"
            value={@search}
            autocomplete="off"
            placeholder="company name, registry code, contact name or email…"
            class="w-full border border-border rounded-[8px] px-3 py-2 text-[13px] bg-card"
          />
        </form>

        <div class="mt-2 space-y-1 max-h-56 overflow-y-auto">
          <button
            :for={c <- @results.companies}
            type="button"
            class="w-full text-left border border-border rounded-[8px] px-3 py-2 text-[12px] hover:bg-paperAlt cursor-pointer"
            phx-click="link"
            phx-value-company_id={c.id}
          >
            <span class="text-ink font-medium">{c.name}</span>
            <span class="text-ink55 tabular-nums"> ·            {c.registry_code} · {c.market}</span>
          </button>
          <button
            :for={p <- @results.persons}
            type="button"
            class="w-full text-left border border-border rounded-[8px] px-3 py-2 text-[12px] hover:bg-paperAlt cursor-pointer"
            phx-click="link"
            phx-value-person_id={p.id}
          >
            <span class="text-ink font-medium">{p.name}</span>
            <span class="text-ink55"> ·            {p.email}</span>
            <span :if={p.company} class="text-ink40"> ·            {p.company.name}</span>
          </button>
          <div
            :if={@results.companies == [] and @results.persons == []}
            class="text-[12px] text-ink40 px-1 py-2"
          >
            nothing found — fill the fields in by hand below
          </div>
        </div>
      </div>

      <form phx-submit="save_profile">
        <div class="text-[10px] uppercase tracking-[0.08em] font-semibold text-ink40 mb-2">
          override · blank falls back to the linked record
        </div>
        <div class="grid grid-cols-2 gap-2">
          <.field name="full_name" label="name" identity={@identity} />
          <.field name="phone" label="phone" identity={@identity} />
          <.field name="company_name" label="company" identity={@identity} />
          <.field name="company_reg_code" label="reg code" identity={@identity} />
          <.field name="country" label="country" identity={@identity} />
          <.field name="website" label="website" identity={@identity} />
        </div>
        <textarea
          name="profile[admin_notes]"
          rows="3"
          placeholder="notes — what they want, what they're blocked on, what you promised"
          class="w-full mt-2 border border-border rounded-[8px] px-3 py-2 text-[13px] bg-card"
        >{@identity.notes}</textarea>
        <button
          type="submit"
          class="mt-2 bg-accent text-white rounded-[8px] px-3 py-1.5 text-[13px] font-medium cursor-pointer hover:opacity-90"
        >
          Save
        </button>
      </form>
    </.modal>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :identity, :map, required: true

  # Value = the admin's override only; the linked record shows as placeholder,
  # so saving an untouched form never freezes a linked value into an override.
  defp field(assigns) do
    key = String.to_existing_atom(assigns.name)

    assigns =
      assign(assigns,
        value: assigns.identity.override[key],
        placeholder: assigns.identity.linked[key] || "—"
      )

    ~H"""
    <label class="block">
      <span class="text-[10px] text-ink55">{@label}</span>
      <input
        name={"profile[#{@name}]"}
        value={@value}
        placeholder={@placeholder}
        class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] bg-card"
      />
    </label>
    """
  end

  # --- modal shell ----------------------------------------------------------

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        class="bg-card border border-border rounded-[11px] w-full max-w-[680px] my-auto px-6 py-7 md:px-8"
        style="box-shadow: 0 24px 80px rgba(35,32,28,0.18);"
        phx-click-away="close_modal"
        phx-window-keydown="close_modal"
        phx-key="escape"
      >
        <div class="flex justify-between items-start gap-3 mb-5">
          <h2 class="font-semibold text-[20px] leading-[1.15] tracking-[-0.02em] text-ink m-0">
            {@title}
          </h2>
          <button
            type="button"
            class="w-6 h-6 flex items-center justify-center cursor-pointer"
            phx-click="close_modal"
          >
            <Liid.icon name="x" size={14} />
          </button>
        </div>

        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # --- revenue --------------------------------------------------------------

  attr :entries, :list, required: true
  attr :form, :any, required: true

  defp revenue_modal(assigns) do
    ~H"""
    <.modal title="Revenue">
      <div class="space-y-1 mb-4">
        <div
          :for={e <- @entries}
          class="flex items-center gap-2 border border-border rounded-[8px] px-3 py-1.5 text-[12px]"
        >
          <span class="tabular-nums text-ink">{e.month}</span>
          <span class="text-[10px] uppercase tracking-[0.05em] text-ink55 bg-paperAlt rounded px-1.5 py-0.5">
            {e.source}
          </span>
          <span :if={e.note} class="text-ink55 truncate">{e.note}</span>
          <span class="ml-auto tabular-nums font-medium text-ink">
            {AdminFormat.money(e.amount_usd)}
          </span>
          <button
            :if={e.source != :subscription}
            type="button"
            class="text-ink40 hover:text-red cursor-pointer"
            phx-click="delete_revenue"
            phx-value-id={e.id}
          >
            <Liid.icon name="x" size={12} />
          </button>
        </div>
        <div :if={@entries == []} class="text-ink40 text-[12px]">no revenue recorded yet</div>
      </div>

      <.form for={@form} phx-submit="add_revenue">
        <div class="text-[10px] uppercase tracking-[0.08em] font-semibold text-ink40 mb-2">
          add revenue (invoice / manual)
        </div>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-2 items-end">
          <label class="block">
            <span class="text-[10px] text-ink55">month</span>
            <input
              name="revenue[month]"
              value={@form[:month].value}
              placeholder="YYYY-MM"
              class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] tabular-nums bg-card"
            />
          </label>
          <label class="block">
            <span class="text-[10px] text-ink55">amount $</span>
            <input
              name="revenue[amount_usd]"
              value={@form[:amount_usd].value}
              inputmode="decimal"
              class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] tabular-nums bg-card"
            />
          </label>
          <label class="block">
            <span class="text-[10px] text-ink55">source</span>
            <select
              name="revenue[source]"
              class="w-full mt-0.5 border border-border rounded-[8px] px-2 py-1.5 text-[13px] bg-card"
            >
              <option value="invoice">invoice</option>
              <option value="manual">manual</option>
            </select>
          </label>
          <button
            type="submit"
            class="bg-accent text-white rounded-[8px] px-3 py-1.5 text-[13px] font-medium cursor-pointer hover:opacity-90"
          >
            Record
          </button>
        </div>
        <input
          name="revenue[note]"
          value={@form[:note].value}
          placeholder="note (optional)"
          class="w-full mt-2 border border-border rounded-[8px] px-2 py-1.5 text-[13px] bg-card"
        />
      </.form>
    </.modal>
    """
  end

  # --- helpers --------------------------------------------------------------

  defp new_revenue_form(month \\ nil) do
    to_form(
      %{
        "month" => month || current_ym(),
        "amount_usd" => "",
        "source" => "invoice",
        "note" => ""
      },
      as: :revenue
    )
  end

  defp current_ym do
    %{year: y, month: m} = DateTime.utc_now()
    "#{y}-#{m |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp blank_to_nil(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
  defp blank_to_nil(_), do: nil
end
