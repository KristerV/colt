defmodule ColtWeb.PricingLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.BillingComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Pricing"),
       prices: BillingComponents.configured_prices()
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas text-ink antialiased">
      <.top_nav current_user={@current_user} />

      <header class="pt-[74px] pb-2 text-center">
        <div class="max-w-[1120px] mx-auto px-8">
          <div class="text-[12px] font-semibold uppercase tracking-[0.08em] text-accent mb-3">
            {gettext("Pricing")}
          </div>
          <h1 class="text-[50px] leading-[1.05] font-bold tracking-[-0.03em] max-w-[740px] mx-auto mb-[18px]">
            {raw(gettext("One price for the <em>whole</em> funnel."))}
          </h1>
          <p class="text-[18px] text-inkSoft max-w-[620px] mx-auto mb-7 font-[450] leading-[1.5]">
            {gettext(
              "Pick a monthly contact cap. We screen thousands of companies to find them, then draft, sequence and send from your own inboxes — ICP scoring, AI drafting, multi-domain sending and follow-ups included."
            )}
          </p>
        </div>
      </header>

      <section class="pt-[42px] pb-[66px]">
        <div class="max-w-[1120px] mx-auto px-8">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-5 items-start">
            <.tier
              name={gettext("Starter")}
              price="€49"
              desc={gettext("For testing your first list.")}
              mode={mode(@current_user)}
              price_id={@prices[:starter]}
            >
              <:feature>{raw(gettext("<b>50</b> contacts / month"))}</:feature>
              <:feature>{raw(gettext("Up to <b>1,000</b> screened / month"))}</:feature>
              <:feature>{gettext("ICP AI matching")}</:feature>
              <:feature>{gettext("Multi-domain sending")}</:feature>
              <:feature>{gettext("Reply handling & sequences")}</:feature>
            </.tier>

            <.tier
              name={gettext("Growth")}
              price="€159"
              desc={gettext("For a running outbound motion.")}
              popular
              mode={mode(@current_user)}
              price_id={@prices[:growth]}
            >
              <:feature>{raw(gettext("<b>200</b> contacts / month"))}</:feature>
              <:feature>{raw(gettext("Up to <b>4,000</b> screened / month"))}</:feature>
              <:feature>{gettext("ICP AI matching")}</:feature>
              <:feature>{gettext("Multi-domain sending")}</:feature>
              <:feature>{gettext("Working-hour scheduling")}</:feature>
            </.tier>

            <.tier
              name={gettext("Scale")}
              price="€699"
              desc={gettext("For volume across markets.")}
              mode={mode(@current_user)}
              price_id={@prices[:scale]}
            >
              <:feature>{raw(gettext("<b>1,000</b> contacts / month"))}</:feature>
              <:feature>{raw(gettext("Up to <b>20,000</b> screened / month"))}</:feature>
              <:feature>{gettext("ICP AI matching")}</:feature>
              <:feature>{gettext("Multi-domain sending")}</:feature>
              <:feature>{gettext("Priority reply funneling")}</:feature>
            </.tier>
          </div>

          <p class="text-center text-[12.5px] text-inkFaint mt-6 font-medium">
            {gettext("Prices are in EUR, excl. VAT. Cancel any time from the billing portal.")}
          </p>
        </div>
      </section>

      <.site_footer />
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end

  defp mode(nil), do: :public
  defp mode(_user), do: :authed

  ## ---------- shared bits (mirrors HomeLive l0 nav/footer) ----------

  defp logo_sq(assigns) do
    assigns = assign_new(assigns, :size, fn -> 26 end)
    assigns = assign_new(assigns, :radius, fn -> 7 end)
    assigns = assign_new(assigns, :font, fn -> 15 end)

    ~H"""
    <span
      class="grid place-items-center bg-accent text-white font-bold shrink-0"
      style={"width:#{@size}px;height:#{@size}px;border-radius:#{@radius}px;font-size:#{@font}px;box-shadow:var(--shadow);"}
    >
      L
    </span>
    """
  end

  attr :current_user, :map, default: nil

  defp top_nav(assigns) do
    ~H"""
    <nav
      class="sticky top-0 z-50 border-b border-border"
      style="background:rgba(247,247,245,.82);backdrop-filter:blur(10px);"
    >
      <div class="max-w-[1180px] mx-auto px-8 py-[13px] flex items-center gap-7">
        <.link
          navigate={~p"/"}
          class="flex items-center gap-[9px] font-semibold text-[18px] tracking-[-0.02em] no-underline text-ink"
        >
          <.logo_sq /> Liid
        </.link>
        <div class="hidden md:flex gap-6 ml-2">
          <.link
            navigate={~p"/"}
            class="text-[14px] text-inkSoft font-[450] hover:text-ink no-underline"
          >
            {gettext("Product")}
          </.link>
          <.link
            navigate={~p"/#how"}
            class="text-[14px] text-inkSoft font-[450] hover:text-ink no-underline"
          >
            {gettext("How it works")}
          </.link>
          <.link navigate={~p"/pricing"} class="text-[14px] text-ink font-medium no-underline">
            {gettext("Pricing")}
          </.link>
        </div>
        <div class="ml-auto flex items-center gap-3.5">
          <ColtWeb.Components.Liid.language_picker />
          <.link
            :if={is_nil(@current_user)}
            navigate={~p"/sign-in"}
            class="text-[14px] text-inkSoft font-medium hover:text-ink no-underline"
          >
            {gettext("Sign in")}
          </.link>
          <.link
            navigate={primary_path(@current_user)}
            class="inline-flex items-center justify-center gap-[7px] rounded-[8px] px-4 py-[9px] text-[14px] font-medium bg-accent text-white border border-transparent no-underline hover:bg-[#2f6acb] transition-colors"
            style="box-shadow:var(--shadow);"
          >
            {gettext("Start a campaign")}
          </.link>
        </div>
      </div>
    </nav>
    """
  end

  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :desc, :string, required: true
  attr :popular, :boolean, default: false
  attr :mode, :atom, required: true
  attr :price_id, :string, default: nil
  slot :feature, required: true

  defp tier(assigns) do
    ~H"""
    <div
      class={[
        "bg-card border rounded-[11px] px-6 py-[26px] relative",
        @popular && "border-accent",
        !@popular && "border-border"
      ]}
      style={
        if @popular,
          do: "box-shadow:0 0 0 4px var(--accentSoft),var(--shadow-card);",
          else: "box-shadow:var(--shadow);"
      }
    >
      <span
        :if={@popular}
        class="absolute -top-[11px] left-6 bg-accent text-white text-[11px] font-semibold px-2.5 py-[3px] rounded-full tracking-[0.02em]"
        style="box-shadow:var(--shadow);"
      >
        {gettext("Most popular")}
      </span>
      <div class="text-[15px] font-semibold tracking-[-0.01em] mb-1.5">{@name}</div>
      <div class="text-[36px] font-bold tracking-[-0.03em] tabular-nums">
        {@price}<small class="text-[15px] font-[450] text-inkFaint">{gettext("/mo")}</small>
      </div>
      <div class="text-[13px] text-inkFaint mt-1 mb-5">{@desc}</div>
      <ul class="flex flex-col gap-2.5 mb-[22px]">
        <li
          :for={f <- @feature}
          class="text-[13.5px] text-inkSoft flex items-start gap-2.5 leading-[1.45] [&_b]:text-ink [&_b]:font-semibold [&_b]:tabular-nums"
        >
          <span class="text-green flex-none mt-0.5">✓</span>
          <span>{render_slot(f)}</span>
        </li>
      </ul>
      <.checkout_cta mode={@mode} price_id={@price_id} popular={@popular} />
    </div>
    """
  end

  attr :mode, :atom, required: true
  attr :price_id, :string, default: nil
  attr :popular, :boolean, default: false

  defp checkout_cta(%{mode: :authed, price_id: price_id} = assigns) when is_binary(price_id) do
    ~H"""
    <form action={~p"/billing/checkout"} method="post" class="contents">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="price_id" value={@price_id} />
      <button type="submit" class={cta_class(@popular)} style={cta_style(@popular)}>
        {gettext("Start a campaign")}
      </button>
    </form>
    """
  end

  defp checkout_cta(%{mode: :public} = assigns) do
    ~H"""
    <.link navigate={~p"/sign-in"} class={cta_class(@popular)} style={cta_style(@popular)}>
      {gettext("Start a campaign")}
    </.link>
    """
  end

  defp checkout_cta(assigns) do
    ~H"""
    <span class="block text-center text-[12px] text-inkFaint font-medium py-[9px]">
      {gettext("unavailable")}
    </span>
    """
  end

  defp cta_class(true) do
    "w-full inline-flex items-center justify-center gap-[7px] rounded-[8px] px-4 py-[9px] text-[14px] font-medium no-underline cursor-pointer transition-colors bg-accent text-white border border-transparent hover:bg-[#2f6acb]"
  end

  defp cta_class(false) do
    "w-full inline-flex items-center justify-center gap-[7px] rounded-[8px] px-4 py-[9px] text-[14px] font-medium no-underline cursor-pointer transition-colors bg-card text-inkSoft border border-borderStrong hover:border-inkFaint hover:text-ink"
  end

  defp cta_style(true), do: "box-shadow:var(--shadow);"
  defp cta_style(false), do: nil

  defp site_footer(assigns) do
    ~H"""
    <footer class="border-t border-border bg-bgSoft pt-12 pb-9">
      <div class="max-w-[1120px] mx-auto px-8">
        <div class="grid grid-cols-1 md:grid-cols-[1.6fr_1fr_1fr_1fr] gap-10 mb-9">
          <div>
            <.link
              navigate={~p"/"}
              class="flex items-center gap-[9px] font-semibold text-[18px] tracking-[-0.02em] no-underline text-ink mb-3"
            >
              <.logo_sq /> Liid
            </.link>
            <p class="text-[13px] text-inkFaint max-w-[280px] leading-[1.55]">
              {gettext(
                "Verified B2B contact lists and personalized email sequences from your own inbox. Lead gen for the Baltics and Nordics."
              )}
            </p>
          </div>
          <.foot_col title={gettext("Product")}>
            <:link_item href={~p"/#full"}>{gettext("Sending funnel")}</:link_item>
            <:link_item href={~p"/#how"}>{gettext("Filters")}</:link_item>
            <:link_item href={~p"/#how"}>{gettext("Enrichment")}</:link_item>
            <:link_item href={~p"/#how"}>{gettext("Reply handling")}</:link_item>
          </.foot_col>
          <.foot_col title={gettext("Company")}>
            <:link_item href={~p"/pricing"}>{gettext("Pricing")}</:link_item>
            <:link_item href="mailto:liid@krister.ee">{gettext("Contact")}</:link_item>
          </.foot_col>
          <.foot_col title={gettext("Legal")}>
            <:link_item href={~p"/privacy"}>{gettext("Privacy")}</:link_item>
            <:link_item href={~p"/terms"}>{gettext("Terms")}</:link_item>
          </.foot_col>
        </div>
        <div class="flex items-center gap-4 pt-6 border-t border-border text-[13px] text-inkFaint flex-wrap">
          <span>© {DateTime.utc_now().year} Liid</span>
          <span class="ml-auto tabular-nums">
            {gettext("Data from national business registries, synced nightly.")}
          </span>
        </div>
      </div>
    </footer>
    """
  end

  attr :title, :string, required: true

  slot :link_item, required: true do
    attr :href, :string
  end

  defp foot_col(assigns) do
    ~H"""
    <div>
      <h4 class="text-[12px] uppercase tracking-[0.06em] text-inkFaint font-semibold mb-3.5">
        {@title}
      </h4>
      <a
        :for={item <- @link_item}
        href={item.href}
        class="block text-[13.5px] text-inkSoft mb-2.5 font-[450] hover:text-ink no-underline"
      >
        {render_slot(item)}
      </a>
    </div>
    """
  end

  defp primary_path(nil), do: ~p"/sign-in"
  defp primary_path(_user), do: ~p"/campaigns/new"
end
