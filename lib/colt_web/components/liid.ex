defmodule ColtWeb.Components.Liid do
  @moduledoc """
  Liid design-system function components.

  Source of truth for visuals is `priv/design_prototype/project/liid-shared.jsx`.
  Tokens and keyframes are defined in `assets/css/app.css`.
  """
  use Phoenix.Component
  use Gettext, backend: ColtWeb.Gettext

  alias Colt.Accounts.User
  alias Phoenix.LiveView.JS

  defp open_feedback do
    %JS{}
    |> JS.remove_class("hidden", to: "#feedback-modal")
    |> JS.focus(to: "#feedback-body")
  end

  # Mobile nav drawer — slide the sidebar in/out and toggle the scrim.
  # These run client-side (no server round-trip) and no-op visually at md+,
  # where the sidebar is static. Nav links call close_nav/0 too so the drawer
  # dismisses on tap before navigation.
  defp open_nav do
    %JS{}
    |> JS.remove_class("-translate-x-full", to: "#liid-sidebar")
    |> JS.remove_class("hidden", to: "#liid-nav-backdrop")
  end

  defp close_nav do
    %JS{}
    |> JS.add_class("-translate-x-full", to: "#liid-sidebar")
    |> JS.add_class("hidden", to: "#liid-nav-backdrop")
  end

  @doc "Dot background-color class for a sales-stage kind (nil/active → accent)."
  def stage_dot(:won), do: "bg-green"
  def stage_dot(:lost), do: "bg-inkFaint"
  def stage_dot(_), do: "bg-accent"

  @icon_paths %{
    "arrow" => "M3 8h10M9 4l4 4-4 4",
    "logout" => "M10 3H4v10h6M8 8h6M11 5l3 3-3 3",
    "chev" => "M5 6l3 3 3-3",
    "chev-r" => "M6 4l4 4-4 4",
    "chev-l" => "M10 4L6 8l4 4",
    "chev-l2" => "M8 4L4 8l4 4M12 4L8 8l4 4",
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
    "refresh" => "M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 2v3h-3",
    "menu" => "M2 4h12M2 8h12M2 12h12"
  }

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
        :small -> "px-3.5 py-[7px] text-[12px]"
        _ -> "px-[18px] py-[9px] text-[13px]"
      end

    color =
      case assigns.variant do
        :primary ->
          "bg-accent text-white border-accent font-semibold [box-shadow:0_1px_2px_rgba(59,122,224,.3)] hover:bg-[#3169c8] hover:border-[#3169c8]"

        :secondary ->
          "bg-card text-inkSoft border-borderStrong font-semibold [box-shadow:var(--shadow)] hover:bg-paperAlt hover:text-ink"
      end

    assigns =
      assign(assigns,
        classes:
          "inline-flex items-center gap-2 border rounded-[8px] cursor-pointer transition-all disabled:opacity-40 disabled:cursor-not-allowed disabled:pointer-events-none #{pad} #{color}"
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
      <div
        :if={@kicker}
        class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold mb-3"
      >
        {@kicker}
      </div>
      <h1 class="font-semibold text-[25px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0 text-ink text-pretty">
        {render_slot(@inner_block)}
      </h1>
      <div :if={@sub} class="mt-4 text-[14px] leading-[1.5] text-inkSoft max-w-[520px] text-pretty">
        {@sub}
      </div>
    </div>
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
      assigns
      |> assign_new(:resolved_active, fn ->
        assigns.active || step_to_active(assigns.step)
      end)
      |> assign(:panic_on, derive_panic_on(assigns))

    ~H"""
    <div class={["min-h-screen bg-canvas text-ink", !@landing && "md:flex"]}>
      <div
        :if={!@landing}
        id="liid-nav-backdrop"
        class="hidden fixed inset-0 z-40 bg-black/40 md:hidden"
        phx-click={close_nav()}
      />
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
        <.mobile_top_bar :if={!@landing} campaign={@campaign} />
        <div
          :if={@panic_on}
          class="px-6 py-2.5 bg-red text-white text-[11px] tracking-[0.06em] uppercase flex items-center gap-3 border-b border-red"
        >
          <span class="inline-block w-[7px] h-[7px] rounded-full bg-white animate-[liid-pulse_1.4s_ease-in-out_infinite]" />
          <span class="font-semibold tracking-[0.12em]">Sending halted</span>
        </div>
        <main class={["flex-1 px-4 py-6 md:px-14 md:py-10", @class]}>
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  @doc """
  Mobile-only top bar: hamburger (opens the nav drawer) + Liid wordmark +
  optional campaign name. Hidden at md+ where the static sidebar is shown.
  """
  attr :campaign, :any, default: nil

  def mobile_top_bar(assigns) do
    ~H"""
    <header class="md:hidden sticky top-0 z-30 flex items-center gap-3 px-4 py-2.5 border-b border-border bg-canvas">
      <button
        type="button"
        phx-click={open_nav()}
        aria-label={gettext("Open menu")}
        class="shrink-0 -ml-1 p-1.5 text-inkSoft hover:text-ink cursor-pointer bg-transparent border-0"
      >
        <.icon name="menu" size={20} />
      </button>
      <.link navigate="/" class="flex items-center gap-2.5 no-underline text-ink shrink-0">
        <span class="w-[26px] h-[26px] rounded-[7px] bg-accent text-white flex items-center justify-center font-bold text-[15px]">
          L
        </span>
        <span class="text-[18px] font-bold tracking-[-0.01em]">Liid</span>
      </.link>
      <span
        :if={@campaign}
        class="ml-1 min-w-0 truncate text-[14px] font-semibold text-inkSoft"
      >
        {@campaign.name}
      </span>
    </header>
    """
  end

  attr :current_user, :map, default: nil

  def landing_top_bar(assigns) do
    ~H"""
    <header class="flex items-center gap-6 px-4 md:px-8 py-4 border-b border-border bg-bgSoft">
      <.link navigate="/" class="flex items-center gap-2.5 no-underline text-ink shrink-0">
        <span class="w-[26px] h-[26px] rounded-[7px] bg-accent text-white flex items-center justify-center font-bold text-[15px]">
          L
        </span>
        <span class="text-[18px] font-bold tracking-[-0.01em]">Liid</span>
      </.link>

      <div class="flex-1" />

      <div class="flex items-center gap-2">
        <.link
          navigate="/pricing"
          class="text-[12px] font-medium text-inkSoft hover:text-ink no-underline px-2"
        >
          {gettext("Pricing")}
        </.link>
        <.language_picker />
        <%= if @current_user do %>
          <.link
            navigate="/campaigns"
            class="text-[12px] font-medium text-inkSoft hover:text-ink no-underline border border-borderStrong rounded-[8px] px-3 py-1.5"
          >
            {gettext("Campaigns")}
          </.link>
          <.link
            href="/sign-out"
            method="get"
            class="text-[12px] font-medium text-inkSoft hover:text-ink no-underline border border-borderStrong rounded-[8px] px-3 py-1.5"
          >
            {gettext("Sign out")}
          </.link>
        <% else %>
          <.link
            href="/sign-in"
            class="text-[12px] font-medium text-inkSoft hover:text-ink no-underline border border-borderStrong rounded-[8px] px-3 py-1.5"
          >
            {gettext("Sign in")}
          </.link>
        <% end %>
      </div>
    </header>
    """
  end

  @locales [
    {"en", "English"},
    {"et", "Eesti"},
    {"lv", "Latviešu"},
    {"lt", "Lietuvių"},
    {"fi", "Suomi"},
    {"sv", "Svenska"},
    {"nb", "Norsk"},
    {"da", "Dansk"},
    {"is", "Íslenska"}
  ]

  def language_picker(assigns) do
    assigns =
      assign_new(assigns, :current, fn ->
        Gettext.get_locale(ColtWeb.Gettext)
      end)
      |> assign(:locales, @locales)

    ~H"""
    <details class="relative" data-component="language-picker">
      <summary class="list-none cursor-pointer text-[12px] font-medium uppercase tracking-[0.04em] text-inkSoft hover:text-ink border border-borderStrong rounded-[8px] px-3 py-1.5">
        {@current}
      </summary>
      <div class="absolute right-0 mt-1 z-50 bg-card border border-border rounded-[8px] min-w-[160px] [box-shadow:var(--shadow-card)] p-1">
        <form :for={{code, label} <- @locales} action="/locale" method="post" class="block">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="locale" value={code} />
          <button
            type="submit"
            class={[
              "w-full text-left text-[12px] font-medium px-2.5 py-1.5 rounded-[8px]",
              "bg-transparent border-0 cursor-pointer hover:bg-paperAlt hover:text-ink",
              code == @current && "text-accent bg-accentSoft",
              code != @current && "text-inkSoft"
            ]}
          >
            <span class="inline-block w-6 uppercase tracking-[0.04em] text-inkFaint">{code}</span>
            <span>{label}</span>
          </button>
        </form>
      </div>
    </details>
    """
  end

  defp derive_panic_on(%{campaign: %{panic_switch_on: v}}) when is_boolean(v), do: v
  defp derive_panic_on(%{panic_on: v}) when is_boolean(v), do: v
  defp derive_panic_on(_), do: false

  defp step_to_active(nil), do: nil
  defp step_to_active(0), do: :campaigns
  defp step_to_active(1), do: :icp
  defp step_to_active(2), do: :market
  defp step_to_active(3), do: :filters
  defp step_to_active(4), do: :exclude
  defp step_to_active(5), do: :target
  defp step_to_active(6), do: :enrichment_funnel
  defp step_to_active(_), do: nil

  @enrichment_items [
    %{id: :name, icon: "file"},
    %{id: :market, icon: "globe"},
    %{id: :filters, icon: "filter"},
    %{id: :icp, icon: "user"},
    %{id: :exclude, icon: "x"},
    %{id: :target, icon: "spark"},
    %{id: :enrichment_funnel, icon: "grid"}
  ]

  @sending_items [
    %{id: :pitch, icon: "spark"},
    %{id: :sending_accounts, icon: "mail"},
    %{id: :write, icon: "spark"},
    %{id: :sending_funnel, icon: "grid"},
    %{id: :variants, icon: "code"},
    %{id: :settings, icon: "file"}
  ]

  @sales_items [
    %{id: :sales_setup, icon: "filter"},
    %{id: :sales_funnel, icon: "grid"}
  ]

  defp nav_label(:campaigns), do: gettext("Campaigns")
  defp nav_label(:email_accounts), do: gettext("Email accounts")
  defp nav_label(:billing), do: gettext("Billing")
  defp nav_label(:name), do: gettext("Name")
  defp nav_label(:icp), do: gettext("ICP")
  defp nav_label(:market), do: gettext("Market")
  defp nav_label(:filters), do: gettext("Filters")
  defp nav_label(:exclude), do: gettext("Exclude")
  defp nav_label(:target), do: gettext("Target")
  defp nav_label(:enrichment_funnel), do: gettext("Enrichment funnel")
  defp nav_label(:pitch), do: gettext("Pitch")
  defp nav_label(:sequence), do: gettext("Sequence")
  defp nav_label(:sending_accounts), do: gettext("Sending accounts")
  defp nav_label(:writing), do: gettext("Writing")
  defp nav_label(:sending_funnel), do: gettext("Sending funnel")
  defp nav_label(:write), do: gettext("Write")
  defp nav_label(:variants), do: gettext("Variants")
  defp nav_label(:settings), do: gettext("Settings")
  defp nav_label(:sales_setup), do: gettext("Setup")
  defp nav_label(:sales_funnel), do: gettext("Sales funnel")

  attr :active, :atom, default: nil
  attr :current_user, :map, default: nil
  attr :campaign, :any, default: nil
  attr :campaign_id, :any, default: nil
  attr :campaign_name, :string, default: nil
  attr :panic_on, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <aside
      id="liid-sidebar"
      class="fixed inset-y-0 left-0 z-50 w-[248px] -translate-x-full transition-transform duration-200 ease-out md:translate-x-0 md:transition-none md:sticky md:top-0 md:self-start md:h-screen md:z-auto shrink-0 border-r border-border bg-bgSoft flex flex-col"
    >
      <div class="px-[22px] pt-[18px] pb-3.5 flex items-center gap-2.5">
        <.link
          navigate="/"
          class="flex items-center no-underline text-ink"
          phx-click={close_nav()}
        >
          <span class="text-[18px] font-bold tracking-[-0.01em]">Liid</span>
        </.link>
        <.link
          navigate="/search"
          phx-click={close_nav()}
          aria-label={gettext("Search")}
          class="ml-auto inline-flex items-center gap-1.5 px-2.5 h-[30px] rounded-[8px] no-underline text-[12px] font-semibold text-inkSoft hover:text-ink hover:bg-paperAlt border border-transparent hover:border-border transition-colors"
        >
          {gettext("Search")} <.icon name="search" size={14} />
        </.link>
        <button
          type="button"
          phx-click={close_nav()}
          aria-label={gettext("Close menu")}
          class="md:hidden -mr-1 p-1 text-inkSoft hover:text-ink cursor-pointer bg-transparent border-0"
        >
          <.icon name="x" size={18} />
        </button>
      </div>

      <div class="flex-1 overflow-auto px-2">
        <.usage_badge :if={@current_user} user={@current_user} />

        <.campaign_scope_header campaign={@campaign} active={@active} />

        <.sidebar_section
          :if={@campaign}
          label={gettext("Enrichment")}
          items={enrichment_items_with_hrefs(@campaign_id)}
          active={@active}
        />

        <.sidebar_section
          :if={@campaign}
          label={gettext("Sending")}
          items={sending_items_with_hrefs(@campaign_id)}
          active={@active}
        >
          <:header_extra>
            <.live_component
              module={ColtWeb.Components.AutoApproveToggle}
              id={"auto-approve-#{@campaign.id}"}
              campaign={@campaign}
              current_user={@current_user}
            />
          </:header_extra>
        </.sidebar_section>

        <.sidebar_section
          :if={@campaign && @current_user && @current_user.is_admin}
          label={gettext("Sales")}
          items={sales_items_with_hrefs(@campaign_id)}
          active={@active}
        >
          <:header_extra>
            <.admin_badge label={gettext("Admin")} />
          </:header_extra>
        </.sidebar_section>
      </div>

      <div :if={@current_user} class="border-t border-border pt-2.5 px-2 pb-2">
        <.link
          navigate="/email-accounts"
          phx-click={close_nav()}
          class={[
            "flex items-center gap-2.5 px-2.5 py-1.5 rounded-[8px] hover:bg-paperAlt no-underline",
            if(@active == :email_accounts,
              do:
                "text-accent font-semibold bg-accentSoft [box-shadow:inset_0_0_0_1px_var(--accentRing)]",
              else: "text-inkSoft hover:text-ink"
            )
          ]}
        >
          <.icon name="mail" size={13} class="text-inkFaint" />
          <span class="text-[13px]">{gettext("Email accounts")}</span>
        </.link>
        <.link
          navigate="/billing"
          phx-click={close_nav()}
          class={[
            "flex items-center gap-2.5 px-2.5 py-1.5 rounded-[8px] hover:bg-paperAlt no-underline",
            if(@active == :billing,
              do:
                "text-accent font-semibold bg-accentSoft [box-shadow:inset_0_0_0_1px_var(--accentRing)]",
              else: "text-inkSoft hover:text-ink"
            )
          ]}
        >
          <.icon name="file" size={13} class="text-inkFaint" />
          <span class="text-[13px]">{gettext("Billing")}</span>
        </.link>
        <button
          type="button"
          phx-click={open_feedback()}
          class="w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-[8px] text-left text-inkSoft hover:text-ink hover:bg-paperAlt cursor-pointer bg-transparent border-0"
        >
          <.icon name="mail" size={13} class="text-inkFaint" />
          <span class="text-[13px]">{gettext("Feedback")}</span>
        </button>
        <.link
          :if={@current_user.is_admin}
          href="/admin"
          class="flex items-center gap-2.5 px-2.5 py-1.5 rounded-[8px] text-inkSoft hover:text-ink hover:bg-paperAlt no-underline"
        >
          <.icon name="code" size={13} class="text-inkFaint" />
          <span class="text-[13px]">{gettext("Admin")}</span>
        </.link>
        <div class="flex items-center gap-2.5 px-2.5 pt-2.5 mt-1">
          <div
            class="w-[26px] h-[26px] rounded-full bg-[#e7e1d8] text-[#7a6f5f] flex items-center justify-center text-[12px] font-semibold shrink-0"
            title={to_string(@current_user.email)}
          >
            {avatar_initial(@current_user)}
          </div>
          <div class="text-[12.5px] font-medium text-inkSoft truncate flex-1">
            {to_string(@current_user.email)}
          </div>
          <.link
            href="/sign-out"
            method="get"
            title={gettext("Sign out")}
            class="shrink-0 text-inkFaint hover:text-ink no-underline"
          >
            <.icon name="logout" size={14} />
          </.link>
        </div>
      </div>
      <div :if={!@current_user} class="border-t border-border px-[18px] py-3.5">
        <.link
          href="/sign-in"
          class="text-[12px] font-medium uppercase tracking-[0.04em] text-inkSoft hover:text-ink no-underline"
        >
          {gettext("sign in")}
        </.link>
      </div>
    </aside>
    """
  end

  @doc """
  Golden chip marking an admin-only feature — the house convention for
  features that are gated to admins now but slated to ship to everyone later.
  Gate the surrounding markup on `@current_user.is_admin`; this only renders
  the badge.
  """
  attr :label, :string, default: "Admin"

  def admin_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-[3px] rounded-[6px] bg-goldSoft text-gold">
      {@label}
    </span>
    """
  end

  @doc """
  Centered modal dialog — Calm-Pro card over a dimmed backdrop. Render it
  conditionally from the host (`<Liid.modal :if={@open} …>`); it closes on
  backdrop click, the ✕, and Escape, each pushing the `on_cancel` event, which
  the host handles. Body goes in the default slot; actions in `:footer`.
  """
  attr :id, :string, default: nil
  attr :on_cancel, :string, required: true, doc: "event pushed on backdrop / ✕ / Escape"
  attr :eyebrow, :string, default: nil
  attr :title, :string, default: nil
  attr :max_width, :string, default: "max-w-[460px]"
  slot :inner_block, required: true
  slot :footer

  def modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style="background: rgba(20,18,14,0.45); backdrop-filter: blur(2px);"
    >
      <div
        id={@id}
        class={[
          "bg-card border border-border rounded-[11px] w-full my-auto px-6 py-6 md:px-7 md:py-7",
          @max_width
        ]}
        style="box-shadow: 0 24px 80px rgba(0,0,0,0.18);"
        phx-click-away={@on_cancel}
        phx-window-keydown={@on_cancel}
        phx-key="escape"
      >
        <div :if={@eyebrow || @title} class="flex justify-between items-start gap-3 mb-4">
          <div class="min-w-0">
            <div
              :if={@eyebrow}
              class="text-[10px] tracking-[0.12em] uppercase text-inkFaint font-semibold mb-1.5 truncate"
            >
              {@eyebrow}
            </div>
            <h2
              :if={@title}
              class="font-semibold text-[18px] md:text-[20px] leading-[1.2] tracking-[-0.01em] m-0 text-ink"
            >
              {@title}
            </h2>
          </div>
          <button
            type="button"
            phx-click={@on_cancel}
            aria-label={gettext("Close")}
            class="shrink-0 w-6 h-6 flex items-center justify-center cursor-pointer text-inkFaint hover:text-ink bg-transparent border-0"
          >
            <.icon name="x" size={14} />
          </button>
        </div>

        {render_slot(@inner_block)}

        <div :if={@footer != []} class="mt-5 flex items-center gap-3 justify-end">
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end

  @doc false
  attr :user, :map, required: true

  def usage_badge(assigns) do
    assigns = assign(assigns, :usage, usage_state(assigns.user))

    ~H"""
    <div :if={@usage.state != :hidden} class="px-1.5 pb-2">
      <.link
        navigate="/pricing"
        phx-click={close_nav()}
        class="block no-underline bg-card border border-border rounded-[8px] px-2.5 py-2 [box-shadow:var(--shadow)] hover:bg-bgSoft"
      >
        <%= case @usage.state do %>
          <% :none -> %>
            <span class="text-[12px] font-medium text-inkSoft">{gettext("Pick a plan")} →</span>
          <% _ -> %>
            <div class="flex items-baseline justify-between gap-2">
              <div class="text-[10px] tracking-[0.08em] uppercase font-semibold text-inkFaint">
                {gettext("Left this period")}
              </div>
              <span
                :if={@usage.state == :exhausted}
                class="text-[10px] tracking-[0.04em] uppercase font-semibold text-amber"
              >
                {gettext("upgrade")} →
              </span>
            </div>
            <div class="mt-1.5 flex items-baseline gap-4">
              <.usage_metric label={gettext("contacts")} value={@usage.contacts} />
              <.usage_metric label={gettext("screenings")} value={@usage.screening} />
            </div>
        <% end %>
      </.link>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp usage_metric(assigns) do
    ~H"""
    <div class="flex items-baseline gap-1">
      <span class="text-[15px] font-bold text-ink tabular-nums tracking-[-0.02em]">{@value}</span>
      <span class="text-[11px] text-inkFaint">{@label}</span>
    </div>
    """
  end

  # Derives the sidebar usage chip state from a (possibly unloaded) user.
  #   :none      — no active paid plan → prompt to pick one
  #   :exhausted — paid but a cap is used up → red, link to upgrade
  #   :ok        — paid, capacity remaining
  #   :hidden    — usage calcs not loaded (e.g. admin pages) → render nothing
  defp usage_state(user) do
    contacts = safe_int(Map.get(user, :remaining_capacity))
    screening = safe_int(Map.get(user, :remaining_screening))

    cond do
      Map.get(user, :is_admin) == true ->
        %{state: :hidden}

      not User.paid?(user) ->
        %{state: :none}

      is_nil(contacts) or is_nil(screening) ->
        %{state: :hidden}

      contacts <= 0 or screening <= 0 ->
        %{state: :exhausted, contacts: max(contacts, 0), screening: max(screening, 0)}

      true ->
        %{state: :ok, contacts: contacts, screening: screening}
    end
  end

  defp safe_int(n) when is_integer(n), do: n
  defp safe_int(_), do: nil

  defp enrichment_items_with_hrefs(nil), do: @enrichment_items

  defp enrichment_items_with_hrefs(id) do
    Enum.map(@enrichment_items, fn item -> Map.put(item, :href, enrichment_href(item.id, id)) end)
  end

  defp sending_items_with_hrefs(nil), do: @sending_items

  defp sending_items_with_hrefs(id) do
    Enum.map(@sending_items, fn item -> Map.put(item, :href, sending_href(item.id, id)) end)
  end

  defp sales_items_with_hrefs(nil), do: @sales_items

  defp sales_items_with_hrefs(id) do
    Enum.map(@sales_items, fn item -> Map.put(item, :href, sales_href(item.id, id)) end)
  end

  defp enrichment_href(:name, id), do: "/campaigns/#{id}/name"
  defp enrichment_href(:icp, id), do: "/campaigns/#{id}/icp"
  defp enrichment_href(:market, id), do: "/campaigns/#{id}/market"
  defp enrichment_href(:filters, id), do: "/campaigns/#{id}/filters"
  defp enrichment_href(:exclude, id), do: "/campaigns/#{id}/suppression"
  defp enrichment_href(:target, id), do: "/campaigns/#{id}/target"
  defp enrichment_href(:enrichment_funnel, id), do: "/campaigns/#{id}/funnel"

  defp sending_href(:pitch, id), do: "/campaigns/#{id}/pitch"
  defp sending_href(:write, id), do: "/campaigns/#{id}/write"
  defp sending_href(:variants, id), do: "/campaigns/#{id}/variants"
  defp sending_href(:settings, id), do: "/campaigns/#{id}/settings"
  defp sending_href(:sending_accounts, id), do: "/campaigns/#{id}/sending-accounts"
  defp sending_href(:sending_funnel, id), do: "/campaigns/#{id}/sending-funnel"

  defp sales_href(:sales_setup, id), do: "/campaigns/#{id}/sales/setup"
  defp sales_href(:sales_funnel, id), do: "/campaigns/#{id}/sales"

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
        class="px-2.5 py-1 mb-0.5 flex items-center justify-between"
      >
        <span class="text-[10.5px] tracking-[0.09em] uppercase font-semibold text-inkFaint">
          {@label}
        </span>
        <span :if={@header_extra != []}>{render_slot(@header_extra)}</span>
      </div>
      <div>
        <%= for item <- @items do %>
          <% is_active = item.id == @active %>
          <.link
            navigate={item.href}
            phx-click={close_nav()}
            class={[
              "flex items-center gap-2.5 px-2.5 py-1.5 rounded-[8px] no-underline",
              if(is_active,
                do:
                  "bg-accentSoft text-accent font-semibold [box-shadow:inset_0_0_0_1px_var(--accentRing)]",
                else: "text-inkSoft hover:bg-paperAlt hover:text-ink"
              )
            ]}
          >
            <.icon
              name={item.icon}
              size={13}
              class={if(is_active, do: "text-accent", else: "text-inkFaint")}
            />
            <span class="text-[13.5px]">
              {nav_label(item.id)}
            </span>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :campaign, :any, default: nil
  attr :active, :atom, default: nil

  defp campaign_scope_header(assigns) do
    ~H"""
    <div class="mx-1.5 mb-3.5 px-2.5 py-2 bg-accentSoft border border-accentRing rounded-[8px]">
      <div class="flex items-center justify-between mb-0.5">
        <span class="flex items-center gap-1.5 text-[10.5px] tracking-[0.08em] uppercase font-semibold text-accent">
          <.status_dot state={:done} size={6} />
          {gettext("Campaign")}
        </span>
        <.link
          :if={@campaign}
          navigate="/campaigns"
          phx-click={close_nav()}
          class="text-[10.5px] tracking-[0.08em] uppercase font-semibold text-inkSoft hover:text-accent no-underline"
        >
          {gettext("Change")} →
        </.link>
      </div>
      <.link
        navigate="/campaigns"
        phx-click={close_nav()}
        class="block text-[13px] font-semibold leading-[1.2] truncate no-underline hover:opacity-80"
      >
        <span :if={@campaign} class="text-ink">{@campaign.name}</span>
        <span
          :if={!@campaign}
          class={if(@active == :campaigns, do: "text-accent", else: "text-inkSoft")}
        >
          {gettext("Choose campaign")} →
        </span>
      </.link>
    </div>
    """
  end
end
