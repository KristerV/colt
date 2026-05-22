defmodule ColtWeb.Components.Liid do
  @moduledoc """
  Liid design-system function components.

  Source of truth for visuals is `priv/design_prototype/project/liid-shared.jsx`.
  Tokens and keyframes are defined in `assets/css/app.css`.
  """
  use Phoenix.Component

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
            onclick="window.openFeedback()"
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
  Outer screen wrapper — paper background, comfy density padding, top bar slot.
  """
  attr :step, :any, default: nil
  attr :current_user, :map, default: nil
  attr :campaign_name, :string, default: nil
  attr :campaign_id, :any, default: nil
  attr :campaign, :any, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def screen(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-paper text-ink">
      <.top_bar
        step={@step}
        current_user={@current_user}
        campaign_name={@campaign_name}
        campaign_id={@campaign_id}
        campaign={@campaign}
      />
      <main class={["flex-1 px-4 py-6 md:px-14 md:py-10", @class]}>
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end
end
