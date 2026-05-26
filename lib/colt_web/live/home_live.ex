defmodule ColtWeb.HomeLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: "Liid — reliable B2B contact data for the Baltics and Nordics")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} landing={true}>
      <div class="max-w-[1080px] mx-auto w-full">
        <.hero current_user={@current_user} />
        <.problem />
        <.what_we_do />
        <.icp_match />
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
    ~H"""
    <section class="pt-10 md:pt-24 pb-16 md:pb-28">
      <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-5">
        Liid · lead enrichment for the Baltics and Nordics
      </div>
      <h1 class="font-serif font-normal text-[44px] md:text-[80px] leading-[1.0] tracking-[-0.04em] m-0 max-w-[920px] text-pretty">
        Reliable B2B contact data for the <em>Baltics</em> and Nordics.
      </h1>
      <p class="mt-7 md:mt-9 text-[15px] md:text-[17px] leading-[1.55] text-ink70 max-w-[620px] text-pretty">
        Liid pulls company data straight from government registries and enriches it with
        fresh, verified contact info. Filter by what actually matters — size, revenue,
        growth, region — and export to Instantly in one click.
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
          sign in
        </.link>
      </div>

      <div class="mt-12 md:mt-16 flex items-center gap-3 font-mono text-[11px] tracking-[0.04em] text-ink55">
        <Liid.status_dot state={:done} size={8} />
        <span>EE live · 12,400+ companies indexed</span>
        <span class="w-px h-3.5 bg-ink20 mx-1.5" />
        <span>FI · LV · LT · SE · NO soon</span>
      </div>
    </section>
    """
  end

  defp problem(assigns) do
    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          The problem
        </div>
        <div class="max-w-[680px] space-y-5 text-[15px] md:text-[16px] leading-[1.6] text-ink70">
          <p>
            Most contact databases that cover the Baltics are stale, scraped once, and
            padded with junk. <span class="text-ink">Apollo</span>
            and <span class="text-ink">ZoomInfo</span>
            are built for the US — coverage drops off the moment you cross into Tallinn or
            Riga. Local scrapers get you a name and maybe a generic
            <span class="font-mono text-[14px]">info@</span>
            address.
          </p>
          <p class="text-ink">
            If you're running cold outbound here, you've already felt it: half your list
            bounces, the other half is wrong-fit.
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
            What Liid does
          </div>
          <h2 class="font-serif text-[32px] md:text-[40px] leading-[1.05] tracking-[-0.02em] max-w-[260px]">
            Government data, recently verified.
          </h2>
        </div>

        <ul class="grid sm:grid-cols-2 gap-px bg-ink20 border border-ink20 rounded-[2px]">
          <.feature
            num="01"
            title="Government data, not scraped guesses."
            body="Companies, revenue, employee counts, annual reports — straight from rik.ee and equivalents in each market."
          />
          <.feature
            num="02"
            title="Recent enrichment, on demand."
            body={
              ~s|When Liid gives you a contact, it was checked recently. No "last verified 2022" footnotes.|
            }
          />
          <.feature
            num="03"
            title="Filters that match how you target."
            body="Industry, region, founded year, employee count, revenue band, growth trajectory."
          />
          <.feature
            num="04"
            title="Export-ready."
            body="Instantly-format CSV in one click. Take it anywhere."
          />
        </ul>
      </div>
    </section>
    """
  end

  attr :num, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  defp feature(assigns) do
    ~H"""
    <li class="bg-paper p-6 md:p-8">
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
          ICP match
        </div>
        <div class="max-w-[720px]">
          <h2 class="font-serif font-normal text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
            Filters get you close. ICP match gets you <em>right</em>.
          </h2>

          <div class="mt-8 space-y-5 text-[15px] md:text-[16px] leading-[1.65] text-ink70">
            <p>
              Government data lets you narrow by size, revenue, region — the structured
              stuff. But "50-employee fintechs in Tallinn" still leaves you with a list
              where half the companies aren't actually selling what you think.
            </p>
            <p class="text-ink">
              So Liid reads every candidate's website, summarises what they actually do,
              and checks it against the ICP you described in plain English. Wrong-fit
              companies are flagged and excluded from the export — you only pay attention
              to ones that pass both gates.
            </p>
          </div>

          <div class="mt-10 border border-ink20 rounded-[2px] divide-y divide-rule font-mono text-[12px]">
            <.match_row
              state={:done}
              name="Konvey OÜ"
              meta="€820k · 47 emp · Tallinn"
              note={~s|matches "B2B SaaS for logistics"|}
              tone={:match}
            />
            <.match_row
              state={:done}
              name="Tehno Grupp AS"
              meta="€940k · 52 emp · Tartu"
              note="industrial automation · not a match"
              tone={:miss}
            />
            <.match_row
              state={:done}
              name="Routelink OÜ"
              meta="€670k · 38 emp · Tallinn"
              note={~s|matches "B2B SaaS for logistics"|}
              tone={:match}
            />
          </div>

          <div class="mt-3 font-mono text-[10px] uppercase tracking-[0.1em] text-ink40">
            preview · 2 of 3 included in export
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

  defp ai_section(assigns) do
    ~H"""
    <section class="py-20 md:py-32 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          On AI
        </div>
        <div class="max-w-[700px]">
          <h2 class="font-serif font-normal text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
            AI is a tool here, not the <em>product</em>.
          </h2>

          <div class="mt-8 space-y-5 text-[15px] md:text-[16px] leading-[1.65] text-ink70">
            <p>
              We tried the "AI does everything" version. Agents that write emails, agents
              that decide who to contact, agents that personalise. It's expensive to keep
              stable and the output stinks of slop — recipients can tell. People are
              getting so much AI-written outreach now that even genuinely human emails are
              starting to read as suspicious.
            </p>
            <p class="text-ink">
              The cold emails that work are the ones with a clear offer sent to a
              well-targeted list. That's what Liid optimises for.
            </p>
            <p>
              AI lives inside the pipeline as glue — matching ICPs, summarising websites,
              validating fit — never as the thing writing to your prospects.
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
        How it works
      </div>

      <ol class="grid md:grid-cols-3 gap-px bg-ink20 border border-ink20 rounded-[2px]">
        <.step num="01" body="Describe your ICP and pick a market." />
        <.step num="02" body="Filter the registry data — size, revenue, growth, region." />
        <.step
          num="03"
          body="Liid enriches in parallel: website validated, contact found, email verified. Export."
        />
      </ol>
    </section>
    """
  end

  attr :num, :string, required: true
  attr :body, :string, required: true

  defp step(assigns) do
    ~H"""
    <li class="bg-paper p-6 md:p-10">
      <div class="font-serif text-[44px] md:text-[56px] leading-none tracking-[-0.02em] tnum">
        {@num}
      </div>
      <div class="mt-6 text-[15px] text-ink70 leading-[1.55] max-w-[280px]">{@body}</div>
    </li>
    """
  end

  defp coverage(assigns) do
    markets = [
      {"EE", "Estonia", :live},
      {"FI", "Finland", :soon},
      {"LV", "Latvia", :soon},
      {"LT", "Lithuania", :soon},
      {"SE", "Sweden", :soon},
      {"NO", "Norway", :soon}
    ]

    assigns = assign(assigns, markets: markets)

    ~H"""
    <section class="py-16 md:py-24 border-t border-rule">
      <div class="grid md:grid-cols-[260px_1fr] gap-8 md:gap-16">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 pt-1">
          Coverage
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
          <span class="font-mono text-[10px] uppercase tracking-[0.1em] text-ink55">live</span>
        </span>
        <span
          :if={@state == :soon}
          class="font-mono text-[10px] uppercase tracking-[0.1em] text-ink40"
        >
          soon
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
        Stop sending to <em>dead</em> inboxes.
      </h2>
      <p class="mt-6 text-[15px] text-ink55 max-w-[520px]">
        Build a targeted list from real registry data. Export it. Send something worth
        reading.
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
      <span>built by Krister Viirsaar</span>
      <span class="w-px h-3 bg-ink20" />
      <span>Täp OÜ · Tallinn, Estonia</span>
      <span class="w-px h-3 bg-ink20" />
      <a href="mailto:liid@krister.ee" class="hover:text-ink no-underline normal-case tracking-normal">
        liid@krister.ee
      </a>
      <span class="w-px h-3 bg-ink20" />
      <span>{DateTime.utc_now().year}</span>
      <span class="flex-1" />
      <.link
        :if={is_nil(@current_user)}
        href="/sign-in"
        class="hover:text-ink no-underline"
      >
        sign in
      </.link>
    </footer>
    """
  end

  defp primary_path(nil), do: "/sign-in"
  defp primary_path(_user), do: "/campaigns/new"

  defp primary_label(nil), do: "Get verified leads"
  defp primary_label(_user), do: "Get verified leads"
end
