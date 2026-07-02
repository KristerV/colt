defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Liid — all-in-one lead gen for the Baltics and Nordics")
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas text-ink antialiased">
      <.top_nav current_user={@current_user} />
      <.hero current_user={@current_user} />
      <.funnel />
      <.full_picture />
      <.walkthrough />
      <.comparison />
      <.one_tool />
      <.pricing current_user={@current_user} />
      <.final_cta current_user={@current_user} />
      <.site_footer />
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end

  ## ---------- shared bits ----------

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

  defp live_dot(assigns) do
    ~H"""
    <span class="relative inline-flex w-2 h-2">
      <span class="w-2 h-2 rounded-full bg-green relative z-[1]" />
      <span class="absolute inset-0 rounded-full bg-green animate-[liid-pulse_1.8s_infinite]" />
    </span>
    """
  end

  ## ---------- nav ----------

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
          <a href="#full" class="text-[14px] text-inkSoft font-[450] hover:text-ink no-underline">
            {gettext("Product")}
          </a>
          <a href="#how" class="text-[14px] text-inkSoft font-[450] hover:text-ink no-underline">
            {gettext("How it works")}
          </a>
          <.link
            navigate={~p"/pricing"}
            class="text-[14px] text-inkSoft font-[450] hover:text-ink no-underline"
          >
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
          <.cta_button navigate={primary_path(@current_user)}>
            {primary_label(@current_user)}
          </.cta_button>
        </div>
      </div>
    </nav>
    """
  end

  attr :navigate, :string, required: true
  attr :large, :boolean, default: false
  slot :inner_block, required: true

  defp cta_button(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "inline-flex items-center justify-center gap-[7px] rounded-[8px] font-medium",
        "bg-accent text-white border border-transparent no-underline whitespace-nowrap",
        "transition-colors hover:bg-[#2f6acb]",
        @large && "px-[22px] py-3 text-[15px]",
        !@large && "px-4 py-[9px] text-[14px]"
      ]}
      style="box-shadow:var(--shadow);"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  ## ---------- hero ----------

  attr :current_user, :map, default: nil

  defp hero(assigns) do
    ~H"""
    <header class="pt-[74px] pb-2 text-center">
      <div class="max-w-[1120px] mx-auto px-8">
        <h1 class="text-[50px] leading-[1.05] font-bold tracking-[-0.03em] max-w-[740px] mx-auto mb-[18px]">
          {raw(gettext("Lead gen for the Baltics and <em>Nordics</em>."))}
        </h1>
        <p class="text-[18px] text-inkSoft max-w-[600px] mx-auto mb-7 font-[450] leading-[1.5]">
          {gettext("Find who fits, reach them in your voice — and we'll even make the calls.")}
        </p>
        <div class="flex gap-3 justify-center items-center flex-wrap">
          <.cta_button navigate={primary_path(@current_user)} large>
            {primary_label(@current_user)}
          </.cta_button>
          <a
            href="#how"
            class="inline-flex items-center justify-center gap-[7px] rounded-[8px] px-[22px] py-3 text-[15px] font-medium bg-card text-inkSoft border border-borderStrong no-underline hover:border-inkFaint hover:text-ink transition-colors"
          >
            {gettext("See how it works")}
          </a>
        </div>
      </div>
    </header>
    """
  end

  ## ---------- hero 4-step funnel ----------

  defp funnel(assigns) do
    ~H"""
    <section class="pt-[42px] pb-14">
      <div class="max-w-[1180px] mx-auto px-8">
        <div class="flex items-stretch justify-center gap-0 flex-col md:flex-row">
          <.pstep no="1" tone={:accent} label={gettext("Filter")} value="300k">
            {gettext("government companies")}
          </.pstep>

          <.pchevron />

          <.pstep no="2" label={gettext("Enrich")} value="10k">
            {gettext("enriched contacts")}
          </.pstep>

          <.pchevron />

          <.pstep no="3" label={gettext("AI checks")} value="2,400">
            {raw(gettext("match <em>your</em> ICP"))}
          </.pstep>

          <.pchevron />

          <.pstep no="4" tone={:accent} label={gettext("Send")} value="2,400">
            {raw(gettext("emails in <em>your</em> voice"))}
          </.pstep>

          <.pchevron />

          <.pstep no="5" tone={:green} label={gettext("Reply")} value="160">
            {gettext("interested leads")}
          </.pstep>
        </div>
      </div>
    </section>
    """
  end

  attr :no, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :atom, default: :plain
  slot :inner_block, required: true

  defp pstep(assigns) do
    ~H"""
    <div
      class={[
        "flex-1 min-w-0 bg-card border rounded-[11px] px-[18px] pt-4 pb-[18px] text-center flex flex-col items-center gap-2.5",
        @tone == :accent && "border-accentRing",
        @tone == :green && "border-[#bfe6d2]",
        @tone == :plain && "border-border"
      ]}
      style="box-shadow:var(--shadow-card);"
    >
      <div class="text-[11px] font-bold tracking-[0.1em] uppercase text-inkFaint flex items-center gap-2">
        <span class={[
          "w-5 h-5 rounded-[6px] grid place-items-center text-[11px] font-bold tabular-nums border",
          @tone == :green && "bg-greenSoft text-green border-[#bfe6d2]",
          @tone != :green && "bg-accentSoft text-accent border-accentRing"
        ]}>
          {@no}
        </span>
        {@label}
      </div>
      <div class={[
        "text-[40px] font-bold tracking-[-0.03em] tabular-nums leading-none mt-0.5",
        @tone == :accent && "text-accent",
        @tone == :green && "text-green",
        @tone == :plain && "text-ink"
      ]}>
        {@value}
      </div>
      <div class="text-[14px] text-inkSoft font-[450] leading-[1.3]">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp pchevron(assigns) do
    ~H"""
    <div class="shrink-0 w-9 grid place-items-center text-accentRing rotate-90 md:rotate-0">
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="w-[18px] h-[18px]"
      >
        <path d="M9 5l7 7-7 7" />
      </svg>
    </div>
    """
  end

  ## ---------- section header ----------

  attr :kicker, :string, required: true
  slot :title, required: true
  slot :inner_block, required: true

  defp sec_head(assigns) do
    ~H"""
    <div class="text-center max-w-[640px] mx-auto mb-9">
      <div class="text-[12px] font-semibold uppercase tracking-[0.08em] text-accent mb-3">
        {@kicker}
      </div>
      <h2 class="text-[36px] font-bold tracking-[-0.025em] leading-[1.1] mb-3">
        {render_slot(@title)}
      </h2>
      <p class="text-[16px] text-inkSoft leading-[1.5]">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  ## ---------- the full picture (app mock) ----------

  defp full_picture(assigns) do
    ~H"""
    <section id="full" class="pt-[46px] pb-14">
      <div class="max-w-[1120px] mx-auto px-8">
        <.sec_head kicker={gettext("The full picture")}>
          <:title>{raw(gettext("Everything you need for cold <em>outreach</em>."))}</:title>
          {gettext(
            "The whole funnel — targeting, enrichment, sending and replies — lives in a single view. No spreadsheet, no five-tool stack."
          )}
        </.sec_head>
      </div>
      <div class="max-w-[1180px] mx-auto px-8">
        <div
          class="bg-card border border-border rounded-[11px] overflow-hidden"
          style="box-shadow:var(--shadow-card);"
        >
          <div class="flex items-center gap-[7px] px-4 py-[11px] border-b border-border bg-bgSoft">
            <span class="w-[11px] h-[11px] rounded-full" style="background:#e0b3ad;" />
            <span class="w-[11px] h-[11px] rounded-full" style="background:#ecd6a3;" />
            <span class="w-[11px] h-[11px] rounded-full" style="background:#bfe6d2;" />
            <span class="ml-2.5 flex-1 max-w-[420px] bg-card border border-border rounded-[6px] text-[12px] text-inkFaint px-3 py-[5px] tabular-nums">
              app.liid.io/campaigns/fendr-icp/sending
            </span>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-[188px_1fr] min-h-[560px]">
            <aside class="border-b md:border-b-0 md:border-r border-border bg-bgSoft p-4 flex flex-col gap-5">
              <div class="flex items-center gap-2 font-semibold text-[15px] tracking-[-0.02em] px-1 py-0.5">
                <.logo_sq size={22} radius={6} font={13} /> Liid
              </div>
              <div>
                <div class="text-[11px] uppercase tracking-[0.07em] text-inkFaint font-semibold px-2 mb-1.5">
                  {gettext("Enrichment")}
                </div>
                <.side_link label={gettext("Targeting")} />
                <.side_link label={gettext("Filters")} />
                <.side_link label={gettext("Funnel")} />
              </div>
              <div>
                <div class="text-[11px] uppercase tracking-[0.07em] text-inkFaint font-semibold px-2 mb-1.5">
                  {gettext("Sending")}
                </div>
                <.side_link label={gettext("Sequences")} active />
                <.side_link label={gettext("Replies")} />
                <.side_link label={gettext("Inboxes")} />
              </div>
            </aside>

            <div class="p-[18px] md:px-5 overflow-hidden">
              <div class="flex items-center gap-3 mb-4 flex-wrap">
                <h3 class="text-[17px] font-semibold tracking-[-0.02em]">
                  {gettext("Sending — Fendr ICP")}
                </h3>
                <span class="text-[12px] text-inkFaint tabular-nums">
                  {gettext("312 in sequence")}
                </span>
                <span class="ml-auto inline-flex items-center gap-1.5 text-[12.5px] font-medium px-2.5 py-[3px] rounded-full bg-greenSoft border border-[#bfe6d2] text-green">
                  <.live_dot /> {gettext("Auto-approve on")}
                </span>
              </div>

              <div class="grid grid-cols-3 lg:grid-cols-6 gap-[9px] mb-[18px]">
                <.stat label={gettext("Sending")} value="312" tone={:accent} live />
                <.stat label={gettext("Call ready")} value="8" dot="accent" />
                <.stat label={gettext("Interested")} value="23" dot="green" />
                <.stat label={gettext("Not interested")} value="141" dot="faint" />
                <.stat label={gettext("Failed")} value="4" dot="amber" />
                <.stat label={gettext("Bounced")} value="6" dot="red" />
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-[300px_1fr] gap-4">
                <div class="bg-card border border-border rounded-[8px] overflow-hidden">
                  <div class="px-3.5 py-2.5 border-b border-border text-[12.5px] font-semibold text-inkSoft flex items-center gap-2 bg-bgSoft">
                    <span class="w-[7px] h-[7px] rounded-full bg-green" />
                    {gettext("Replied · Interested")}
                    <span class="ml-auto text-[11.5px] text-inkFaint font-medium tabular-nums">
                      23
                    </span>
                  </div>
                  <.crow
                    initials="MT"
                    name="Mart Tamm"
                    who={gettext("CEO · Fendr")}
                    step="Step 3/4"
                    reply={gettext("replied · interested")}
                    selected
                  />
                  <.crow
                    initials="LK"
                    name="Liis Kask"
                    who={gettext("Founder · Voolt")}
                    step="Step 4/4"
                    reply={gettext("replied · interested")}
                  />
                  <.crow
                    initials="JO"
                    name="Jaan Org"
                    who={gettext("CTO · Pinta")}
                    step="Step 2/4"
                    reply={gettext("replied · interested")}
                  />
                  <.crow
                    initials="KP"
                    name="Kadri Põld"
                    who={gettext("Head of Sales · Roov")}
                    step="Step 3/4"
                    reply={gettext("call ready")}
                    reply_tone={:accent}
                  />
                </div>

                <div class="bg-card border border-border rounded-[8px] overflow-hidden">
                  <div class="px-3.5 py-2.5 border-b border-border text-[12.5px] font-semibold text-inkSoft flex items-center gap-2 bg-bgSoft">
                    <span class="w-[7px] h-[7px] rounded-full bg-green" />
                    {gettext("Mart Tamm — Fendr")}
                    <span class="ml-auto text-[11.5px] text-inkFaint font-medium">
                      {gettext("paused on reply")}
                    </span>
                  </div>
                  <div class="p-3.5 flex flex-col gap-3">
                    <div class="border border-border rounded-[8px] overflow-hidden bg-card">
                      <div class="px-3 py-2.5 border-b border-border flex items-center gap-2 bg-bgSoft">
                        <span class="text-[11px] font-semibold text-inkFaint tabular-nums">
                          {gettext("Step 1 · You")}
                        </span>
                        <span class="text-[12.5px] font-semibold">{gettext("Sent")}</span>
                        <span class="ml-auto text-[11px] text-inkFaint tabular-nums">
                          Jun 14 · 09:12
                        </span>
                      </div>
                      <div class="p-3">
                        <div class="text-[13.5px] font-semibold tracking-[-0.01em] mb-2">
                          {gettext("Quick question about Fendr's onboarding")}
                        </div>
                        <p class="text-[13px] text-inkSoft leading-[1.6] mb-2">
                          {gettext(
                            "Hi Mart — noticed Fendr's been hiring on the ops side this quarter. We help Estonian SaaS teams pull verified buyer contacts straight from the registry instead of guessing."
                          )}
                        </p>
                        <p class="text-[13px] text-inkSoft leading-[1.6]">
                          {gettext("Worth a 15-minute look at how your onboarding funnel maps to it?")}
                        </p>
                      </div>
                    </div>
                    <div class="border border-[#bfe6d2] rounded-[8px] overflow-hidden bg-card">
                      <div class="px-3 py-2.5 border-b border-border flex items-center gap-2 bg-greenSoft">
                        <span class="text-[11px] font-semibold text-inkFaint tabular-nums">
                          {gettext("Reply")}
                        </span>
                        <span class="text-[12.5px] font-semibold text-green">Mart Tamm</span>
                        <span class="ml-auto text-[11px] text-inkFaint tabular-nums">
                          Jun 15 · 08:40
                        </span>
                      </div>
                      <div class="p-3">
                        <p class="text-[13px] text-inkSoft leading-[1.6]">
                          {gettext(
                            "Timing's good, actually — we're rebuilding outbound right now. Send over a slot for next week and I'll bring our growth lead."
                          )}
                        </p>
                      </div>
                    </div>
                    <span class="self-start inline-flex items-center gap-1.5 text-[12.5px] font-medium px-2.5 py-[3px] rounded-full bg-greenSoft border border-[#bfe6d2] text-green">
                      <span class="w-[7px] h-[7px] rounded-full bg-green" />
                      {gettext("Sequence paused · sorted into Interested")}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp side_link(assigns) do
    ~H"""
    <span class={[
      "flex items-center gap-2.5 text-[13.5px] font-[450] px-2 py-1.5 rounded-[6px]",
      @active && "bg-accentSoft text-accent font-medium",
      !@active && "text-inkSoft"
    ]}>
      <span class={[
        "w-[15px] h-[15px] rounded-[4px] shrink-0",
        @active && "bg-accent/30",
        !@active && "bg-ink20"
      ]} />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :atom, default: :plain
  attr :dot, :string, default: nil
  attr :live, :boolean, default: false

  defp stat(assigns) do
    ~H"""
    <div class={[
      "border rounded-[8px] px-3 py-[11px]",
      @tone == :accent && "border-accentRing bg-accentSoft",
      @tone != :accent && "border-border bg-card"
    ]}>
      <div class="text-[11.5px] text-inkSoft font-medium flex items-center gap-1.5 mb-1.5">
        <.live_dot :if={@live} />
        <span :if={@dot} class={["w-[7px] h-[7px] rounded-full", dot_class(@dot)]} />
        {@label}
      </div>
      <div class={[
        "text-[23px] font-semibold tracking-[-0.02em] tabular-nums",
        @tone == :accent && "text-accent"
      ]}>
        {@value}
      </div>
    </div>
    """
  end

  defp dot_class("accent"), do: "bg-accent"
  defp dot_class("green"), do: "bg-green"
  defp dot_class("amber"), do: "bg-amber"
  defp dot_class("red"), do: "bg-red"
  defp dot_class("faint"), do: "bg-inkFaint"

  attr :initials, :string, required: true
  attr :name, :string, required: true
  attr :who, :string, required: true
  attr :step, :string, required: true
  attr :reply, :string, required: true
  attr :reply_tone, :atom, default: :green
  attr :selected, :boolean, default: false

  defp crow(assigns) do
    ~H"""
    <div class={[
      "px-3.5 py-[11px] border-b border-border last:border-b-0 flex items-center gap-2.5",
      @selected && "bg-accentSoft"
    ]}>
      <div class={[
        "w-[30px] h-[30px] rounded-[7px] grid place-items-center text-[12px] font-semibold shrink-0",
        @selected && "bg-[#dbe7fa] text-accent",
        !@selected && "bg-[#eceae6] text-inkSoft"
      ]}>
        {@initials}
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-[13.5px] font-medium tracking-[-0.01em]">{@name}</div>
        <div class="text-[11.5px] text-inkFaint flex items-center gap-1.5 mt-px">
          <span>{@who}</span>·<span class="tabular-nums">{@step}</span>
        </div>
      </div>
      <div class={[
        "text-[10.5px] font-medium flex items-center gap-1.5 whitespace-nowrap",
        @reply_tone == :accent && "text-accent",
        @reply_tone == :green && "text-green"
      ]}>
        <span class={[
          "w-[6px] h-[6px] rounded-full",
          @reply_tone == :accent && "bg-accent",
          @reply_tone == :green && "bg-green"
        ]} />
        {@reply}
      </div>
    </div>
    """
  end

  ## ---------- walkthrough spine ----------

  defp walkthrough(assigns) do
    ~H"""
    <section id="how" class="pt-[54px] pb-[30px]">
      <div class="max-w-[1120px] mx-auto px-8">
        <.sec_head kicker={gettext("How it works")}>
          <:title>
            {raw(gettext("From a sentence about your customer to <em>booked calls</em>."))}
          </:title>
          {gettext("Step by step. Clean data in. The right people on the phone.")}
        </.sec_head>

        <div class="relative max-w-[960px] mx-auto md:pl-[62px]">
          <div
            class="hidden md:block absolute left-[21px] top-3.5 bottom-[34px] w-0.5"
            style="background:linear-gradient(to bottom,var(--accentRing),var(--accentRing) 92%,transparent);"
          />

          <.wstep num="01" title={gettext("Describe who you sell to.")}>
            <:desc>
              {raw(
                gettext(
                  "Write it in <strong>plain English</strong> and name a job title. That's what the AI judges fit against — no keyword juggling."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Ideal customer")}</div>
              <div class="bg-card border border-border rounded-[8px] overflow-hidden mb-3">
                <div class="px-3.5 py-2 border-b border-border text-[11px] text-inkFaint font-medium tracking-[0.03em] uppercase bg-bgSoft">
                  {gettext("Who you sell to")}
                </div>
                <div class="px-3.5 py-3 text-[13.5px] text-inkSoft leading-[1.5]">
                  {gettext(
                    "B2B SaaS selling to enterprise, 10–50 people, raised a seed round, struggling to scale outbound from a tiny founding team"
                  )}<span class="border-r-2 border-accent pr-px animate-[liid-blink_1.1s_steps(1)_infinite]" />
                </div>
              </div>
              <span class="wchip-accent">{gettext("Target title: CTO")}</span>
            </:visual>
          </.wstep>

          <.wstep num="02" title={gettext("Pick your market.")}>
            <:desc>
              {raw(
                gettext(
                  "Straight from <strong>national business registries</strong> across the Baltics &amp; Nordics — fresh, official company data, not a resold list."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Registry")}</div>
              <div class="bg-card border border-border rounded-[8px] overflow-hidden">
                <.prow country={gettext("Estonia")} on />
                <.prow country={gettext("Finland")} />
                <.prow country={gettext("Latvia")} />
                <.prow country={gettext("Lithuania")} />
                <.prow country={gettext("Sweden")} />
                <.prow country={gettext("Norway")} />
              </div>
            </:visual>
          </.wstep>

          <.wstep num="03" title={gettext("Narrow by the numbers that matter.")}>
            <:desc>
              {raw(
                gettext(
                  "Revenue, employees, industry, growth — the <strong>count updates as you drag</strong>. You're in control of exactly who's left."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Filters")}</div>
              <div class="flex flex-col gap-[15px]">
                <.fctrl
                  name={gettext("Revenue")}
                  value="€1M – €10M"
                  left="18%"
                  width="42%"
                  right="60%"
                />
                <.fctrl
                  name={gettext("Employees")}
                  value="10 – 50"
                  left="12%"
                  width="33%"
                  right="45%"
                />
                <div class="flex items-center justify-between bg-card border border-borderStrong rounded-[8px] px-3 py-2 text-[13px] text-ink">
                  <span>{gettext("Industry: SaaS")}</span>
                  <span class="text-inkFaint text-[11px]">▾</span>
                </div>
                <div class="flex items-center gap-2.5 bg-accentSoft border border-accentRing rounded-[8px] px-3.5 py-[11px] mt-[3px]">
                  <span class="text-[24px] font-bold text-accent tracking-[-0.02em] tabular-nums leading-none">
                    10,000
                  </span>
                  <span class="text-[12.5px] text-inkSoft">{gettext("companies match")}</span>
                </div>
              </div>
            </:visual>
          </.wstep>

          <.wstep num="04" title={gettext("Real contacts, checked twice.")}>
            <:desc>
              {raw(
                gettext(
                  "Contacts come <strong>from the company's own site</strong>, with the registry synced nightly — fresh and correct, not a years-old dump."
                )
              )}
            </:desc>
            <:desc>
              {raw(
                gettext(
                  "And the AI checks each company <strong>actually fits your ICP</strong>, so you only ever email real prospects."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Enriched contacts")}</div>
              <div class="flex flex-col gap-[9px]">
                <.erow initials="MT" name="Mart Tamm" meta="CEO · Fendr OÜ" />
                <.erow initials="LK" name="Liis Kask" meta="Founder · Voolt AS" />
                <.erow initials="JO" name="Jaan Org" meta="CTO · Pinta OÜ" />
              </div>
            </:visual>
          </.wstep>

          <.wstep num="05" title={gettext("Sequenced in your voice.")}>
            <:desc>
              {raw(
                gettext(
                  "<strong>The AI learns from a few of your emails</strong> and drafts the whole sequence. It sends across multiple inboxes on a human schedule — and a reply pauses it."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Sequence")}</div>
              <div class="flex flex-col">
                <.seq_step no="1" text={gettext("Email 1 — intro")} chip={gettext("in your voice")} />
                <.seq_wait label={gettext("wait 3 days")} />
                <.seq_step no="2" text={gettext("Email 2 — follow-up")} />
                <.seq_wait label={gettext("wait 4 days")} />
                <.seq_step no="3" text={gettext("Email 3 — last touch")} />
              </div>
              <div class="flex items-center gap-2 mt-3">
                <span class="wchip-accent">{gettext("Drafted in your voice")}</span>
                <span class="wchip">
                  <span class="w-[7px] h-[7px] rounded-full bg-green" /> {gettext("3 inboxes")}
                </span>
              </div>
            </:visual>
          </.wstep>

          <.wstep num="06" title={gettext("We'll even make the calls.")}>
            <:desc>
              {raw(
                gettext(
                  "<strong>A real person calls your interested leads</strong> — to book the meeting, refine your offer, and sharpen your ICP from real conversations."
                )
              )}
            </:desc>
            <:visual>
              <div class="vlabel">{gettext("Call queue")}</div>
              <div class="bg-card border border-border rounded-[8px] overflow-hidden">
                <div class="flex items-center gap-3 p-3.5">
                  <div class="w-7 h-7 rounded-[7px] bg-[#eceae6] text-inkSoft grid place-items-center text-[12px] font-semibold shrink-0">
                    MT
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[14px] font-semibold tracking-[-0.01em]">Mart Tamm · CEO</div>
                    <div class="text-[12px] text-inkFaint mt-px">Fendr OÜ</div>
                  </div>
                  <span class="w-[38px] h-[38px] rounded-[9px] bg-greenSoft border border-[#bfe6d2] text-green grid place-items-center shrink-0">
                    <svg
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.8"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      class="w-[18px] h-[18px]"
                    >
                      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" />
                    </svg>
                  </span>
                </div>
                <div class="flex items-center gap-2.5 px-3.5 py-[11px] border-t border-border bg-bgSoft">
                  <span class="text-[12px] font-medium text-inkSoft">
                    {gettext("Discovery call · refine the offer")}
                  </span>
                  <span class="ml-auto text-[11.5px] text-inkFaint tabular-nums">
                    {gettext("Tue · 14:00")}
                  </span>
                </div>
              </div>
            </:visual>
          </.wstep>
        </div>
      </div>
    </section>
    """
  end

  attr :num, :string, required: true
  attr :title, :string, required: true
  slot :desc, required: true
  slot :visual, required: true

  defp wstep(assigns) do
    ~H"""
    <div class="relative mb-[30px]">
      <div
        class="hidden md:grid absolute left-[-62px] top-0 w-11 h-11 rounded-full bg-card border-2 border-accentRing place-items-center font-bold text-[13px] text-accent z-[2] tabular-nums"
        style="box-shadow:var(--shadow);"
      >
        {@num}
      </div>
      <div
        class="bg-card border border-border rounded-[11px] px-6 py-[22px]"
        style="box-shadow:var(--shadow-card);"
      >
        <div class="grid grid-cols-1 md:grid-cols-[1fr_1.05fr] gap-7 items-center">
          <div>
            <div class="text-[12px] font-semibold text-accent tracking-[0.04em] tabular-nums">
              {gettext("STEP")} {@num}
            </div>
            <div class="text-[20px] font-semibold tracking-[-0.02em] mt-0.5 mb-[7px]">{@title}</div>
            <p
              :for={d <- @desc}
              class="text-inkSoft text-[14.5px] leading-[1.55] [&_strong]:text-ink [&_strong]:font-semibold [&+p]:mt-2.5"
            >
              {render_slot(d)}
            </p>
          </div>
          <div class="bg-bgSoft border border-border rounded-[8px] p-4 [&_.vlabel]:text-[11px] [&_.vlabel]:font-semibold [&_.vlabel]:text-inkFaint [&_.vlabel]:tracking-[0.05em] [&_.vlabel]:uppercase [&_.vlabel]:mb-[11px]
            [&_.wchip]:inline-flex [&_.wchip]:items-center [&_.wchip]:gap-1.5 [&_.wchip]:text-[12.5px] [&_.wchip]:font-medium [&_.wchip]:px-[11px] [&_.wchip]:py-[5px] [&_.wchip]:rounded-[7px] [&_.wchip]:bg-card [&_.wchip]:border [&_.wchip]:border-border [&_.wchip]:text-inkSoft [&_.wchip]:tabular-nums
            [&_.wchip-accent]:inline-flex [&_.wchip-accent]:items-center [&_.wchip-accent]:gap-1.5 [&_.wchip-accent]:text-[12.5px] [&_.wchip-accent]:font-medium [&_.wchip-accent]:px-[11px] [&_.wchip-accent]:py-[5px] [&_.wchip-accent]:rounded-[7px] [&_.wchip-accent]:bg-accentSoft [&_.wchip-accent]:border [&_.wchip-accent]:border-accentRing [&_.wchip-accent]:text-accent
            [&_.wchip-green]:inline-flex [&_.wchip-green]:items-center [&_.wchip-green]:gap-1.5 [&_.wchip-green]:text-[12.5px] [&_.wchip-green]:font-medium [&_.wchip-green]:px-[11px] [&_.wchip-green]:py-[5px] [&_.wchip-green]:rounded-[7px] [&_.wchip-green]:bg-greenSoft [&_.wchip-green]:border [&_.wchip-green]:border-[#bfe6d2] [&_.wchip-green]:text-green">
            {render_slot(@visual)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :country, :string, required: true
  attr :on, :boolean, default: false

  attr :count, :string, default: nil

  defp prow(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-2.5 px-3.5 py-2.5 border-b border-border last:border-b-0 text-[13.5px]",
      @on && "bg-accentSoft"
    ]}>
      <span class={[
        "w-[15px] h-[15px] rounded-full border-[1.5px] flex-none grid place-items-center",
        @on && "border-accent",
        !@on && "border-[#9ed3b8]"
      ]}>
        <span class={["w-[7px] h-[7px] rounded-full", @on && "bg-accent", !@on && "bg-green"]} />
      </span>
      <span class={["", @on && "font-medium text-ink", !@on && "text-ink font-[450]"]}>
        {@country}
      </span>
      <span class="ml-auto text-[11.5px] font-medium tabular-nums flex items-center gap-1.5">
        <span :if={@count} class="text-ink tabular-nums">{@count}</span>
        <span class="text-inkFaint font-[450]">
          {if @count, do: gettext("active"), else: gettext("available")}
        </span>
      </span>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :left, :string, required: true
  attr :width, :string, required: true
  attr :right, :string, required: true

  defp fctrl(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-baseline mb-2">
        <span class="text-[12.5px] font-medium text-inkSoft">{@name}</span>
        <span class="text-[12.5px] font-semibold text-ink tabular-nums">{@value}</span>
      </div>
      <div class="relative h-[5px] rounded-full bg-border">
        <div
          class="absolute top-0 h-[5px] rounded-full bg-accent"
          style={"left:#{@left};width:#{@width};"}
        />
        <div
          class="absolute top-1/2 w-[15px] h-[15px] rounded-full bg-card border-2 border-accent -translate-y-1/2 -translate-x-1/2"
          style={"left:#{@left};box-shadow:var(--shadow);"}
        />
        <div
          class="absolute top-1/2 w-[15px] h-[15px] rounded-full bg-card border-2 border-accent -translate-y-1/2 -translate-x-1/2"
          style={"left:#{@right};box-shadow:var(--shadow);"}
        />
      </div>
    </div>
    """
  end

  attr :initials, :string, required: true
  attr :name, :string, required: true
  attr :meta, :string, required: true

  defp erow(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 bg-card border border-border rounded-[8px] px-3.5 py-2.5">
      <div class="w-7 h-7 rounded-[7px] bg-[#eceae6] text-inkSoft grid place-items-center text-[12px] font-semibold shrink-0">
        {@initials}
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-[13px] font-medium tracking-[-0.01em]">{@name}</div>
        <div class="text-[11.5px] text-inkFaint mt-px">{@meta}</div>
      </div>
      <div class="flex gap-1.5 flex-none">
        <span class="wchip-green"><span class="font-bold">✓</span>{gettext("ICP fit")}</span>
        <span class="wchip-green"><span class="font-bold">✓</span>{gettext("Verified")}</span>
      </div>
    </div>
    """
  end

  attr :no, :string, required: true
  attr :text, :string, required: true
  attr :chip, :string, default: nil

  defp seq_step(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 bg-card border border-border rounded-[8px] px-3.5 py-2.5">
      <span class="w-[22px] h-[22px] rounded-[6px] bg-accentSoft border border-accentRing text-accent text-[11px] font-bold grid place-items-center shrink-0 tabular-nums">
        {@no}
      </span>
      <span class="text-[13px] font-medium text-ink">{@text}</span>
      <span
        :if={@chip}
        class="ml-auto text-[11px] font-medium text-accent bg-accentSoft border border-accentRing rounded-[6px] px-2 py-0.5"
      >
        {@chip}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true

  defp seq_wait(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 py-1.5 pl-[11px] text-inkFaint text-[11.5px] tabular-nums before:content-[''] before:w-px before:h-3.5 before:bg-borderStrong before:ml-2.5">
      {@label}
    </div>
    """
  end

  ## ---------- comparison table ----------

  defp comparison(assigns) do
    ~H"""
    <section class="pt-9 pb-14">
      <div class="max-w-[1120px] mx-auto px-8">
        <.sec_head kicker={gettext("The old way")}>
          <:title>
            {raw(gettext("What it takes to land 100 prospects that <em>actually fit</em>."))}
          </:title>
          {gettext("The same campaign, three ways.")}
        </.sec_head>

        <div
          class="bg-card border border-border rounded-[11px] overflow-hidden overflow-x-auto"
          style="box-shadow:var(--shadow-card);"
        >
          <table class="w-full border-collapse text-[14px] min-w-[680px]">
            <thead>
              <tr>
                <th class="px-5 py-4 text-left align-bottom text-[12px] tracking-[0.06em] uppercase text-inkFaint font-semibold">
                  {gettext("Task")}
                </th>
                <th class="px-5 py-4 text-left align-bottom text-inkSoft text-[14px] border-l border-border w-[250px] font-semibold">
                  {gettext("By hand")}<small class="block font-[450] text-inkFaint text-[12px] mt-0.5">{gettext("Google + spreadsheets")}</small>
                </th>
                <th class="px-5 py-4 text-left align-bottom text-inkSoft text-[14px] border-l border-border w-[250px] font-semibold">
                  {gettext("Apollo + automation tools")}<small class="block font-[450] text-inkFaint text-[12px] mt-0.5">{gettext("a stitched stack")}</small>
                </th>
                <th class="px-5 py-4 text-left align-bottom w-[250px] bg-accentSoft border-l border-b border-accentRing">
                  <span class="flex items-center gap-2 text-[16px] text-accent font-bold tracking-[-0.02em]">
                    <.logo_sq size={22} radius={6} font={13} /> Liid
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <.cmp_row
                task={gettext("Find companies in your market")}
                a={gettext("Google + lists, copy-paste")}
                b={gettext("Thin, stale Baltic & Nordic data")}
                liid={gettext("Straight from the national registry")}
              />
              <.cmp_row
                task={gettext("Match them to your ICP")}
                a={gettext("Read every website yourself")}
                b={gettext("Still manual — Apollo gives contacts, not fit")}
                liid={gettext("AI reads each site, keeps only the fits")}
              />
              <.cmp_row
                task={gettext("Find contacts & emails")}
                a={gettext("Dig through each site")}
                b={gettext("Often missing or out of date")}
                liid={gettext("From the company's own site")}
              />
              <.cmp_row
                task={gettext("Verify deliverability")}
                a={gettext("Yet another export")}
                b={gettext("Bolt on MillionVerifier / NeverBounce")}
                liid={gettext("Verified before you send — built in")}
              />
              <.cmp_row
                task={gettext("Write personalized emails")}
                a={gettext("One by one")}
                b={gettext("Templated — quality tanks")}
                liid={gettext("AI in your voice; you approve")}
              />
              <.cmp_row
                task={gettext("Send & follow up")}
                a={gettext("Manual, one inbox")}
                b={gettext("A separate sequencer (Instantly, Smartlead)")}
                liid={gettext("Multi-inbox sequences, human schedule")}
              />
              <.cmp_row
                task={gettext("Call the prospects")}
                a={gettext("If you find the time")}
                b={gettext("Not their job")}
                liid={gettext("We make the calls for you")}
              />
              <tr>
                <td class="px-5 py-3 align-top font-semibold text-ink text-[14.5px] border-t-2 border-borderStrong bg-bgSoft w-[240px]">
                  {gettext("Total")}
                </td>
                <td class="px-5 py-3 align-top border-t-2 border-borderStrong bg-bgSoft border-l border-border font-semibold text-inkSoft tabular-nums">
                  {gettext("Weeks")}
                </td>
                <td class="px-5 py-3 align-top border-t-2 border-borderStrong bg-bgSoft border-l border-border font-semibold text-inkSoft tabular-nums">
                  {gettext("Days · 4–5 tools")}
                </td>
                <td class="px-5 py-3 align-top border-t-2 border-borderStrong border-l border-accentRing bg-accentSoft font-semibold text-accent tabular-nums">
                  {gettext("Hours · one tool")}
                </td>
              </tr>
            </tbody>
          </table>
          <div class="px-5 py-3.5 border-t border-border bg-bgSoft text-[12.5px] text-inkFaint">
            {gettext("Illustrative, for landing ~100 prospects that match your ICP.")}
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :task, :string, required: true
  attr :a, :string, required: true
  attr :b, :string, required: true
  attr :liid, :string, required: true

  defp cmp_row(assigns) do
    ~H"""
    <tr>
      <td class="px-5 py-3.5 border-t border-border align-top font-medium text-ink w-[240px]">
        {@task}
      </td>
      <td class="px-5 py-3.5 border-t border-border align-top border-l border-border text-inkSoft">
        {@a}
      </td>
      <td class="px-5 py-3.5 border-t border-border align-top border-l border-border text-inkSoft">
        {@b}
      </td>
      <td
        class="px-5 py-3.5 border-t border-border align-top border-l border-accentRing"
        style="background:#f6f9fe;"
      >
        <span class="inline-flex items-start gap-2">
          <span class="inline-grid place-items-center w-[18px] h-[18px] rounded-[5px] bg-greenSoft text-green text-[11px] font-bold shrink-0 mt-px">
            ✓
          </span>
          <span class="text-ink font-medium leading-[1.4]">{@liid}</span>
        </span>
      </td>
    </tr>
    """
  end

  ## ---------- one tool, not five ----------

  defp one_tool(assigns) do
    ~H"""
    <section class="pt-[46px] pb-14">
      <div class="max-w-[1120px] mx-auto px-8">
        <.sec_head kicker={gettext("One login")}>
          <:title>{raw(gettext("One tool, not <em>five</em>."))}</:title>
          {gettext("Liid does the whole job — here's the stack it replaces.")}
        </.sec_head>

        <div class="grid grid-cols-1 md:grid-cols-[1fr_0.92fr] gap-[26px] items-center">
          <div>
            <div class="flex flex-col gap-2.5">
              <.ot_tool job={gettext("Prospecting & data")} svc="Apollo, ZoomInfo" />
              <.ot_tool job={gettext("Enrichment")} svc="Clay" />
              <.ot_tool job={gettext("Email verification")} svc="MillionVerifier" />
              <.ot_tool job={gettext("Sequencer + inboxes")} svc="Instantly, Smartlead" />
              <.ot_tool job={gettext("Calling")} svc={gettext("an SDR or agency")} />
            </div>
            <div class="text-[12.5px] text-inkFaint mt-[3px] pl-0.5">
              {gettext("+ the spreadsheet, the VA, and the copy-paste between them.")}
            </div>
          </div>

          <div
            class="bg-accentSoft border border-accentRing rounded-[11px] px-7 py-[30px] relative"
            style="box-shadow:0 0 0 4px rgba(59,122,224,.07),var(--shadow-card);"
          >
            <div class="flex items-center gap-2.5 text-[20px] font-bold tracking-[-0.02em] text-accent mb-3.5">
              <.logo_sq size={30} radius={7} font={17} /> Liid
            </div>
            <p class="text-[16px] text-ink leading-[1.55] font-[450]">
              <strong class="font-semibold">
                {gettext(
                  "Finds, fits, verifies, writes, sequences across inboxes — and makes the calls."
                )}
              </strong>
            </p>
            <span class="mt-4 inline-flex items-center gap-[7px] text-[13px] font-semibold text-accent bg-card border border-accentRing rounded-full px-3 py-[5px]">
              <span class="w-[7px] h-[7px] rounded-full bg-green" /> {gettext("One login")}
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :job, :string, required: true
  attr :svc, :string, required: true

  defp ot_tool(assigns) do
    ~H"""
    <div class="flex items-center gap-3 bg-bgSoft border border-border rounded-[8px] px-3.5 py-3 opacity-[0.82]">
      <span class="w-5 h-5 rounded-[5px] bg-[#efeeec] text-inkFaint grid place-items-center text-[11px] font-bold shrink-0">
        ✕
      </span>
      <div>
        <div class="text-[13.5px] font-medium text-inkSoft">{@job}</div>
        <div class="text-[12px] text-inkFaint mt-px">{@svc}</div>
      </div>
    </div>
    """
  end

  ## ---------- pricing ----------

  attr :current_user, :map, default: nil

  defp pricing(assigns) do
    ~H"""
    <section id="pricing" class="py-[50px]">
      <div class="max-w-[1120px] mx-auto px-8">
        <.sec_head kicker={gettext("Pricing")}>
          <:title>{raw(gettext("One price for the <em>whole</em> funnel."))}</:title>
          {gettext(
            "Targeting, enrichment, sending and reply handling included on every plan. EUR, excl. VAT. Cancel anytime."
          )}
        </.sec_head>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-5 items-start">
          <.tier
            name={gettext("Starter")}
            price="€49"
            desc={gettext("For testing your first list.")}
            navigate={primary_path(@current_user)}
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
            navigate={primary_path(@current_user)}
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
            navigate={primary_path(@current_user)}
          >
            <:feature>{raw(gettext("<b>1,000</b> contacts / month"))}</:feature>
            <:feature>{raw(gettext("Up to <b>20,000</b> screened / month"))}</:feature>
            <:feature>{gettext("ICP AI matching")}</:feature>
            <:feature>{gettext("Multi-domain sending")}</:feature>
            <:feature>{gettext("Priority reply funneling")}</:feature>
          </.tier>
        </div>

        <p class="text-center text-[12.5px] text-inkFaint mt-6">
          {gettext(
            "All plans include ICP AI matching, multi-domain sending, reply handling, and sequences with working-hour scheduling."
          )}
        </p>
      </div>
    </section>
    """
  end

  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :desc, :string, required: true
  attr :popular, :boolean, default: false
  attr :navigate, :string, required: true
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
      <.link
        navigate={@navigate}
        class={[
          "w-full inline-flex items-center justify-center gap-[7px] rounded-[8px] px-4 py-[9px] text-[14px] font-medium no-underline transition-colors",
          @popular && "bg-accent text-white border border-transparent hover:bg-[#2f6acb]",
          !@popular &&
            "bg-card text-inkSoft border border-borderStrong hover:border-inkFaint hover:text-ink"
        ]}
        style={if @popular, do: "box-shadow:var(--shadow);", else: nil}
      >
        {gettext("Start a campaign")}
      </.link>
    </div>
    """
  end

  ## ---------- final CTA ----------

  attr :current_user, :map, default: nil

  defp final_cta(assigns) do
    ~H"""
    <section class="pt-5 pb-[66px]">
      <div class="max-w-[1120px] mx-auto px-8">
        <div
          class="rounded-[11px] px-10 py-[54px] text-center text-white"
          style="background:linear-gradient(135deg,#37352f,#2c2a25);box-shadow:var(--shadow-card);"
        >
          <h2 class="text-[38px] font-bold tracking-[-0.025em] mb-3 text-white [&_em]:text-[#8fb6f2] [&_em]:not-italic">
            {raw(gettext("Stop sending to <em>dead</em> inboxes."))}
          </h2>
          <p class="text-[16px] max-w-[480px] mx-auto mb-6" style="color:rgba(255,255,255,.7);">
            {gettext(
              "Verified contacts from fresh registry data, screened by AI, sent in your voice — and we make the calls."
            )}
          </p>
          <.link
            navigate={primary_path(@current_user)}
            class="inline-flex items-center justify-center gap-[7px] rounded-[8px] px-[22px] py-3 text-[15px] font-medium bg-accent text-white border border-transparent no-underline hover:bg-[#2f6acb] transition-colors"
            style="box-shadow:var(--shadow);"
          >
            {primary_label(@current_user)}
          </.link>
          <p class="mt-[18px] text-[13px]" style="color:rgba(255,255,255,.5);">
            {gettext("Estonia live today · Finland, Latvia, Lithuania, Sweden & Norway soon.")}
          </p>
        </div>
      </div>
    </section>
    """
  end

  ## ---------- footer ----------

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
            <:link_item href="#full">{gettext("Sending funnel")}</:link_item>
            <:link_item href="#how">{gettext("Filters")}</:link_item>
            <:link_item href="#how">{gettext("Enrichment")}</:link_item>
            <:link_item href="#how">{gettext("Reply handling")}</:link_item>
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

  ## ---------- routing helpers ----------

  defp primary_path(nil), do: ~p"/sign-in"
  defp primary_path(_user), do: ~p"/campaigns/new"

  defp primary_label(_user), do: gettext("Start a campaign")
end
