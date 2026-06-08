defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Liid — all-in-one lead gen for the Baltics and Nordics")
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} landing={true}>
      <div class="max-w-[1080px] mx-auto w-full">
        <.hero current_user={@current_user} />
        <.process />
        <.problem />
        <.icp_match />
        <.what_we_do />
        <.writer />
        <.ai_section />
        <.how_it_works />
        <.coverage />
        <.footer_cta current_user={@current_user} />
      </div>
    </Layouts.app>
    """
  end

  attr :current_user, :map, default: nil

  defp hero(assigns) do
    markets = Colt.Markets.all()
    live = markets |> Enum.filter(& &1.enabled) |> Enum.map(& &1.code)
    soon = markets |> Enum.reject(& &1.enabled) |> Enum.map(& &1.code)
    assigns = assign(assigns, live: live, soon: soon)

    ~H"""
    <section class="pt-10 md:pt-24 pb-16 md:pb-28">
      <h1 class="font-serif font-normal text-[44px] md:text-[80px] leading-[1.0] tracking-[-0.04em] m-0 max-w-[920px] text-pretty">
        {raw(gettext("Lead gen for the Baltics and <em>Nordics</em>."))}
      </h1>
      <p class="mt-7 md:mt-9 text-[15px] md:text-[17px] leading-[1.55] text-ink70 max-w-[620px] text-pretty">
        {gettext(
          "Accurate targeting, emails personalised in your own writing style, and the infrastructure to send thousands — all in one."
        )}
      </p>

      <div class="mt-10 md:mt-14 flex flex-wrap items-center gap-4">
        <.link navigate={primary_path(@current_user)}>
          <Liid.btn variant={:primary} mono>
            {primary_label(@current_user)} <Liid.icon name="arrow" />
          </Liid.btn>
        </.link>
        <.link
          :if={is_nil(@current_user)}
          href="/sign-in"
          class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
        >
          {gettext("sign in")}
        </.link>
      </div>

      <div class="mt-12 md:mt-16 flex items-center gap-3 font-mono text-[11px] tracking-[0.04em] text-ink55">
        <Liid.status_dot state={:done} size={8} />
        <span>{gettext("%{codes} live", codes: Enum.join(@live, " · "))}</span>
        <span :if={@soon != []} class="w-px h-3.5 bg-ink20 mx-1.5" />
        <span :if={@soon != []}>
          {gettext("%{codes} soon", codes: Enum.join(@soon, " · "))}
        </span>
      </div>
    </section>
    """
  end

  defp process(assigns) do
    steps = [
      %{
        n: "01",
        label: gettext("Target"),
        body: gettext("Filter companies based on government data"),
        dot: :done
      },
      %{
        n: "02",
        label: gettext("ICP fit"),
        body: gettext("AI checks if the company website fits your profile"),
        dot: :done
      },
      %{
        n: "03",
        label: gettext("Contact data"),
        body: gettext("Freshly scraped and verified"),
        dot: :done
      },
      %{
        n: "04",
        label: gettext("Write"),
        body: gettext("Write a few emails, AI learns your style"),
        dot: :work
      },
      %{
        n: "05",
        label: gettext("Send"),
        body: gettext("Send 1000's of emails a day from multiple domains"),
        dot: :work
      }
    ]

    assigns = assign(assigns, steps: steps)

    ~H"""
    <section class="pb-14 md:pb-24">
      <div class="border border-ink20 rounded-[2px] bg-paper overflow-hidden">
        <div class="flex flex-col md:flex-row">
          <%= for {step, i} <- Enum.with_index(@steps) do %>
            <div class="flex-1 p-5 md:p-6">
              <div class="flex items-center gap-2 mb-3.5">
                <Liid.status_dot state={step.dot} size={7} />
                <span class="font-mono text-[10px] tracking-[0.12em] text-ink40 tnum">
                  {step.n}
                </span>
              </div>
              <div class="font-serif text-[24px] md:text-[28px] leading-none tracking-[-0.02em] text-ink">
                {step.label}
              </div>
              <div class="mt-2.5 font-mono text-[11px] text-ink55 leading-[1.45]">
                {step.body}
              </div>
            </div>
            <div
              :if={i < length(@steps) - 1}
              class="flex items-center justify-center text-ink40 border-t md:border-t-0 md:border-l border-rule shrink-0 py-1.5 md:py-0 md:px-1"
            >
              <Liid.icon name="arrow" size={16} class="rotate-90 md:rotate-0" />
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp problem(assigns) do
    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          {gettext("The problem")}
        </div>
        <div class="max-w-[680px] space-y-5 text-[15px] md:text-[16px] leading-[1.6] text-ink70">
          <p>
            {gettext(
              "Running cold outbound in the Baltics and Nordics means juggling tools — one to build the list, another to verify emails, a third to send and track replies. Every handoff loses data and adds a place for things to break."
            )}
          </p>
          <p class="text-ink">
            {gettext(
              "And stale contact data destroys your domain reputation and your emails go to spam — where nobody reads them."
            )}
          </p>
        </div>
      </div>
    </section>
    """
  end

  defp what_we_do(assigns) do
    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div>
          <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-3">
            {gettext("What Liid does")}
          </div>
          <h2 class="font-serif text-[32px] md:text-[40px] leading-[1.05] tracking-[-0.02em] max-w-[260px]">
            {raw(gettext("Clean data in. <em>Safe</em> volume out."))}
          </h2>
        </div>

        <div class="space-y-10">
          <div>
            <div class="font-mono text-[11px] tracking-[0.14em] uppercase text-ink40 mb-3 flex items-center gap-2">
              <Liid.status_dot state={:done} size={6} /> {gettext("Clean data")}
            </div>
            <ul class="grid sm:grid-cols-3 gap-px bg-ink20 border border-ink20 rounded-[2px]">
              <.feature
                num="01"
                title={gettext("Fresh by default.")}
                body={
                  gettext(
                    "Company data straight from the government registries, with contact details scraped recently — not a dump from years ago."
                  )
                }
              />
              <.feature
                num="02"
                title={gettext("Filter on what actually matters.")}
                body={
                  gettext(
                    "Revenue and employee-count bands, region, growth, industry, founded year — the structured data US tools never have for this region."
                  )
                }
              />
              <.feature
                num="03"
                title={gettext("Double-verified contacts.")}
                body={
                  gettext(
                    "Every email and phone we surface actually appears on the company's own site, and we check deliverability separately — so bounces don't trash your domain."
                  )
                }
              />
            </ul>
          </div>

          <div>
            <div class="font-mono text-[11px] tracking-[0.14em] uppercase text-ink40 mb-3 flex items-center gap-2">
              <Liid.status_dot state={:work} size={6} /> {gettext("Safe volume")}
            </div>
            <ul class="grid sm:grid-cols-3 gap-px bg-ink20 border border-ink20 rounded-[2px]">
              <.feature
                num="04"
                title={gettext("No wasted sends.")}
                body={
                  gettext(
                    "AI ICP-fit filtering keeps your volume aimed at companies that could actually buy — never spent on ones that would never buy from you."
                  )
                }
              />
              <.feature
                num="05"
                title={gettext("Fully automated sending.")}
                body={
                  gettext(
                    "Sequences send on schedule from your own inbox — working hours, daily caps, randomised bursts. Replies pause the sequence automatically."
                  )
                }
              />
              <.feature
                num="06"
                title={gettext("Many inboxes, less risk.")}
                body={
                  gettext(
                    "Spread volume across several connected accounts — more reach, lower risk per inbox, and your sending stays healthy."
                  )
                }
              />
            </ul>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :num, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  defp feature(assigns) do
    ~H"""
    <li class="bg-paper p-6 md:p-7">
      <div class="font-mono text-[11px] tracking-[0.08em] text-ink40 mb-4 tnum">{@num}</div>
      <div class="text-[15px] font-medium text-ink mb-2 leading-[1.4]">{@title}</div>
      <div class="text-[14px] text-ink55 leading-[1.55]">{@body}</div>
    </li>
    """
  end

  defp icp_match(assigns) do
    ~H"""
    <section class="py-20 md:py-32 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          {gettext("ICP match")}
        </div>
        <div class="max-w-[720px]">
          <h2 class="font-serif font-normal text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
            {raw(gettext("Filters narrow it down. AI tells you <em>exactly</em> who fits."))}
          </h2>

          <div class="mt-8 space-y-5 text-[15px] md:text-[16px] leading-[1.65] text-ink70">
            <p>
              {gettext(
                ~s|The structured data gets you part way — size, revenue, region. But an industry code only says a company is filed under "fintech", not that it sells what you sell. Half a code-matched list looks right and isn't.|
              )}
            </p>
            <p class="text-ink">
              {gettext(
                "So Liid reads every candidate's website, summarises what they actually do, and checks it against the ICP you described in plain English. Wrong-fit companies are excluded before you see them — and the ones that pass are exactly the contacts your sequence goes to. No re-importing, no copy-paste."
              )}
            </p>
            <p>
              {gettext(
                "This matters more than any clever personalisation. A plain, clear email to a company that genuinely fits beats a tailored one sent to the wrong list — and it keeps your domain out of spam folders."
              )}
            </p>
          </div>

          <div class="mt-10 border border-ink20 rounded-[2px] divide-y divide-rule font-mono text-[12px]">
            <.match_row
              state={:done}
              name="Konvey OÜ"
              meta="€820k · 47 emp · Tallinn"
              note={gettext(~s|matches "B2B SaaS for logistics"|)}
              tone={:match}
            />
            <.match_row
              state={:done}
              name="Tehno Grupp AS"
              meta="€940k · 52 emp · Tartu"
              note={gettext("industrial automation · not a match")}
              tone={:miss}
            />
            <.match_row
              state={:done}
              name="Routelink OÜ"
              meta="€670k · 38 emp · Tallinn"
              note={gettext(~s|matches "B2B SaaS for logistics"|)}
              tone={:match}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :state, :atom, required: true
  attr :name, :string, required: true
  attr :meta, :string, required: true
  attr :note, :string, required: true
  attr :tone, :atom, required: true

  defp match_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-4 px-4 py-3",
      @tone == :miss && "opacity-55"
    ]}>
      <Liid.status_dot state={if @tone == :match, do: :done, else: :skip} size={6} />
      <div class="font-sans text-[13px] font-medium text-ink truncate">{@name}</div>
      <div class="text-[11px] text-ink55 hidden sm:block">{@meta}</div>
      <div class="flex-1" />
      <div class={[
        "text-[11px] truncate",
        @tone == :match && "text-[var(--accent)]",
        @tone == :miss && "text-ink40"
      ]}>
        {@note}
      </div>
    </div>
    """
  end

  defp writer(assigns) do
    ~H"""
    <section class="py-20 md:py-32 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          {gettext("Writing")}
        </div>
        <div class="max-w-[720px]">
          <h2 class="font-serif font-normal text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
            {raw(gettext("AI learns from how <em>you</em> write."))}
          </h2>

          <div class="mt-8 space-y-5 text-[15px] md:text-[16px] leading-[1.65] text-ink70">
            <p>
              {gettext(
                "AI does write your emails — but every change you make is remembered and used for the next draft."
              )}
            </p>
            <p class="text-ink">
              {gettext(
                "You review every email first. Once you're happy with what the AI does, flip on \"approve automatically\" and it takes over."
              )}
            </p>
          </div>

          <div class="mt-10 border border-ink20 rounded-[2px] bg-paper p-5 md:p-6 font-mono text-[12px] leading-[1.6]">
            <div class="flex items-center gap-2 text-ink40 text-[10px] uppercase tracking-[0.1em] mb-3">
              <Liid.status_dot state={:done} size={6} /> {gettext("Step 1 · Initial")}
              <span class="flex-1" />
              <span>{gettext("draft · editable")}</span>
            </div>
            <div class="text-ink mb-1">{gettext("Subject:")} Konvey + warehouse routing</div>
            <div class="text-ink55">
              {gettext(
                "Hi Mart — saw Konvey runs last-mile for a few Tallinn 3PLs. We cut routing overhead for teams your size; worth a 15-min look?"
              )}
            </div>
          </div>

          <div class="mt-3 font-mono text-[10px] uppercase tracking-[0.1em] text-ink40">
            {gettext("one contact at a time · learns from your edits · your voice, not a template")}
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp ai_section(assigns) do
    ~H"""
    <section class="py-20 md:py-32 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          {gettext("On AI")}
        </div>
        <div class="max-w-[700px]">
          <h2 class="font-serif font-normal text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
            {raw(
              gettext("AI is great as <em>glue</em> between the blocks, but it's not a great block.")
            )}
          </h2>

          <div class="mt-8 space-y-5 text-[15px] md:text-[16px] leading-[1.65] text-ink70">
            <p>
              {gettext(
                ~s|Top-tier models do this work well, but they cost so much it isn't worth it — and cheap models just don't work. We tried the "AI agent does everything" model and it never came together. So we do what programmers have known for thirty years and apply AI only where it actually makes sense. It's the glue, not the block.|
              )}
            </p>
            <p class="text-ink">
              {gettext(
                ~s|It shows in the inbox, too. People can sense the slop, and they get so much "personalised" AI outreach now that it all blurs together. A well-targeted, clear offer is what actually gets read.|
              )}
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp how_it_works(assigns) do
    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-10">
        {gettext("How it works")}
      </div>

      <ol class="grid sm:grid-cols-2 lg:grid-cols-5 gap-px bg-ink20 border border-ink20 rounded-[2px]">
        <.step num="01" body={gettext("Describe your ICP and pick a market.")} />
        <.step
          num="02"
          body={gettext("Filter the registry data — size, revenue, growth, region.")}
        />
        <.step
          num="03"
          body={gettext("Liid enriches: website validated, contact found, email verified.")}
        />
        <.step
          num="04"
          body={gettext("Connect your inbox and approve the drafted sequence.")}
        />
        <.step
          num="05"
          body={gettext("Liid sends on schedule and funnels every reply back to you.")}
        />
      </ol>
    </section>
    """
  end

  attr :num, :string, required: true
  attr :body, :string, required: true

  defp step(assigns) do
    ~H"""
    <li class="bg-paper p-6 md:p-7">
      <div class="font-serif text-[40px] md:text-[48px] leading-none tracking-[-0.02em] tnum">
        {@num}
      </div>
      <div class="mt-5 text-[14px] text-ink70 leading-[1.55] max-w-[280px]">{@body}</div>
    </li>
    """
  end

  defp market_name("EE"), do: gettext("Estonia")
  defp market_name("FI"), do: gettext("Finland")
  defp market_name("LV"), do: gettext("Latvia")
  defp market_name("LT"), do: gettext("Lithuania")
  defp market_name("SE"), do: gettext("Sweden")
  defp market_name("NO"), do: gettext("Norway")
  defp market_name("DK"), do: gettext("Denmark")

  defp coverage(assigns) do
    markets =
      Enum.map(Colt.Markets.all(), fn m ->
        {m.code, market_name(m.code), if(m.enabled, do: :live, else: :soon)}
      end)

    assigns = assign(assigns, markets: markets)

    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          {gettext("Coverage")}
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-px bg-ink20 border border-ink20 rounded-[2px]">
          <.market :for={{code, name, state} <- @markets} code={code} name={name} state={state} />
        </div>
      </div>
    </section>
    """
  end

  attr :code, :string, required: true
  attr :name, :string, required: true
  attr :state, :atom, required: true

  defp market(assigns) do
    ~H"""
    <div class={[
      "bg-paper p-5 md:p-6 flex flex-col gap-3",
      @state == :soon && "opacity-50"
    ]}>
      <div class="flex items-center justify-between">
        <span class="font-mono text-[11px] tracking-[0.08em] text-ink55">{@code}</span>
        <span :if={@state == :live} class="flex items-center gap-1.5">
          <Liid.status_dot state={:done} size={6} />
          <span class="font-mono text-[10px] uppercase tracking-[0.1em] text-ink55">
            {gettext("live")}
          </span>
        </span>
        <span
          :if={@state == :soon}
          class="font-mono text-[10px] uppercase tracking-[0.1em] text-ink40"
        >
          {gettext("soon")}
        </span>
      </div>
      <div class="font-serif text-[24px] md:text-[28px] leading-none tracking-[-0.02em]">
        {@name}
      </div>
    </div>
    """
  end

  attr :current_user, :map, default: nil

  defp footer_cta(assigns) do
    ~H"""
    <section class="py-24 md:py-36 border-t border-rule">
      <h2 class="font-serif font-normal text-[36px] md:text-[64px] leading-[1.0] tracking-[-0.04em] m-0 max-w-[820px] text-pretty">
        {raw(gettext("Stop sending to <em>dead</em> inboxes."))}
      </h2>
      <p class="mt-6 text-[15px] text-ink55 max-w-[520px]">
        {gettext(
          "Build a targeted list from real registry data, write something worth reading, and send it from your own inbox — all in one place."
        )}
      </p>
      <div class="mt-10">
        <.link navigate={primary_path(@current_user)}>
          <Liid.btn variant={:primary} mono>
            {primary_label(@current_user)} <Liid.icon name="arrow" />
          </Liid.btn>
        </.link>
      </div>
    </section>

    <footer class="py-10 border-t border-rule flex flex-wrap items-center gap-x-4 gap-y-2 font-mono text-[10px] uppercase tracking-[0.12em] text-ink40">
      <span>Liid</span>
      <span class="w-px h-3 bg-ink20" />
      <span>{gettext("built by Krister Viirsaar")}</span>
      <span class="w-px h-3 bg-ink20" />
      <span>{gettext("Täp OÜ · Tallinn, Estonia")}</span>
      <span class="w-px h-3 bg-ink20" />
      <a href="mailto:liid@krister.ee" class="hover:text-ink no-underline normal-case tracking-normal">
        liid@krister.ee
      </a>
      <span class="w-px h-3 bg-ink20" />
      <span>{DateTime.utc_now().year}</span>
      <span class="flex-1" />
      <.link navigate={~p"/privacy"} class="hover:text-ink no-underline">
        {gettext("privacy")}
      </.link>
      <span class="w-px h-3 bg-ink20" />
      <.link navigate={~p"/terms"} class="hover:text-ink no-underline">
        {gettext("terms")}
      </.link>
      <span class="w-px h-3 bg-ink20" />
      <.link
        :if={is_nil(@current_user)}
        href="/sign-in"
        class="hover:text-ink no-underline"
      >
        {gettext("sign in")}
      </.link>
    </footer>
    """
  end

  defp primary_path(nil), do: "/sign-in"
  defp primary_path(_user), do: "/campaigns/new"

  defp primary_label(nil), do: gettext("Start a campaign")
  defp primary_label(_user), do: gettext("Start a campaign")
end
