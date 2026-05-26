defmodule ColtWeb.Components.Liid do
  @moduledoc """
  Liid design-system function components.

  Source of truth for visuals is `priv/design_prototype/project/liid-shared.jsx`.
  Tokens and keyframes are defined in `assets/css/app.css`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  defp open_feedback do
    %JS{}
    |> JS.remove_class("hidden", to: "#feedback-modal")
    |> JS.focus(to: "#feedback-body")
  end

  @icon_paths %{
    "arrow" => "M3 8h10M9 4l4 4-4 4",
    "chev" => "M5 6l3 3 3-3",
    "chev-r" => "M6 4l4 4-4 4",
    "chev-l" => "M10 4L6 8l4 4",
    "plus" => "M8 3v10M3 8h10",
    "x" => "M4 4l8 8M12 4l-8 8",
    "check" => "M3 8.5l3 3 7-7",
    "search" => "M7 12.5a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11zm4-1.5l3 3",
    "globe" => "M8 1.5v13M1.5 8h13M8 1.5a8 8 0 0 1 0 13M8 1.5a8 8 0 0 0 0 13",
    "spark" => "M8 2v4M8 10v4M2 8h4M10 8h4",
    "download" => "M8 2v9M4 7l4 4 4-4M3 14h10",
    "file" => "M4 2h6l2 2v10H4V2zM10 2v2h2",
    "user" => "M8 8.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM3 14c.5-2.5 2.6-4 5-4s4.5 1.5 5 4",
    "mail" => "M2 4h12v8H2V4zM2 4l6 5 6-5",
    "phone" =>
      "M3 3h3l1.5 3.5L6 8a8 8 0 0 0 2 2l1.5-1.5L13 10v3a1 1 0 0 1-1 1A10 10 0 0 1 2 4a1 1 0 0 1 1-1z",
    "link" =>
      "M7 9l2-2M6 10a2.5 2.5 0 0 1 0-3.5l2-2a2.5 2.5 0 0 1 3.5 3.5l-1 1M10 6a2.5 2.5 0 0 1 0 3.5l-2 2A2.5 2.5 0 0 1 4.5 8l1-1",
    "code" => "M5 5L2 8l3 3M11 5l3 3-3 3M9 3l-2 10",
    "filter" => "M2 3h12l-4.5 6v5L7 12V9L2 3z",
    "grid" => "M2 2h5v5H2zM9 2h5v5H9zM2 9h5v5H2zM9 9h5v5H9z",
    "refresh" => "M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 2v3h-3"
  }

  @stepper_steps ~w(Name ICP Market Filters Target Enrichment)

  attr :name, :string, required: true
  attr :size, :integer, default: 14
  attr :class, :string, default: nil

  def icon(assigns) do
    assigns = assign(assigns, :path, Map.fetch!(@icon_paths, assigns.name))

    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.25"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
    >
      <path d={@path} />
    </svg>
    """
  end

  @doc """
  State-driven status dot. State is one of `:idle | :work | :done | :skip | :fall | :fail`.
  """
  attr :state, :atom, default: :idle
  attr :size, :integer, default: 8
  attr :class, :string, default: nil

  def status_dot(assigns) do
    {bg, border, halo, animate} = dot_style(assigns.state)
    assigns = assign(assigns, bg: bg, border: border, halo: halo, animate: animate)

    ~H"""
    <span
      class={[
        "inline-block shrink-0 rounded-full",
        @animate && "animate-[liid-pulse_1.4s_ease-in-out_infinite]",
        @class
      ]}
      style={"width:#{@size}px;height:#{@size}px;background:#{@bg};border:1px solid #{@border};box-shadow:#{@halo};"}
    />
    """
  end

  defp dot_style(:idle), do: {"transparent", "var(--ink20)", "none", false}

  defp dot_style(:work),
    do:
      {"var(--accent)", "var(--accent)",
       "0 0 0 3px color-mix(in oklch, var(--accent) 13%, transparent)", true}

  defp dot_style(:done), do: {"var(--accent)", "var(--accent)", "none", false}
  defp dot_style(:skip), do: {"var(--ink40)", "var(--ink40)", "none", false}
  defp dot_style(:fall), do: {"var(--warn)", "var(--warn)", "none", false}
  defp dot_style(:fail), do: {"var(--fail)", "var(--fail)", "none", false}

  @doc """
  Liid button. `variant` is `:primary` (ink/paper) or `:secondary` (transparent/ink20 border).
  """
  attr :variant, :atom, default: :secondary, values: [:primary, :secondary]
  attr :size, :atom, default: :default, values: [:default, :small]
  attr :mono, :boolean, default: false
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(disabled name value form phx-click phx-disable-with phx-submit)
  slot :inner_block, required: true

  def btn(assigns) do
    pad =
      case assigns.size do
        :small -> "px-3 py-[7px] text-[12px]"
        _ -> "px-[18px] py-[10px] text-[13px]"
      end

    family = if assigns.mono, do: "font-mono tracking-[0.04em]", else: "font-sans"

    color =
      case assigns.variant do
        :primary -> "bg-ink text-paper border-ink"
        :secondary -> "bg-transparent text-ink border-ink20"
      end

    assigns =
      assign(assigns,
        classes:
          "inline-flex items-center gap-2 border rounded-[2px] font-medium cursor-pointer transition-all disabled:opacity-40 disabled:cursor-not-allowed disabled:pointer-events-none #{pad} #{family} #{color}"
      )

    ~H"""
    <button type={@type} class={@classes} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Headline block: kicker (mono uppercase) + serif title (with optional `<em>` accent word) + sub.
  """
  attr :kicker, :string, default: nil
  attr :sub, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def headline(assigns) do
    ~H"""
    <div class={["max-w-[640px]", @class]}>
      <div :if={@kicker} class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-3.5">
        {@kicker}
      </div>
      <h1 class="font-serif font-normal text-[40px] md:text-[64px] leading-[1.02] tracking-[-0.04em] m-0 text-pretty">
        {render_slot(@inner_block)}
      </h1>
      <div :if={@sub} class="mt-5 text-[15px] leading-[1.5] text-ink55 max-w-[520px] text-pretty">
        {@sub}
      </div>
    </div>
    """
  end

  @doc """
  Top bar — wordmark + stepper + campaign chip + avatar.

  Pass `step` (0..4 or nil) to highlight a step. Pass `campaign_name` to show the right-side chip.
  """
  attr :step, :any, default: nil
  attr :current_user, :map, default: nil
  attr :campaign_name, :string, default: nil
  attr :campaign_id, :any, default: nil
  attr :campaign, :any, default: nil

  def top_bar(assigns) do
    assigns = assign(assigns, :steps, @stepper_steps)

    ~H"""
    <header class="flex items-center gap-3 md:gap-8 px-4 md:px-8 py-4 md:py-5 border-b border-rule">
      <.link navigate="/" class="flex items-baseline gap-1.5 no-underline text-ink shrink-0">
        <span class="font-serif text-[26px] leading-none tracking-[-0.02em]">Liid</span>
        <span
          class="inline-block w-1.5 h-1.5 rounded-full -translate-y-[3px]"
          style="background: var(--accent);"
        />
      </.link>

      <nav
        :if={not is_nil(@step)}
        class="hidden lg:flex items-center font-mono text-[11px] tracking-[0.04em]"
      >
        <% reachable = reachable_steps(@campaign, @step) %>
        <%= for {label, i} <- Enum.with_index(@steps) do %>
          <% state = step_state(i, @step) %>
          <% href = if i in reachable, do: step_href_for(i, @campaign_id), else: nil %>
          <.step_segment state={state} href={href} index={i} label={label} />
          <span :if={i < length(@steps) - 1} class="w-[14px] h-px bg-ink20" />
        <% end %>
      </nav>

      <nav
        :if={not is_nil(@step)}
        class="flex lg:hidden items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] uppercase text-ink55"
      >
        <span class="text-ink tnum">{String.pad_leading(Integer.to_string(@step), 2, "0")}</span>
        <span>{Enum.at(@steps, @step)}</span>
        <span class="text-ink40">· {length(@steps)}</span>
      </nav>

      <div class="flex-1" />

      <div class="flex items-center gap-2 md:gap-3.5 text-[12px] text-ink55">
        <span
          :if={@campaign_name}
          class="hidden md:inline font-mono tracking-[0.04em] truncate max-w-[200px]"
        >
          campaign: <span class="text-ink">{@campaign_name}</span>
        </span>
        <span :if={@campaign_name} class="hidden md:inline w-px h-3.5 bg-ink20" />
        <%= if @current_user do %>
          <button
            type="button"
            phx-click={open_feedback()}
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline cursor-pointer bg-transparent border-0 p-0"
          >
            feedback
          </button>
          <.link
            navigate="/campaigns/new"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
          >
            campaigns
          </.link>
          <.link
            :if={@current_user.is_admin}
            href="/admin"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
          >
            admin
          </.link>
          <.link
            href="/sign-out"
            method="get"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
          >
            <span class="hidden sm:inline">sign out</span>
            <span class="sm:hidden">out</span>
          </.link>
          <div
            class="w-6 h-6 rounded-full bg-ink text-paper flex items-center justify-center text-[11px] font-semibold"
            title={to_string(@current_user.email)}
          >
            {avatar_initial(@current_user)}
          </div>
        <% else %>
          <.link
            href="/sign-in"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
          >
            sign in
          </.link>
        <% end %>
      </div>
    </header>
    """
  end

  defp step_state(_i, nil), do: :future
  defp step_state(i, step) when i == step, do: :active
  defp step_state(i, step) when i < step, do: :done
  defp step_state(_i, _step), do: :future

  defp step_color(:active), do: "text-ink"
  defp step_color(:done), do: "text-ink55"
  defp step_color(:future), do: "text-ink40"

  defp step_href_for(0, _id), do: "/campaigns/new"
  defp step_href_for(_, nil), do: nil
  defp step_href_for(1, id), do: "/campaigns/#{id}/icp"
  defp step_href_for(2, id), do: "/campaigns/#{id}/market"
  defp step_href_for(3, id), do: "/campaigns/#{id}/filters"
  defp step_href_for(4, id), do: "/campaigns/#{id}/target"
  defp step_href_for(5, id), do: "/campaigns/#{id}/funnel"
  defp step_href_for(_, _), do: nil

  # Stages the user can navigate to. Past stages with saved data are always
  # reachable. The current stage is reachable (no-op nav). Once enrichment
  # has started, every stage is reachable for review.
  defp reachable_steps(nil, current), do: List.wrap(current)

  defp reachable_steps(campaign, current) do
    enriching? = Map.get(campaign, :status) == :enriching

    cond do
      enriching? ->
        [0, 1, 2, 3, 4, 5]

      true ->
        base = [0]
        base = if present?(campaign, :icp_description), do: [1 | base], else: base
        base = if present?(campaign, :market), do: [2 | base], else: base
        base = if present_map?(campaign, :filters), do: [3 | base], else: base
        base = if present_map?(campaign, :filters), do: [4 | base], else: base
        [current | base] |> Enum.uniq() |> Enum.sort()
    end
  end

  defp present?(campaign, key) do
    case Map.get(campaign, key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp present_map?(campaign, key) do
    case Map.get(campaign, key) do
      m when is_map(m) and map_size(m) > 0 -> true
      _ -> false
    end
  end

  attr :state, :atom, required: true
  attr :href, :any, required: true
  attr :index, :integer, required: true
  attr :label, :string, required: true

  defp step_segment(%{href: nil} = assigns) do
    ~H"""
    <div class={["flex items-center gap-2 px-3 py-1.5", step_color(@state)]}>
      <.step_inner state={@state} index={@index} label={@label} />
    </div>
    """
  end

  defp step_segment(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={["flex items-center gap-2 px-3 py-1.5 no-underline hover:text-ink", step_color(@state)]}
    >
      <.step_inner state={@state} index={@index} label={@label} />
    </.link>
    """
  end

  attr :state, :atom, required: true
  attr :index, :integer, required: true
  attr :label, :string, required: true

  defp step_inner(assigns) do
    ~H"""
    <span class={[
      "tnum",
      @state == :active && "font-semibold",
      @state == :active && "text-[var(--accent)]"
    ]}>
      {String.pad_leading(Integer.to_string(@index), 2, "0")}
    </span>
    <span class="uppercase tracking-[0.08em]">{@label}</span>
    """
  end

  defp avatar_initial(%{email: email}) do
    email |> to_string() |> String.first() |> String.upcase()
  end

  defp avatar_initial(_), do: "·"

  @doc """
  Outer screen wrapper — sidebar shell with paper background.

  `active` is the current sidebar item id (atom). `campaign` puts the sidebar
  in campaign scope (shows Enrichment + Sending sections). Without a campaign,
  only the Workspace section is shown.
  """
  attr :active, :atom, default: nil
  attr :step, :any, default: nil
  attr :current_user, :map, default: nil
  attr :campaign_name, :string, default: nil
  attr :campaign_id, :any, default: nil
  attr :campaign, :any, default: nil
  attr :panic_on, :boolean, default: false
  attr :landing, :boolean, default: false
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def screen(assigns) do
    assigns =
      assign_new(assigns, :resolved_active, fn ->
        assigns.active || step_to_active(assigns.step)
      end)

    ~H"""
    <div class={["min-h-screen bg-paper text-ink", !@landing && "flex"]}>
      <.sidebar
        :if={!@landing}
        active={@resolved_active}
        current_user={@current_user}
        campaign={@campaign}
        campaign_id={@campaign_id}
        campaign_name={@campaign_name}
        panic_on={@panic_on}
      />
      <div class={[
        !@landing && "flex-1 min-w-0 flex flex-col",
        @landing && "flex flex-col min-h-screen"
      ]}>
        <.landing_top_bar :if={@landing} current_user={@current_user} />
        <div
          :if={@panic_on}
          class="px-6 py-2.5 bg-fail text-paper font-mono text-[11px] tracking-[0.06em] uppercase flex items-center gap-3 border-b border-fail"
        >
          <span class="inline-block w-[7px] h-[7px] rounded-full bg-paper animate-[liid-pulse_1.4s_ease-in-out_infinite]" />
          <span class="font-semibold tracking-[0.12em]">Sending halted</span>
        </div>
        <main class={["flex-1 px-4 py-6 md:px-14 md:py-10", @class]}>
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr :current_user, :map, default: nil

  def landing_top_bar(assigns) do
    ~H"""
    <header class="flex items-center gap-6 px-4 md:px-8 py-4 md:py-5 border-b border-rule">
      <.link navigate="/" class="flex items-baseline gap-1.5 no-underline text-ink shrink-0">
        <span class="font-serif text-[26px] leading-none tracking-[-0.02em]">Liid</span>
        <span
          class="inline-block w-1.5 h-1.5 rounded-full -translate-y-[3px]"
          style="background: var(--color-accent);"
        />
      </.link>

      <div class="flex-1" />

      <div class="flex items-center gap-2">
        <%= if @current_user do %>
          <.link
            navigate="/campaigns"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline border border-ink20 rounded-[2px] px-3 py-1.5"
          >
            Campaigns
          </.link>
          <.link
            href="/sign-out"
            method="get"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline border border-ink20 rounded-[2px] px-3 py-1.5"
          >
            Sign out
          </.link>
        <% else %>
          <.link
            href="/sign-in"
            class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline border border-ink20 rounded-[2px] px-3 py-1.5"
          >
            Sign in
          </.link>
        <% end %>
      </div>
    </header>
    """
  end

  defp step_to_active(nil), do: nil
  defp step_to_active(0), do: :campaigns
  defp step_to_active(1), do: :icp
  defp step_to_active(2), do: :market
  defp step_to_active(3), do: :filters
  defp step_to_active(4), do: :target
  defp step_to_active(5), do: :enrichment_funnel
  defp step_to_active(_), do: nil

  @workspace_items [
    %{id: :campaigns, label: "Campaigns", icon: "grid", href: "/campaigns"},
    %{id: :email_accounts, label: "Email accounts", icon: "mail", href: "/email-accounts"},
    %{id: :billing, label: "Billing", icon: "file", href: "/billing"}
  ]

  @enrichment_items [
    %{id: :name, label: "Name", icon: "file"},
    %{id: :icp, label: "ICP", icon: "user"},
    %{id: :market, label: "Market", icon: "globe"},
    %{id: :filters, label: "Filters", icon: "filter"},
    %{id: :target, label: "Target", icon: "spark"},
    %{id: :enrichment_funnel, label: "Funnel", icon: "grid"}
  ]

  @sending_items [
    %{id: :pitch, label: "Pitch", icon: "spark"},
    %{id: :sequence, label: "Sequence", icon: "code"},
    %{id: :sending_accounts, label: "Sending accounts", icon: "mail"},
    %{id: :writing, label: "Writing", icon: "spark"},
    %{id: :sending_funnel, label: "Sending funnel", icon: "grid"}
  ]

  attr :active, :atom, default: nil
  attr :current_user, :map, default: nil
  attr :campaign, :any, default: nil
  attr :campaign_id, :any, default: nil
  attr :campaign_name, :string, default: nil
  attr :panic_on, :boolean, default: false

  def sidebar(assigns) do
    assigns = assign(assigns, :workspace_items, @workspace_items)

    ~H"""
    <aside class="w-[240px] shrink-0 sticky top-0 self-start h-screen border-r border-rule bg-paper flex flex-col">
      <div class="px-[22px] py-5 border-b border-rule flex items-baseline gap-1.5">
        <.link navigate="/" class="flex items-baseline gap-1.5 no-underline text-ink">
          <span class="font-serif text-[24px] leading-none tracking-[-0.02em]">Liid</span>
          <span
            class="inline-block w-[5px] h-[5px] rounded-full -translate-y-[2px]"
            style="background: var(--color-accent);"
          />
        </.link>
      </div>

      <div class="flex-1 overflow-auto">
        <.sidebar_section items={@workspace_items} active={@active} variant={:workspace} />

        <.campaign_scope_header :if={@campaign} campaign={@campaign} />

        <.sidebar_section
          :if={@campaign}
          label="Enrichment"
          items={enrichment_items_with_hrefs(@campaign_id)}
          active={@active}
        />

        <.sidebar_section
          :if={@campaign}
          label="Sending"
          items={sending_items_with_hrefs(@campaign_id)}
          active={@active}
        >
          <:header_extra>
            <.panic_switch on={@panic_on} />
          </:header_extra>
        </.sidebar_section>
      </div>

      <div :if={@current_user} class="border-t border-rule">
        <button
          type="button"
          phx-click={open_feedback()}
          class="w-full flex items-center gap-2.5 px-[18px] py-[7px] text-left text-ink70 hover:text-ink hover:bg-paperAlt cursor-pointer bg-transparent border-0"
        >
          <.icon name="mail" size={13} class="text-ink55" />
          <span class="text-[13px]">Feedback</span>
        </button>
        <.link
          :if={@current_user.is_admin}
          href="/admin"
          class="flex items-center gap-2.5 px-[18px] py-[7px] text-ink70 hover:text-ink hover:bg-paperAlt no-underline"
        >
          <.icon name="code" size={13} class="text-ink55" />
          <span class="text-[13px]">Admin</span>
        </.link>
        <.link
          href="/sign-out"
          method="get"
          class="flex items-center gap-2.5 px-[18px] py-[7px] text-ink70 hover:text-ink hover:bg-paperAlt no-underline"
        >
          <.icon name="arrow" size={13} class="text-ink55" />
          <span class="text-[13px]">Sign out</span>
        </.link>

        <div class="border-t border-rule px-[18px] py-3 flex items-center gap-2.5">
          <div
            class="w-[26px] h-[26px] rounded-full bg-ink text-paper flex items-center justify-center text-[11px] font-semibold shrink-0"
            title={to_string(@current_user.email)}
          >
            {avatar_initial(@current_user)}
          </div>
          <div class="text-[12px] text-ink truncate">{to_string(@current_user.email)}</div>
        </div>
      </div>
      <div :if={!@current_user} class="border-t border-rule px-[18px] py-3.5">
        <.link
          href="/sign-in"
          class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
        >
          sign in
        </.link>
      </div>
    </aside>
    """
  end

  defp enrichment_items_with_hrefs(nil), do: @enrichment_items

  defp enrichment_items_with_hrefs(id) do
    Enum.map(@enrichment_items, fn item -> Map.put(item, :href, enrichment_href(item.id, id)) end)
  end

  defp sending_items_with_hrefs(nil), do: @sending_items

  defp sending_items_with_hrefs(id) do
    Enum.map(@sending_items, fn item -> Map.put(item, :href, sending_href(item.id, id)) end)
  end

  defp enrichment_href(:name, id), do: "/campaigns/#{id}/name"
  defp enrichment_href(:icp, id), do: "/campaigns/#{id}/icp"
  defp enrichment_href(:market, id), do: "/campaigns/#{id}/market"
  defp enrichment_href(:filters, id), do: "/campaigns/#{id}/filters"
  defp enrichment_href(:target, id), do: "/campaigns/#{id}/target"
  defp enrichment_href(:enrichment_funnel, id), do: "/campaigns/#{id}/funnel"

  defp sending_href(:pitch, id), do: "/campaigns/#{id}/pitch"
  defp sending_href(:sequence, id), do: "/campaigns/#{id}/sequence"
  defp sending_href(:sending_accounts, id), do: "/campaigns/#{id}/sending-accounts"
  defp sending_href(:writing, id), do: "/campaigns/#{id}/writing"
  defp sending_href(:sending_funnel, id), do: "/campaigns/#{id}/sending-funnel"

  attr :label, :string, default: nil
  attr :items, :list, required: true
  attr :active, :atom, default: nil
  attr :variant, :atom, default: :default
  slot :header_extra

  defp sidebar_section(assigns) do
    assigns =
      assign(
        assigns,
        :wrapper_class,
        if(assigns.variant == :workspace, do: "pt-3 mb-1.5", else: "mb-3.5")
      )

    ~H"""
    <div class={@wrapper_class}>
      <div
        :if={@label}
        class="px-[18px] py-1.5 flex items-center justify-between"
      >
        <span class="font-mono text-[10px] tracking-[0.14em] uppercase text-ink40">{@label}</span>
        <span :if={@header_extra != []}>{render_slot(@header_extra)}</span>
      </div>
      <div>
        <%= for item <- @items do %>
          <% is_active = item.id == @active %>
          <.link
            navigate={item.href}
            class={[
              "relative flex items-center gap-2.5 px-[18px] py-[7px] no-underline",
              is_active && "bg-paperAlt"
            ]}
          >
            <span
              :if={is_active}
              class="absolute left-0 top-1 bottom-1 w-[2px]"
              style="background: var(--color-accent);"
            />
            <.icon
              name={item.icon}
              size={13}
              class={if(is_active, do: "text-ink", else: "text-ink55")}
            />
            <span class={[
              "text-[13px]",
              if(is_active, do: "text-ink font-medium", else: "text-ink70")
            ]}>
              {item.label}
            </span>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :campaign, :map, required: true

  defp campaign_scope_header(assigns) do
    ~H"""
    <div class="px-[18px] pt-4 pb-3 border-t border-b border-rule bg-paperAlt mb-2.5">
      <div class="font-mono text-[9px] tracking-[0.14em] uppercase text-ink40 mb-1.5">
        Campaign
      </div>
      <div class="font-serif text-[20px] leading-[1.1] tracking-[-0.015em] text-ink truncate">
        {@campaign.name}
      </div>
      <div class="mt-1.5 font-mono text-[10px] text-ink40 tracking-[0.04em]">
        {to_string(@campaign.status)}
      </div>
    </div>
    """
  end

  attr :on, :boolean, default: false

  defp panic_switch(assigns) do
    ~H"""
    <span
      title={if @on, do: "Sending paused", else: "Sending on"}
      class="relative inline-block w-6 h-[13px] rounded-full"
      style={"background: #{if @on, do: "var(--color-ink20)", else: "var(--color-accent)"}; transition: background .12s;"}
    >
      <span
        class="absolute top-px w-[11px] h-[11px] rounded-full bg-paper"
        style={"left: #{if @on, do: "1px", else: "12px"}; box-shadow: 0 1px 2px rgba(0,0,0,0.2); transition: left .12s;"}
      />
    </span>
    """
  end
end
