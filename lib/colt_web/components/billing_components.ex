defmodule ColtWeb.Components.BillingComponents do
  @moduledoc """
  Pricing / plan card components. Reused by the public `/pricing` page and
  the in-app `/billing` upgrade grid.
  """
  use Phoenix.Component
  use ColtWeb, :verified_routes
  use Gettext, backend: ColtWeb.Gettext

  @plan_features [
    {"ICP fit scoring",
     "Every prospect graded against your ideal profile before it reaches you."},
    {"AI learns your writing style",
     "Drafts match how you actually write — not generic outreach."},
    {"Multiple domains per campaign",
     "Rotate sending across all your domains under one campaign."},
    {"Automatic follow-ups", "Sequenced touches that stop the moment someone replies."},
    {"Direct sending", "Outreach goes from your mailboxes — no separate sender to warm up."}
  ]

  def plan_features, do: @plan_features

  @doc "Resolves configured Stripe price ids keyed by tier."
  def configured_prices do
    cap = Application.get_env(:colt, Colt.Billing, [])[:price_capacity] || %{}
    by_cap = Map.new(cap, fn {pid, c} -> {c, pid} end)
    %{starter: by_cap[50], growth: by_cap[200], scale: by_cap[1000]}
  end

  @doc """
  A single pricing card. `cta` is a slot that contains the action (form/link/button).
  """
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :price_suffix, :string, default: "/month"
  attr :tagline, :string, default: nil
  attr :highlight, :boolean, default: false
  attr :class, :string, default: nil
  slot :cta, required: true

  def plan_card(assigns) do
    assigns = assign(assigns, :features, @plan_features)

    ~H"""
    <div class={[
      "flex flex-col border rounded-[2px] bg-paper p-7",
      @highlight && "border-ink",
      !@highlight && "border-rule",
      @class
    ]}>
      <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-4">
        {@name}
      </div>
      <div class="flex items-baseline gap-1">
        <span class="font-mono text-[40px] leading-none tracking-[-0.02em] text-ink">{@price}</span>
        <span class="font-mono text-[12px] text-ink55">{@price_suffix}</span>
      </div>
      <p :if={@tagline} class="mt-3 text-[14px] leading-[1.5] text-ink55 min-h-[42px]">
        {@tagline}
      </p>
      <ul class="mt-6 space-y-2.5 flex-1">
        <li :for={{title, body} <- @features} class="text-[13px] leading-[1.5] text-ink70">
          <span class="text-ink">{title}.</span>
          <span class="text-ink55">{body}</span>
        </li>
      </ul>
      <div class="mt-7">
        {render_slot(@cta)}
      </div>
    </div>
    """
  end

  @doc """
  Grid of all three priced plans + a "contact us" card.
  `mode` is `:public` (anon → /sign-in) or `:authed` (POST /billing/checkout).
  """
  attr :mode, :atom, default: :public, values: [:public, :authed]
  attr :prices, :map, default: %{}

  def plan_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <.plan_card name="Starter" price="49€" tagline="50 enriched contacts every month.">
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:starter]} label="Start with 50" />
        </:cta>
      </.plan_card>

      <.plan_card name="Growth" price="159€" tagline="200 enriched contacts every month." highlight>
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:growth]} label="Start with 200" />
        </:cta>
      </.plan_card>

      <.plan_card name="Scale" price="699€" tagline="1,000 enriched contacts every month.">
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:scale]} label="Start with 1,000" />
        </:cta>
      </.plan_card>

      <.plan_card
        name="Enterprise"
        price="Contact"
        price_suffix=""
        tagline="More than 1,000 a month, custom domains, dedicated support."
      >
        <:cta>
          <a
            href="mailto:hello@liid.app?subject=Enterprise%20plan"
            class="inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[13px] font-medium bg-transparent text-ink border-ink20 no-underline"
          >
            Email us
          </a>
        </:cta>
      </.plan_card>
    </div>
    """
  end

  attr :mode, :atom, required: true
  attr :price_id, :string, default: nil
  attr :label, :string, required: true

  defp checkout_cta(%{mode: :authed, price_id: price_id} = assigns) when is_binary(price_id) do
    ~H"""
    <form action={~p"/billing/checkout"} method="post" class="contents">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="price_id" value={@price_id} />
      <button
        type="submit"
        class="inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[13px] font-medium bg-ink text-paper border-ink cursor-pointer"
      >
        {@label}
      </button>
    </form>
    """
  end

  defp checkout_cta(%{mode: :public} = assigns) do
    ~H"""
    <a
      href={~p"/sign-in"}
      class="inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[13px] font-medium bg-ink text-paper border-ink no-underline"
    >
      {@label}
    </a>
    """
  end

  defp checkout_cta(assigns) do
    ~H"""
    <span class="text-[12px] text-ink55 font-mono">unavailable</span>
    """
  end
end
