defmodule ColtWeb.Components.BillingComponents do
  @moduledoc """
  Pricing / plan card components. Reused by the public `/pricing` page and
  the in-app `/billing` upgrade grid.
  """
  use Phoenix.Component
  use ColtWeb, :verified_routes
  use Gettext, backend: ColtWeb.Gettext

  @doc "Resolves configured Stripe price ids keyed by tier."
  def configured_prices do
    cap = Application.get_env(:colt, Colt.Billing, [])[:price_capacity] || %{}
    by_cap = Map.new(cap, fn {pid, c} -> {c, pid} end)
    %{starter: by_cap[50], growth: by_cap[200], scale: by_cap[1000]}
  end

  @doc """
  A single pricing card. The caps are the differentiator; every plan includes
  the same two capabilities (enrichment + sending), shown once. `cta` is a slot
  with the action (form/link/button).
  """
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :price_suffix, :string, default: "/month"
  attr :contacts, :string, default: nil
  attr :screened, :string, default: nil
  attr :highlight, :boolean, default: false
  attr :class, :string, default: nil
  slot :cta, required: true

  def plan_card(assigns) do
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

      <div :if={@contacts} class="mt-6 pt-5 border-t border-rule">
        <div class="font-mono text-[22px] leading-none tracking-[-0.02em] text-ink">{@contacts}</div>
        <div
          :if={@screened}
          class="mt-2 font-mono text-[11px] tracking-[0.04em] uppercase text-ink55"
        >
          {@screened}
        </div>
      </div>

      <ul class="mt-6 space-y-2.5 flex-1">
        <li class="flex items-center gap-2.5 text-[13px] text-ink70">
          <span
            class="inline-block w-[5px] h-[5px] rounded-full"
            style="background: var(--color-accent);"
          />
          {gettext("Contact enrichment")}
        </li>
        <li class="flex items-center gap-2.5 text-[13px] text-ink70">
          <span
            class="inline-block w-[5px] h-[5px] rounded-full"
            style="background: var(--color-accent);"
          />
          {gettext("Email sending")}
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
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <.plan_card
        name="Starter"
        price="49€"
        contacts="50 contacts / mo"
        screened="Up to 1,000 companies screened"
      >
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:starter]} label="Start with 50" />
        </:cta>
      </.plan_card>

      <.plan_card
        name="Growth"
        price="159€"
        contacts="200 contacts / mo"
        screened="Up to 4,000 companies screened"
        highlight
      >
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:growth]} label="Start with 200" />
        </:cta>
      </.plan_card>

      <.plan_card
        name="Scale"
        price="699€"
        contacts="1,000 contacts / mo"
        screened="Up to 20,000 companies screened"
      >
        <:cta>
          <.checkout_cta mode={@mode} price_id={@prices[:scale]} label="Start with 1,000" />
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
