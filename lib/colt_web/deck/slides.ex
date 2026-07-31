defmodule ColtWeb.Deck.Slides do
  @moduledoc """
  The demo deck: slides as code, not as data.

  There is deliberately no slide editor. A slide is a HEEx function here, which
  means full HTML/CSS, real product numbers pulled at render time, and a git
  diff when the pitch changes.

  Two things are keyed off `slide_key`:

  - `order/1` — which slides each A/B variant plays, and in what sequence. The
    long deck runs `a…f`; the short deck runs `a b c g`, where `g` is a single
    condensed slide standing in for `d e f`. Adding a variant is a new clause,
    not a schema change.
  - narration — `Colt.Deck.Manifest` points at recorded clips by `slide_key`,
    so slides shared between variants share one recording. Record `:hook` once
    and both decks have it.

  Every slide renders into a 16:9 stage that is `container-type: size`, so all
  type is sized in `cqw` (percent of stage width) and the layout is identical at
  any viewport — see the `deck-*` styles in `ColtWeb.DeckLive`.
  """
  use ColtWeb, :html

  @long [:hook, :problem, :targeting, :enrichment, :sending, :cta]
  @short [:hook, :problem, :targeting, :short_cta]

  @doc "Every A/B variant the deck is built for, in presentation order."
  def variants, do: ["long", "short"]

  @doc "Slide order for an ab_funnel variant. Unknown/absent variant gets the long deck."
  def order("short"), do: @short
  def order("long"), do: @long
  def order(_), do: @long

  @doc "Every slide that exists, for the studio's recording list."
  def all_keys, do: Enum.uniq(@long ++ @short)

  def title(:hook), do: "What Liid is"
  def title(:problem), do: "One tool, not five"
  def title(:targeting), do: "Describe who you sell to"
  def title(:enrichment), do: "The AI reads every website"
  def title(:sending), do: "Replies land sorted"
  def title(:cta), do: "Pricing & start"
  def title(:short_cta), do: "The rest of it, and pricing"

  ## ---------- shared stage styles ----------

  @doc """
  The `d-*` / `deck-*` stylesheet shared by the player and the studio.

  Kept as a plain stylesheet rather than utility classes because every size in
  it is in `cqw`, which only means anything inside the `container-type: size`
  stage — see `.deck-stage`.
  """
  def styles(assigns) do
    ~H"""
    <style>
      /* The stage is a fixed 16:9 box that is its own size container, so every
         slide measurement below is in cqw (% of stage width) and the deck looks
         identical on a laptop and on a boardroom screen. */
      .deck-stage {
        width: 100%;
        aspect-ratio: 16 / 9;
        container-type: size;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 11px;
        box-shadow: var(--shadow-card);
        position: relative;
        overflow: hidden;
      }

      /* Full-screen playback: the stage takes the whole viewport, letterboxed
         to 16:9 so slide layout (all cqw) is identical to the studio preview. */
      .deck-fullscreen .deck-stage {
        width: min(100vw, calc(100vh * 16 / 9));
        border: 0;
        border-radius: 0;
        box-shadow: none;
      }

      /* Extra bottom padding is the face bubble's safe area: content is
         vertically centred inside this box, so the padding lifts it clear of
         the corner the talking head occupies. */
      .d-pad { padding: 4.2cqw 5cqw 9.5cqw; }
      .d-h1 { font-size: 5.4cqw; line-height: 1.04; font-weight: 700; letter-spacing: -0.03em; }
      .d-h2 { font-size: 3.9cqw; line-height: 1.08; font-weight: 700; letter-spacing: -0.025em; }
      .d-h3 { font-size: 2.1cqw; line-height: 1.15; letter-spacing: -0.02em; }
      .d-h4 { font-size: 1.75cqw; line-height: 1.2; letter-spacing: -0.015em; }
      .d-lead { font-size: 1.9cqw; line-height: 1.45; font-weight: 450; }
      .d-body { font-size: 1.35cqw; line-height: 1.4; font-weight: 450; }
      .d-fine { font-size: 1.02cqw; line-height: 1.35; }
      .d-kicker {
        font-size: 1.02cqw; font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.09em;
      }
      .d-num {
        font-size: 2.9cqw; font-weight: 700; letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums; line-height: 1.15;
      }
      .d-num-sm {
        font-size: 1.9cqw; font-weight: 700; letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums; line-height: 1.2;
      }

      .d-card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 11px;
        box-shadow: var(--shadow);
      }
      .d-cardhead {
        padding: 0.7cqw 1.5cqw;
        border-bottom: 1px solid var(--border);
        background: var(--bgSoft);
        color: var(--inkFaint);
        font-size: 0.95cqw; font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.05em;
      }
      .d-chip {
        display: inline-flex; align-items: center; gap: 0.5cqw;
        border-radius: 999px; padding: 0.4cqw 0.9cqw;
        font-size: 1cqw; font-weight: 600;
      }
      .d-dot { width: 0.7cqw; height: 0.7cqw; border-radius: 999px; display: inline-block; }
      .d-step-no {
        display: grid; place-items: center;
        width: 2cqw; height: 2cqw; border-radius: 0.6cqw;
        background: var(--bgSoft); color: var(--inkFaint);
        font-size: 0.95cqw; font-weight: 700;
      }
      .d-x {
        display: grid; place-items: center;
        width: 1.6cqw; height: 1.6cqw; border-radius: 0.45cqw;
        background: #efeeec; color: var(--inkFaint);
        font-size: 0.85cqw; font-weight: 700; flex-shrink: 0;
      }
      .d-avatar {
        display: grid; place-items: center;
        width: 3.2cqw; height: 3.2cqw; border-radius: 0.9cqw;
        background: var(--accentSoft); color: var(--accent);
        font-size: 1.2cqw; font-weight: 700; flex-shrink: 0;
      }
      .d-btn {
        display: inline-flex; align-items: center; justify-content: center;
        background: var(--accent); color: #fff;
        border-radius: 0.7cqw; padding: 1cqw 1.8cqw;
        font-size: 1.4cqw; font-weight: 600;
        box-shadow: var(--shadow); cursor: pointer;
      }
      .d-caret {
        display: inline-block; width: 0; height: 1.1cqw;
        border-right: 2px solid var(--accent); vertical-align: text-bottom;
        animation: deck-blink 1.1s steps(1) infinite;
      }
      @keyframes deck-blink { 50% { opacity: 0 } }

      /* the talking head */
      .deck-bubble {
        position: absolute; right: 2cqw; bottom: 2cqw;
        width: 10.5cqw; height: 10.5cqw; border-radius: 999px;
        object-fit: cover; background: #efeeec;
        border: 0.35cqw solid #fff;
        box-shadow: 0 4px 18px rgba(35,32,28,.18);
        z-index: 3;
      }
      .deck-bubble[hidden] { display: none; }
    </style>
    """
  end

  ## ---------- render ----------

  attr :key, :atom, required: true
  attr :registry_total, :integer, default: 0
  attr :countries, :list, default: []
  attr :cta_path, :string, default: "/register"

  def slide(assigns) do
    case assigns.key do
      :hook -> hook(assigns)
      :problem -> problem(assigns)
      :targeting -> targeting(assigns)
      :enrichment -> enrichment(assigns)
      :sending -> sending(assigns)
      :cta -> cta(assigns)
      :short_cta -> short_cta(assigns)
    end
  end

  ## ---------- a · hook ----------

  defp hook(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full text-center">
      <div class="d-kicker text-accent">Liid</div>
      <h1 class="d-h1 mt-[1.4cqw]">
        Lead gen for the Baltics and <em>Nordics</em>.
      </h1>
      <p class="d-lead text-inkSoft mt-[1.6cqw] mx-auto max-w-[62cqw]">
        Find who fits, reach them in your voice — and get back only the replies worth answering.
      </p>

      <div class="flex items-stretch justify-center gap-[0.9cqw] mt-[3.4cqw]">
        <.pstep no="1" tone={:accent} label="Filter" value={approx(@registry_total)}>
          registry companies
        </.pstep>
        <.pstep no="2" label="Enrich" value="10k">enriched contacts</.pstep>
        <.pstep no="3" label="AI checks" value="2,400">match <em>your</em> ICP</.pstep>
        <.pstep no="4" tone={:accent} label="Send" value="2,400">in <em>your</em> voice</.pstep>
        <.pstep no="5" tone={:green} label="Reply" value="160">interested leads</.pstep>
      </div>

      <div class="d-fine text-inkFaint mt-[2.2cqw]">
        {countries_line(@countries)}
      </div>
    </div>
    """
  end

  ## ---------- b · problem ----------

  defp problem(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="d-kicker text-inkFaint">The stack you're replacing</div>
      <h2 class="d-h2 mt-[1cqw]">One tool, not <em>five</em>.</h2>

      <div class="grid grid-cols-[1fr_0.9fr] gap-[3cqw] items-center mt-[3cqw]">
        <div class="flex flex-col gap-[0.85cqw]">
          <.ot job="Prospecting & data" svc="Apollo, ZoomInfo" />
          <.ot job="Enrichment" svc="Clay" />
          <.ot job="Email verification" svc="MillionVerifier" />
          <.ot job="Sequencer + inboxes" svc="Instantly, Smartlead" />
          <.ot job="Calling & follow-up" svc="an SDR or an agency" />
          <div class="d-fine text-inkFaint pl-[0.3cqw]">
            + the spreadsheet, the VA, and the copy-paste between them.
          </div>
        </div>

        <div
          class="bg-accentSoft border border-accentRing rounded-[11px] px-[2.4cqw] py-[2.6cqw]"
          style="box-shadow:0 0 0 4px rgba(59,122,224,.07),var(--shadow-card);"
        >
          <div class="flex items-center gap-[0.8cqw] text-accent font-bold d-h3">
            <.logo size={2.4} /> Liid
          </div>
          <p class="d-body text-ink leading-[1.55] mt-[1.2cqw] font-semibold">
            Finds, fits, verifies, writes, sequences across inboxes — and hands you the replies.
          </p>
          <span class="d-chip mt-[1.6cqw] bg-card border border-accentRing text-accent">
            <span class="d-dot bg-green" /> One login
          </span>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- c · targeting ----------

  defp targeting(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="d-kicker text-inkFaint">Step one</div>
      <h2 class="d-h2 mt-[1cqw]">Describe who you sell to. In <em>one sentence</em>.</h2>

      <div class="grid grid-cols-[1.15fr_1fr] gap-[2.4cqw] mt-[2.6cqw]">
        <div class="d-card overflow-hidden">
          <div class="d-cardhead">Who you sell to</div>
          <div class="px-[1.5cqw] py-[1.4cqw] d-body text-inkSoft leading-[1.5]">
            B2B SaaS selling to enterprise, 10–50 people, raised a seed round,
            struggling to scale outbound from a tiny founding team<span class="d-caret" />
          </div>
          <div class="px-[1.5cqw] pb-[1.4cqw]">
            <span class="d-chip bg-accentSoft border border-accentRing text-accent">
              Target title: CTO
            </span>
          </div>
        </div>

        <div class="d-card overflow-hidden">
          <div class="d-cardhead">Straight from the national registry</div>
          <div class="px-[1.5cqw] py-[1.4cqw] flex flex-wrap gap-[0.6cqw]">
            <span class="d-chip bg-bgSoft border border-border text-inkSoft">Software · 62.01</span>
            <span class="d-chip bg-bgSoft border border-border text-inkSoft">Harju maakond</span>
            <span class="d-chip bg-bgSoft border border-border text-inkSoft">Revenue €1M–€10M</span>
            <span class="d-chip bg-bgSoft border border-border text-inkSoft">10–50 employees</span>
            <span
              class="d-chip border"
              style="background:var(--greenSoft);border-color:#bfe3d1;color:var(--green);"
            >
              Growing · 2×
            </span>
          </div>
          <div class="px-[1.5cqw] pb-[1.5cqw] pt-[0.4cqw] border-t border-border mt-[0.4cqw]">
            <div class="d-fine text-inkFaint mt-[1cqw]">Companies matching right now</div>
            <div class="d-num text-accent">512</div>
          </div>
        </div>
      </div>

      <div class="d-fine text-inkFaint mt-[2cqw]">
        Official registry data, refreshed nightly — real revenue and headcount, not a resold list.
      </div>
    </div>
    """
  end

  ## ---------- d · enrichment ----------

  defp enrichment(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="d-kicker text-inkFaint">The week you get back</div>
      <h2 class="d-h2 mt-[1cqw]">It reads every site and <em>throws most out</em>.</h2>

      <div class="grid grid-cols-4 gap-[1.2cqw] mt-[2.8cqw]">
        <.stat label="Registry match" value="512" sub="companies to check" />
        <.stat label="Website read" value="486" sub="scraped & summarised" />
        <.stat label="Fits your ICP" value="141" sub="judged by the AI" tone={:accent} />
        <.stat label="Verified email" value="118" sub="named person, valid inbox" tone={:green} />
      </div>

      <div class="grid grid-cols-2 gap-[1.6cqw] mt-[2cqw]">
        <div class="d-card px-[1.5cqw] py-[1.3cqw]">
          <div class="d-fine text-inkFaint">Why this one fits</div>
          <p class="d-body text-ink leading-[1.5] mt-[0.6cqw]">
            "Series-A analytics vendor, 28 staff, sells to enterprise retail.
            Careers page lists two open AE roles — outbound is a live problem."
          </p>
        </div>
        <div class="d-card px-[1.5cqw] py-[1.3cqw] flex items-center gap-[1.2cqw]">
          <span class="d-avatar">MK</span>
          <div>
            <div class="d-body font-bold text-ink">Mari Kask</div>
            <div class="d-fine text-inkFaint">CTO · datastack.ee</div>
            <div class="d-fine text-green mt-[0.4cqw] flex items-center gap-[0.4cqw]">
              <span class="d-dot bg-green" /> mari@datastack.ee · verified
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## ---------- e · sending ----------

  defp sending(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="d-kicker text-inkFaint">What you open in the morning</div>
      <h2 class="d-h2 mt-[1cqw]">Replies land <em>sorted by intent</em>.</h2>

      <div class="grid grid-cols-5 gap-[1cqw] mt-[2.6cqw]">
        <.stat label="Sent" value="2,400" sub="across 4 domains" />
        <.stat label="Opened" value="1,104" sub="46%" />
        <.stat label="Replied" value="238" sub="9.9%" />
        <.stat label="Interested" value="160" sub="worth answering" tone={:green} />
        <.stat label="In sales funnel" value="41" sub="live conversations" tone={:accent} />
      </div>

      <div class="grid grid-cols-[1fr_1fr] gap-[1.6cqw] mt-[2.2cqw]">
        <div class="d-card px-[1.5cqw] py-[1.3cqw]">
          <div class="flex items-center gap-[0.5cqw] flex-wrap">
            <span class="d-chip bg-bgSoft border border-border text-inkSoft">Step 2</span>
            <span class="d-chip bg-accentSoft border border-accentRing text-accent">Them</span>
            <span
              class="d-chip border"
              style="background:var(--greenSoft);border-color:#bfe3d1;color:var(--green);"
            >
              Interested
            </span>
          </div>
          <p class="d-body text-ink leading-[1.5] mt-[0.9cqw]">
            "Timing is decent actually — we're hiring an AE in Q3. Can you send
            over what a pilot would look like?"
          </p>
        </div>

        <div class="flex flex-col gap-[0.7cqw] justify-center">
          <.stage name="To contact" count="18" />
          <.stage name="In conversation" count="14" active />
          <.stage name="Call booked" count="6" />
          <.stage name="Won" count="3" tone={:green} />
        </div>
      </div>
    </div>
    """
  end

  ## ---------- f · cta ----------

  defp cta(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full text-center">
      <div class="d-kicker text-inkFaint">Pricing</div>
      <h2 class="d-h2 mt-[1cqw]">One price for the <em>whole</em> funnel.</h2>
      <p class="d-body text-inkSoft mt-[1.2cqw] mx-auto max-w-[54cqw]">
        Targeting, enrichment, verification, sending and reply handling are in every plan.
        EUR, excl. VAT. Cancel anytime.
      </p>

      <div class="grid grid-cols-3 gap-[1.4cqw] mt-[2.4cqw] text-left">
        <.tier name="Starter" price="€49" contacts="50" screened="1,000" />
        <.tier name="Growth" price="€159" contacts="200" screened="4,000" popular />
        <.tier name="Scale" price="€699" contacts="1,000" screened="20,000" />
      </div>

      <div class="mt-[2.6cqw]">
        <button type="button" phx-click="cta" class="d-btn">Start a campaign →</button>
        <div class="d-fine text-inkFaint mt-[1cqw]">
          The first thing it asks you is that one sentence. About ten minutes to live.
        </div>
      </div>
    </div>
    """
  end

  ## ---------- g · short deck's condensed close ----------

  defp short_cta(assigns) do
    ~H"""
    <div class="d-pad flex flex-col justify-center h-full">
      <div class="d-kicker text-inkFaint">And then it runs itself</div>
      <h2 class="d-h2 mt-[1cqw]">From a sentence to <em>booked calls</em>.</h2>

      <div class="grid grid-cols-3 gap-[1.4cqw] mt-[2.6cqw]">
        <.mini
          n="01"
          title="Fits, not volume"
          body="Reads every matching company's site and keeps only the ones that match your description."
          stat="141 of 512"
        />
        <.mini
          n="02"
          title="Written in your voice"
          body="Finds the named person, verifies the address, writes per company, sends from your inboxes."
          stat="2,400 sent"
        />
        <.mini
          n="03"
          title="Replies, sorted"
          body="Interested, not now, wrong person — sorted by intent and moved into a sales funnel."
          stat="160 interested"
          tone={:green}
        />
      </div>

      <div class="d-card mt-[2.2cqw] px-[2cqw] py-[1.6cqw] flex items-center justify-between">
        <div>
          <div class="d-h3 font-bold">
            Every plan includes the <em>whole</em> funnel.
          </div>
          <div class="d-fine text-inkFaint mt-[0.5cqw]">
            From €49/month. EUR, excl. VAT. Cancel anytime. About ten minutes to live.
          </div>
        </div>
        <button type="button" phx-click="cta" class="d-btn shrink-0">Start a campaign →</button>
      </div>
    </div>
    """
  end

  ## ---------- pieces ----------

  attr :no, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :atom, default: :plain
  slot :inner_block, required: true

  defp pstep(assigns) do
    ~H"""
    <div
      class="d-card flex-1 px-[1.1cqw] pt-[1cqw] pb-[1.2cqw] text-center flex flex-col items-center gap-[0.5cqw]"
      style={ring_style(@tone)}
    >
      <span class="d-step-no" style={tone_style(@tone)}>{@no}</span>
      <div class="d-fine text-inkFaint font-semibold uppercase tracking-[0.06em]">{@label}</div>
      <div class="d-num-sm" style={ink_style(@tone)}>{@value}</div>
      <div class="d-fine text-inkSoft leading-[1.3]">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :job, :string, required: true
  attr :svc, :string, required: true

  defp ot(assigns) do
    ~H"""
    <div class="flex items-center gap-[0.9cqw] bg-bgSoft border border-border rounded-[8px] px-[1.1cqw] py-[0.85cqw] opacity-[0.82]">
      <span class="d-x">✕</span>
      <div>
        <div class="d-body font-medium text-inkSoft leading-none">{@job}</div>
        <div class="d-fine text-inkFaint mt-[0.3cqw]">{@svc}</div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, required: true
  attr :tone, :atom, default: :plain

  defp stat(assigns) do
    ~H"""
    <div class="d-card px-[1.1cqw] py-[1.1cqw]" style={tone_style(@tone)}>
      <div class="d-fine text-inkSoft font-semibold">{@label}</div>
      <div class="d-num" style={ink_style(@tone)}>{@value}</div>
      <div class="d-fine text-inkFaint">{@sub}</div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :count, :string, required: true
  attr :active, :boolean, default: false
  attr :tone, :atom, default: :plain

  defp stage(assigns) do
    ~H"""
    <div
      class="d-card flex items-center justify-between px-[1.2cqw] py-[0.8cqw]"
      style={@active && tone_style(:accent)}
    >
      <span class="flex items-center gap-[0.7cqw]">
        <span
          class="d-dot"
          style={"background:var(--#{if @tone == :green, do: "green", else: "accent"});"}
        />
        <span class={["d-body font-medium", @active && "text-accent"]}>{@name}</span>
      </span>
      <span class={["d-body font-bold tabular-nums", @active && "text-accent"]}>{@count}</span>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :contacts, :string, required: true
  attr :screened, :string, required: true
  attr :popular, :boolean, default: false

  defp tier(assigns) do
    ~H"""
    <div
      class="d-card px-[1.5cqw] py-[1.5cqw] relative"
      style={
        @popular &&
          "border-color:var(--accent);box-shadow:0 0 0 4px var(--accentSoft),var(--shadow-card);"
      }
    >
      <div class="d-fine text-inkSoft font-semibold uppercase tracking-[0.06em]">{@name}</div>
      <div class="d-num mt-[0.4cqw]">{@price}<span class="d-fine text-inkFaint">/mo</span></div>
      <div class="d-body text-ink mt-[0.8cqw]">
        <b>{@contacts}</b> contacts / month
      </div>
      <div class="d-fine text-inkFaint mt-[0.3cqw]">up to {@screened} screened</div>
    </div>
    """
  end

  attr :n, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :stat, :string, required: true
  attr :tone, :atom, default: :plain

  defp mini(assigns) do
    ~H"""
    <div class="d-card px-[1.4cqw] py-[1.4cqw]">
      <span class="d-step-no bg-bgSoft text-inkFaint">{@n}</span>
      <div class="d-h4 font-bold mt-[0.9cqw]">{@title}</div>
      <p class="d-body text-inkSoft leading-[1.5] mt-[0.6cqw]">{@body}</p>
      <div class="d-num-sm mt-[1cqw]" style={ink_style(if @tone == :green, do: :green, else: :accent)}>
        {@stat}
      </div>
    </div>
    """
  end

  attr :size, :float, default: 2.0

  defp logo(assigns) do
    ~H"""
    <span
      class="grid place-items-center bg-accent text-white font-bold shrink-0"
      style={"width:#{@size}cqw;height:#{@size}cqw;border-radius:#{@size / 3.7}cqw;font-size:#{@size * 0.58}cqw;"}
    >
      L
    </span>
    """
  end

  ## ---------- helpers ----------

  # Tone overrides go through inline style rather than utility classes: the
  # `d-*` slide styles are a plain stylesheet, so a class would lose the
  # specificity fight while an inline style always wins.
  defp tone_style(:accent),
    do: "background:var(--accentSoft);border-color:var(--accentRing);color:var(--accent);"

  defp tone_style(:green),
    do: "background:var(--greenSoft);border-color:#bfe3d1;color:var(--green);"

  defp tone_style(_), do: nil

  defp ring_style(:accent), do: "border-color:var(--accentRing);"
  defp ring_style(:green), do: "border-color:#bfe3d1;"
  defp ring_style(_), do: nil

  defp ink_style(:accent), do: "color:var(--accent);"
  defp ink_style(:green), do: "color:var(--green);"
  defp ink_style(_), do: nil

  defp approx(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp approx(n) when n >= 1_000, do: "#{div(n, 1000)}k"
  defp approx(n), do: to_string(n)

  defp countries_line([]), do: "Estonia, Finland, Latvia and Lithuania live today."

  defp countries_line(countries) do
    live =
      countries
      |> Enum.filter(& &1.available)
      |> Enum.map(& &1.name)

    case live do
      [] -> "Coming soon."
      names -> Enum.join(names, " · ") <> " — live today."
    end
  end
end
