defmodule ColtWeb.Sending.SendingAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, CampaignEmailAccount, EmailAccount, Sequence, SequenceStep}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}
  on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  @work_days_per_month 22

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Sending accounts — %{name}", name: campaign.name),
           campaign: campaign,
           picker_selection: nil
         )
         |> load_data()}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_params(_params, _uri, socket) do
    socket =
      if socket.assigns.live_action == :picker do
        enrolled_ids =
          socket.assigns.enrollments
          |> Enum.map(& &1.email_account_id)
          |> MapSet.new()

        assign(socket, picker_selection: enrolled_ids)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, enrollment} <- CampaignEmailAccount.get(id, actor: actor),
         :ok <- CampaignEmailAccount.remove(enrollment, actor: actor) do
      {:noreply, load_data(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_pick", %{"id" => id}, socket) do
    sel = socket.assigns.picker_selection || MapSet.new()

    sel =
      if MapSet.member?(sel, id),
        do: MapSet.delete(sel, id),
        else: MapSet.put(sel, id)

    {:noreply, assign(socket, picker_selection: sel)}
  end

  def handle_event("save_picker", _params, socket) do
    actor = socket.assigns.current_user
    selected = socket.assigns.picker_selection || MapSet.new()

    current_ids =
      socket.assigns.enrollments
      |> Enum.map(& &1.email_account_id)
      |> MapSet.new()

    to_remove = MapSet.difference(current_ids, selected)
    to_add = MapSet.difference(selected, current_ids)

    Enum.each(socket.assigns.enrollments, fn enrollment ->
      if MapSet.member?(to_remove, enrollment.email_account_id) do
        CampaignEmailAccount.remove(enrollment, actor: actor)
      end
    end)

    Enum.each(to_add, fn email_account_id ->
      CampaignEmailAccount.enroll(socket.assigns.campaign.id, email_account_id, actor: actor)
    end)

    {:noreply,
     push_navigate(socket, to: ~p"/campaigns/#{socket.assigns.campaign.id}/sending-accounts")}
  end

  defp load_data(socket) do
    actor = socket.assigns.current_user

    accounts = EmailAccount.list_for_user!(actor.id, actor: actor)

    enrollments =
      CampaignEmailAccount.list_for_campaign!(socket.assigns.campaign.id, actor: actor)

    sequence_summary = compute_sequence_summary(socket.assigns.campaign.id, actor)

    assign(socket,
      accounts: accounts,
      enrollments: enrollments,
      accounts_by_id: Map.new(accounts, fn a -> {a.id, a} end),
      sequence_summary: sequence_summary
    )
  end

  defp compute_sequence_summary(campaign_id, actor) do
    with {:ok, %_{} = sequence} <- Sequence.get_for_campaign(campaign_id, actor: actor),
         {:ok, steps} <- SequenceStep.list_for_sequence(sequence.id, authorize?: false) do
      email_count = Enum.count(steps, &(&1.kind == :email))
      total_days = steps |> Enum.drop(1) |> Enum.map(& &1.delay_days) |> Enum.sum()
      %{steps: email_count, total_days: total_days}
    else
      _ -> %{steps: 0, total_days: 0}
    end
  end

  defp enrolled_accounts(enrollments, accounts_by_id) do
    Enum.map(enrollments, fn enrollment ->
      account = Map.get(accounts_by_id, enrollment.email_account_id)
      {enrollment, account}
    end)
    |> Enum.reject(fn {_, account} -> is_nil(account) end)
  end

  defp capacity(enrolled_pairs) do
    active =
      Enum.filter(enrolled_pairs, fn {enrollment, account} ->
        not enrollment.paused? and account.status == :healthy
      end)

    daily = active |> Enum.map(fn {_, a} -> a.daily_quota end) |> Enum.sum()
    %{active_count: length(active), daily: daily, monthly: daily * @work_days_per_month}
  end

  def render(assigns) do
    case assigns.live_action do
      :picker -> picker(assigns)
      _ -> default_view(assigns)
    end
  end

  # ── default view ────────────────────────────────────────────────────────
  defp default_view(assigns) do
    enrolled_pairs = enrolled_accounts(assigns.enrollments, assigns.accounts_by_id)
    cap = capacity(enrolled_pairs)
    steps = assigns.sequence_summary.steps
    cycle_days = assigns.sequence_summary.total_days

    throughput =
      if steps > 0, do: max(1, div(cap.daily, max(steps, 1))), else: 0

    assigns =
      assign(assigns,
        enrolled_pairs: enrolled_pairs,
        cap: cap,
        cycle_days: cycle_days,
        throughput: throughput
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sending_accounts}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[900px] mx-auto pb-16">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline kicker={gettext("Sending · Accounts")}>
            {raw(gettext("Which inboxes this campaign <em>sends through</em>."))}
          </Liid.headline>

          <.link
            navigate={~p"/campaigns/#{@campaign.id}/sending-accounts/add"}
            class="no-underline"
          >
            <Liid.btn variant={:primary} size={:small}>
              <Liid.icon name="plus" size={11} /> {gettext("Add accounts")}
            </Liid.btn>
          </.link>
        </div>

        <div
          class="bg-card border border-border rounded-[11px] overflow-hidden"
          style="box-shadow:var(--shadow-card)"
        >
          <div class="hidden md:grid grid-cols-[1fr_120px_140px_160px] bg-bgSoft border-b border-border text-[10px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
            <div class="px-[18px] py-3">{gettext("Account")}</div>
            <div class="px-[14px] py-3 text-right">{gettext("Quota")}</div>
            <div class="px-[14px] py-3">{gettext("Status")}</div>
            <div class="px-[14px] py-3 text-right"></div>
          </div>

          <%= if @enrolled_pairs == [] do %>
            <.empty_row campaign_id={@campaign.id} />
          <% else %>
            <%= for {{enrollment, account}, idx} <- Enum.with_index(@enrolled_pairs) do %>
              <.enrolled_row
                enrollment={enrollment}
                account={account}
                last={idx == length(@enrolled_pairs) - 1}
              />
            <% end %>
          <% end %>
        </div>

        <div class="mt-5 grid grid-cols-3 gap-3">
          <.capacity_tile
            label={gettext("Daily capacity")}
            big={"~#{@cap.daily}"}
            sub={gettext("emails / day")}
            accent
          />
          <.capacity_tile
            label={gettext("Monthly")}
            big={"~#{:erlang.float_to_binary(@cap.monthly / 1000, decimals: 1)}k"}
            sub={gettext("emails / month")}
          />
          <.capacity_tile
            label={gettext("Throughput")}
            big={"#{@throughput}"}
            sub={gettext("contacts / day · %{days}d each", days: @cycle_days)}
          />
        </div>

        <div class="mt-8 flex flex-wrap items-center gap-3">
          <.link navigate={~p"/campaigns/#{@campaign.id}/pitch"} class="no-underline">
            <Liid.btn size={:small}>
              <Liid.icon name="chev-l" size={11} /> {gettext("Back")}
            </Liid.btn>
          </.link>
          <.link navigate={~p"/campaigns/#{@campaign.id}/write"} class="no-underline">
            <Liid.btn variant={:primary}>
              {gettext("Continue → sequence")} <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── picker view ─────────────────────────────────────────────────────────
  defp picker(assigns) do
    selection = assigns.picker_selection || MapSet.new()
    accounts = assigns.accounts

    assigns =
      assign(assigns,
        selection: selection,
        selected_count: MapSet.size(selection),
        total_count: length(accounts)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sending_accounts}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[900px] mx-auto pb-16">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline
            kicker={gettext("Sending · Accounts · Add")}
            sub={
              gettext(
                "Each inbox respects its global daily quota. Disconnected accounts are unselectable."
              )
            }
          >
            {raw(gettext("Pick inboxes for this <em>campaign</em>."))}
          </Liid.headline>

          <div class="flex items-center gap-3">
            <.link
              navigate={~p"/campaigns/#{@campaign.id}/sending-accounts"}
              class="no-underline"
            >
              <Liid.btn size={:small}>{gettext("Cancel")}</Liid.btn>
            </.link>
            <Liid.btn
              variant={:primary}
              size={:small}
              phx-click="save_picker"
            >
              <Liid.icon name="check" size={11} /> {gettext("Save selection")}
            </Liid.btn>
          </div>
        </div>

        <div class="mb-3 text-[11.5px] text-inkSoft tabular-nums">
          <span class="text-ink font-semibold">{@selected_count}</span>
          {gettext("selected · %{total} available", total: @total_count)}
        </div>

        <div
          class="bg-card border border-border rounded-[11px] overflow-hidden"
          style="box-shadow:var(--shadow-card)"
        >
          <div class="hidden md:grid grid-cols-[36px_1fr_100px_140px] bg-bgSoft border-b border-border text-[10px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
            <div class="py-3"></div>
            <div class="px-[14px] py-3">{gettext("Account")}</div>
            <div class="px-[14px] py-3 text-right">{gettext("Quota")}</div>
            <div class="px-[14px] py-3">{gettext("Status")}</div>
          </div>

          <%= if @accounts == [] do %>
            <div class="p-9 text-center">
              <div class="text-[22px] font-semibold text-ink tracking-[-0.01em] mb-1.5">
                {gettext("No inboxes connected yet.")}
              </div>
              <div class="text-[12px] text-inkSoft mb-3.5">
                {gettext("Connect at least one in Email accounts to enroll it here.")}
              </div>
              <.link navigate={~p"/email-accounts"} class="no-underline">
                <Liid.btn size={:small}>
                  <Liid.icon name="arrow" size={11} /> {gettext("Email accounts")}
                </Liid.btn>
              </.link>
            </div>
          <% else %>
            <%= for {account, idx} <- Enum.with_index(@accounts) do %>
              <.picker_row
                account={account}
                selected={MapSet.member?(@selection, account.id)}
                last={idx == length(@accounts) - 1}
              />
            <% end %>
          <% end %>
        </div>

        <div
          class="mt-4 px-4 py-3 bg-card border border-border rounded-[11px] flex items-center gap-2.5 text-[11.5px] text-inkSoft"
          style="box-shadow:var(--shadow)"
        >
          <Liid.icon name="spark" size={11} />
          <span>
            {gettext("Don't see the inbox you want?")}
            <.link
              navigate={~p"/email-accounts"}
              class="text-accent font-medium hover:underline"
            >
              {gettext("Connect a new one in Email accounts →")}
            </.link>
          </span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── partials ───────────────────────────────────────────────────────────
  attr :enrollment, :map, required: true
  attr :account, :map, required: true
  attr :last, :boolean, default: false

  defp enrolled_row(assigns) do
    ~H"""
    <div class={[!@last && "border-b border-border"]}>
      <%!-- desktop: aligned grid --%>
      <div class="hidden md:grid grid-cols-[1fr_120px_140px_160px] items-center">
        <div class="px-[18px] py-3.5">
          <div class="text-[13px] text-ink font-medium">{@account.address}</div>
          <div :if={@enrollment.paused_reason} class="text-[11px] text-inkSoft mt-0.5">
            {@enrollment.paused_reason}
          </div>
        </div>
        <div class="px-[14px] py-3.5 text-right">
          <span class="text-[12px] text-inkSoft tabular-nums">
            {gettext("%{quota}/day", quota: @account.daily_quota)}
          </span>
        </div>
        <div class="px-[14px] py-3.5">
          <.status_pill enrollment={@enrollment} account={@account} />
        </div>
        <div class="px-[14px] py-3.5 text-right flex items-center justify-end gap-2">
          <.link
            navigate={~p"/email-accounts/#{@account.id}/stats"}
            class="no-underline px-2.5 py-1 border border-borderStrong text-[10px] tracking-[0.06em] uppercase font-semibold text-inkSoft rounded-[8px] hover:text-ink hover:bg-paperAlt"
          >
            {gettext("stats")}
          </.link>
          <button
            type="button"
            phx-click="remove"
            phx-value-id={@enrollment.id}
            data-confirm={gettext("Remove %{address} from this campaign?", address: @account.address)}
            class="px-2.5 py-1 border border-borderStrong text-[10px] tracking-[0.06em] uppercase font-semibold text-inkSoft rounded-[8px] cursor-pointer hover:text-red hover:border-red/40 hover:bg-redSoft bg-card"
          >
            {gettext("remove")}
          </button>
        </div>
      </div>

      <%!-- mobile: stacked card --%>
      <div class="md:hidden flex flex-col gap-3 px-4 py-3.5">
        <div>
          <div class="text-[14px] text-ink font-medium break-all">{@account.address}</div>
          <div :if={@enrollment.paused_reason} class="text-[11px] text-inkSoft mt-0.5">
            {@enrollment.paused_reason}
          </div>
        </div>
        <div class="flex items-center justify-between gap-3">
          <span class="text-[10px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
            {gettext("Quota")}
          </span>
          <span class="text-[12px] text-inkSoft tabular-nums">
            {gettext("%{quota}/day", quota: @account.daily_quota)}
          </span>
        </div>
        <div class="flex items-center justify-between gap-3">
          <span class="text-[10px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
            {gettext("Status")}
          </span>
          <.status_pill enrollment={@enrollment} account={@account} />
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/email-accounts/#{@account.id}/stats"}
            class="no-underline flex-1 text-center px-2.5 py-2 border border-borderStrong text-[10px] tracking-[0.06em] uppercase font-semibold text-inkSoft rounded-[8px] hover:text-ink hover:bg-paperAlt"
          >
            {gettext("stats")}
          </.link>
          <button
            type="button"
            phx-click="remove"
            phx-value-id={@enrollment.id}
            data-confirm={gettext("Remove %{address} from this campaign?", address: @account.address)}
            class="flex-1 px-2.5 py-2 border border-borderStrong text-[10px] tracking-[0.06em] uppercase font-semibold text-inkSoft rounded-[8px] cursor-pointer hover:text-red hover:border-red/40 hover:bg-redSoft bg-card"
          >
            {gettext("remove")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :enrollment, :map, required: true
  attr :account, :map, required: true

  defp status_pill(assigns) do
    {label, class, dot_pulse, active?} =
      cond do
        assigns.account.status == :disconnected ->
          {gettext("disconnected"), "text-red border-red/30 bg-redSoft", false, false}

        assigns.account.status == :auth_error ->
          {gettext("auth error"), "text-red border-red/30 bg-redSoft", false, false}

        assigns.enrollment.paused? or assigns.account.status == :paused_bounces ->
          {gettext("paused"), "text-inkSoft border-border bg-paperAlt", false, false}

        true ->
          {gettext("active"), "text-accent border-accentRing bg-accentSoft", true, true}
      end

    assigns = assign(assigns, label: label, class: class, dot_pulse: dot_pulse, active?: active?)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.06em] uppercase font-semibold rounded-[8px] border",
      @class
    ]}>
      <span
        class={["w-1.5 h-1.5 rounded-full", @dot_pulse && "animate-pulse"]}
        style={if @active?, do: "background: var(--accent);", else: "background: currentColor;"}
      />
      {@label}
    </span>
    """
  end

  attr :campaign_id, :any, required: true

  defp empty_row(assigns) do
    ~H"""
    <div class="p-9 text-center">
      <div class="text-[22px] font-semibold text-ink tracking-[-0.01em] mb-1.5">
        {gettext("No inboxes enrolled yet.")}
      </div>
      <div class="text-[12px] text-inkSoft mb-3.5">
        {gettext("This campaign can't send until at least one is added.")}
      </div>
      <.link
        navigate={~p"/campaigns/#{@campaign_id}/sending-accounts/add"}
        class="no-underline inline-block"
      >
        <Liid.btn variant={:primary} size={:small}>
          <Liid.icon name="plus" size={11} /> {gettext("Add accounts")}
        </Liid.btn>
      </.link>
    </div>
    """
  end

  attr :account, :map, required: true
  attr :selected, :boolean, required: true
  attr :last, :boolean, default: false

  defp picker_row(assigns) do
    selectable = assigns.account.status not in [:disconnected, :auth_error]

    assigns =
      assign(assigns,
        selectable: selectable,
        row_class: if(assigns.selected, do: "bg-accentSoft", else: "bg-card")
      )

    ~H"""
    <div class={[
      !@last && "border-b border-border",
      @row_class
    ]}>
      <%!-- desktop: aligned grid --%>
      <div class="hidden md:grid grid-cols-[36px_1fr_100px_140px] items-center">
        <div class="py-3.5 pl-3.5">
          <button
            type="button"
            phx-click={@selectable && "toggle_pick"}
            phx-value-id={@account.id}
            disabled={!@selectable}
            class={[
              "w-[16px] h-[16px] rounded-[5px] border flex items-center justify-center",
              @selected && "border-accent",
              !@selected && @selectable &&
                "border-borderStrong hover:border-accentRing cursor-pointer",
              !@selectable && "border-border opacity-50 cursor-not-allowed"
            ]}
            style={@selected && "background: var(--accent);"}
            aria-pressed={@selected}
          >
            <Liid.icon :if={@selected} name="check" size={10} />
          </button>
        </div>
        <div class={["px-[14px] py-3.5", !@selectable && "opacity-60"]}>
          <div class="text-[13px] text-ink font-medium">{@account.address}</div>
          <div :if={!@selectable} class="text-[11px] text-red mt-0.5">
            {if @account.status == :disconnected,
              do: gettext("disconnected — re-auth in Email accounts first"),
              else: gettext("auth error — re-auth in Email accounts")}
          </div>
        </div>
        <div class={["px-[14px] py-3.5 text-right", !@selectable && "opacity-60"]}>
          <span class="text-[12px] text-inkSoft tabular-nums">
            {gettext("%{quota}/day", quota: @account.daily_quota)}
          </span>
        </div>
        <div class={["px-[14px] py-3.5", !@selectable && "opacity-60"]}>
          <.status_pill_static status={@account.status} />
        </div>
      </div>

      <%!-- mobile: stacked card; whole card toggles selection --%>
      <div
        class="md:hidden flex items-start gap-3 px-4 py-3.5"
        phx-click={@selectable && "toggle_pick"}
        phx-value-id={@selectable && @account.id}
      >
        <button
          type="button"
          phx-click={@selectable && "toggle_pick"}
          phx-value-id={@account.id}
          disabled={!@selectable}
          class={[
            "shrink-0 mt-0.5 w-[18px] h-[18px] rounded-[5px] border flex items-center justify-center",
            @selected && "border-accent",
            !@selected && @selectable && "border-borderStrong cursor-pointer",
            !@selectable && "border-border opacity-50 cursor-not-allowed"
          ]}
          style={@selected && "background: var(--accent);"}
          aria-pressed={@selected}
        >
          <Liid.icon :if={@selected} name="check" size={11} />
        </button>
        <div class={["flex-1 min-w-0 flex flex-col gap-2", !@selectable && "opacity-60"]}>
          <div>
            <div class="text-[14px] text-ink font-medium break-all">{@account.address}</div>
            <div :if={!@selectable} class="text-[11px] text-red mt-0.5">
              {if @account.status == :disconnected,
                do: gettext("disconnected — re-auth in Email accounts first"),
                else: gettext("auth error — re-auth in Email accounts")}
            </div>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-[12px] text-inkSoft tabular-nums">
              {gettext("%{quota}/day", quota: @account.daily_quota)}
            </span>
            <.status_pill_static status={@account.status} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_pill_static(assigns) do
    {label, active?, tone} =
      case assigns.status do
        :healthy -> {gettext("active"), true, :active}
        :paused_bounces -> {gettext("paused"), false, :paused}
        :disconnected -> {gettext("disconnected"), false, :fail}
        :auth_error -> {gettext("auth error"), false, :fail}
      end

    assigns = assign(assigns, label: label, active?: active?, tone: tone)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 text-[10px] tracking-[0.06em] uppercase font-semibold rounded-[8px] border",
      @active? && "text-accent border-accentRing bg-accentSoft",
      @tone == :paused && "text-inkSoft border-border bg-paperAlt",
      @tone == :fail && "text-red border-red/30 bg-redSoft"
    ]}>
      <span
        class={["w-1.5 h-1.5 rounded-full", @active? && "animate-pulse"]}
        style={if @active?, do: "background: var(--accent);", else: "background: currentColor;"}
      />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :big, :string, required: true
  attr :sub, :string, default: nil
  attr :accent, :boolean, default: false

  defp capacity_tile(assigns) do
    ~H"""
    <div
      class={[
        "px-5 py-4 rounded-[11px] border",
        if(@accent, do: "bg-accentSoft border-accentRing", else: "bg-card border-border")
      ]}
      style="box-shadow:var(--shadow)"
    >
      <div class={[
        "text-[10.5px] tracking-[0.09em] uppercase font-semibold mb-2",
        if(@accent, do: "text-accent", else: "text-inkFaint")
      ]}>
        {@label}
      </div>
      <div
        class="text-[34px] font-bold leading-none tracking-[-0.02em] tabular-nums"
        style={@accent && "color: var(--accent);"}
      >
        {@big}
      </div>
      <div :if={@sub} class="mt-2 text-[11px] text-inkSoft tabular-nums">{@sub}</div>
    </div>
    """
  end
end
