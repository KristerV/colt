defmodule ColtWeb.Sending.SendingAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, CampaignEmailAccount, EmailAccount, Sequence, SequenceStep}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}

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
            <Liid.btn variant={:primary} mono size={:small}>
              <Liid.icon name="plus" size={11} /> {gettext("Add accounts")}
            </Liid.btn>
          </.link>
        </div>

        <div class="border border-rule rounded-[2px] overflow-hidden">
          <div class="grid grid-cols-[1fr_120px_140px_160px] bg-paperAlt border-b border-rule font-mono text-[10px] tracking-[0.12em] uppercase text-ink55">
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

        <div class="mt-7 grid grid-cols-3 gap-px bg-rule border border-rule rounded-[2px] overflow-hidden">
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
              mono
              phx-click="save_picker"
            >
              <Liid.icon name="check" size={11} /> {gettext("Save selection")}
            </Liid.btn>
          </div>
        </div>

        <div class="mb-3 font-mono text-[11px] text-ink55 tracking-[0.04em]">
          <span class="text-ink font-semibold">{@selected_count}</span>
          {gettext("selected · %{total} available", total: @total_count)}
        </div>

        <div class="border border-rule rounded-[2px] overflow-hidden">
          <div class="grid grid-cols-[36px_1fr_100px_140px] bg-paperAlt border-b border-rule font-mono text-[10px] tracking-[0.12em] uppercase text-ink55">
            <div class="py-3"></div>
            <div class="px-[14px] py-3">{gettext("Account")}</div>
            <div class="px-[14px] py-3 text-right">{gettext("Quota")}</div>
            <div class="px-[14px] py-3">{gettext("Status")}</div>
          </div>

          <%= if @accounts == [] do %>
            <div class="p-9 text-center">
              <div class="font-serif text-[22px] text-ink55 tracking-[-0.01em] mb-1.5">
                {gettext("No inboxes connected yet.")}
              </div>
              <div class="text-[12px] text-ink40 mb-3.5">
                {gettext("Connect at least one in Email accounts to enroll it here.")}
              </div>
              <.link navigate={~p"/email-accounts"} class="no-underline">
                <Liid.btn size={:small} mono>
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

        <div class="mt-4 px-4 py-3 bg-paperAlt border border-rule rounded-[2px] flex items-center gap-2.5 font-mono text-[11px] text-ink55 tracking-[0.04em]">
          <Liid.icon name="spark" size={11} />
          <span>
            {gettext("Don't see the inbox you want?")}
            <.link
              navigate={~p"/email-accounts"}
              class="text-ink underline underline-offset-2 hover:text-ink70"
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
    <div class={[
      "grid grid-cols-[1fr_120px_140px_160px] items-center",
      !@last && "border-b border-rule"
    ]}>
      <div class="px-[18px] py-3.5">
        <div class="font-mono text-[13px] text-ink font-medium">{@account.address}</div>
        <div :if={@enrollment.paused_reason} class="text-[11px] text-ink55 mt-0.5">
          {@enrollment.paused_reason}
        </div>
      </div>
      <div class="px-[14px] py-3.5 text-right">
        <span class="font-mono text-[12px] text-ink70 tabular-nums">
          {gettext("%{quota}/day", quota: @account.daily_quota)}
        </span>
      </div>
      <div class="px-[14px] py-3.5">
        <.status_pill enrollment={@enrollment} account={@account} />
      </div>
      <div class="px-[14px] py-3.5 text-right flex items-center justify-end gap-2">
        <.link
          navigate={~p"/email-accounts/#{@account.id}/stats"}
          class="no-underline px-2.5 py-1 border border-ink20 font-mono text-[10px] tracking-[0.08em] uppercase text-ink55 rounded-[2px] hover:text-ink hover:border-ink40"
        >
          {gettext("stats")}
        </.link>
        <button
          type="button"
          phx-click="remove"
          phx-value-id={@enrollment.id}
          data-confirm={gettext("Remove %{address} from this campaign?", address: @account.address)}
          class="px-2.5 py-1 border border-ink20 font-mono text-[10px] tracking-[0.08em] uppercase text-ink55 rounded-[2px] cursor-pointer hover:text-ink hover:border-ink40 bg-transparent"
        >
          {gettext("remove")}
        </button>
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
          {gettext("disconnected"), "text-fail border-fail/40 bg-fail/10", false, false}

        assigns.account.status == :auth_error ->
          {gettext("auth error"), "text-fail border-fail/40 bg-fail/10", false, false}

        assigns.enrollment.paused? or assigns.account.status == :paused_bounces ->
          {gettext("paused"), "text-ink55 border-ink20 bg-ink10", false, false}

        true ->
          {gettext("active"), "border-[color:var(--accent)]/40", true, true}
      end

    assigns = assign(assigns, label: label, class: class, dot_pulse: dot_pulse, active?: active?)

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1.5 px-2.5 py-1 font-mono text-[10px] tracking-[0.06em] uppercase font-semibold rounded-[2px] border",
        @class
      ]}
      style={
        if @active?,
          do: "color: var(--accent); background: color-mix(in oklch, var(--accent) 8%, transparent);"
      }
    >
      <span
        class={["w-1.5 h-1.5 rounded-full", @dot_pulse && "animate-pulse"]}
        style={
          if @active?,
            do: "background: var(--accent);",
            else: "background: currentColor;"
        }
      />
      {@label}
    </span>
    """
  end

  attr :campaign_id, :any, required: true

  defp empty_row(assigns) do
    ~H"""
    <div class="p-9 text-center">
      <div class="font-serif text-[22px] text-ink55 tracking-[-0.01em] mb-1.5">
        {gettext("No inboxes enrolled yet.")}
      </div>
      <div class="text-[12px] text-ink40 mb-3.5">
        {gettext("This campaign can't send until at least one is added.")}
      </div>
      <.link navigate={~p"/campaigns/#{@campaign_id}/sending-accounts/add"} class="no-underline">
        <Liid.btn variant={:primary} size={:small} mono>
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
        row_class: if(assigns.selected, do: "bg-[color:var(--accent)]/[0.03]", else: "bg-paper")
      )

    ~H"""
    <div class={[
      "grid grid-cols-[36px_1fr_100px_140px] items-center",
      !@last && "border-b border-rule",
      @row_class
    ]}>
      <div class="py-3.5 pl-3.5">
        <button
          type="button"
          phx-click={@selectable && "toggle_pick"}
          phx-value-id={@account.id}
          disabled={!@selectable}
          class={[
            "w-[14px] h-[14px] rounded-[2px] border flex items-center justify-center",
            @selected && "border-[color:var(--accent)]",
            !@selected && @selectable && "border-ink40 hover:border-ink70 cursor-pointer",
            !@selectable && "border-ink20 opacity-50 cursor-not-allowed"
          ]}
          style={@selected && "background: var(--accent);"}
          aria-pressed={@selected}
        >
          <Liid.icon :if={@selected} name="check" size={10} />
        </button>
      </div>
      <div class={["px-[14px] py-3.5", !@selectable && "opacity-60"]}>
        <div class="font-mono text-[13px] text-ink font-medium">{@account.address}</div>
        <div :if={!@selectable} class="text-[11px] text-fail mt-0.5">
          {if @account.status == :disconnected,
            do: gettext("disconnected — re-auth in Email accounts first"),
            else: gettext("auth error — re-auth in Email accounts")}
        </div>
      </div>
      <div class={["px-[14px] py-3.5 text-right", !@selectable && "opacity-60"]}>
        <span class="font-mono text-[12px] text-ink70 tabular-nums">
          {gettext("%{quota}/day", quota: @account.daily_quota)}
        </span>
      </div>
      <div class={["px-[14px] py-3.5", !@selectable && "opacity-60"]}>
        <.status_pill_static status={@account.status} />
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
    <span
      class={[
        "inline-flex items-center gap-1.5 px-2.5 py-1 font-mono text-[10px] tracking-[0.06em] uppercase font-semibold rounded-[2px] border",
        @active? && "border-[color:var(--accent)]/40",
        @tone == :paused && "text-ink55 border-ink20 bg-ink10",
        @tone == :fail && "text-fail border-fail/40 bg-fail/10"
      ]}
      style={
        if @active?,
          do: "color: var(--accent); background: color-mix(in oklch, var(--accent) 8%, transparent);"
      }
    >
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
    <div class="px-6 py-5 bg-paper">
      <div class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink55 mb-2">{@label}</div>
      <div
        class="font-serif text-[42px] font-normal leading-none tracking-[-0.02em] tabular-nums"
        style={@accent && "color: var(--accent);"}
      >
        {@big}
      </div>
      <div :if={@sub} class="mt-2 font-mono text-[11px] text-ink55 tracking-[0.04em]">{@sub}</div>
    </div>
    """
  end
end
