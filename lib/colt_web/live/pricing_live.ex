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
    <Layouts.app flash={@flash} current_user={@current_user} landing={true}>
      <div class="max-w-[1180px] mx-auto w-full">
        <section class="pt-10 md:pt-20 pb-10 md:pb-14">
          <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-5">
            {gettext("Liid · pricing")}
          </div>
          <h1 class="font-serif font-normal text-[44px] md:text-[72px] leading-[1.02] tracking-[-0.04em] m-0 max-w-[880px] text-pretty">
            {raw(gettext("Pricing that <em>scales</em> with reach."))}
          </h1>
          <p class="mt-6 text-[15px] md:text-[17px] leading-[1.55] text-ink70 max-w-[640px] text-pretty">
            {gettext(
              "Pick a monthly enrichment cap. Everything else — ICP scoring, AI drafting, multi-domain sending, follow-ups — comes with every plan."
            )}
          </p>
        </section>

        <section class="pb-20 md:pb-28">
          <BillingComponents.plan_grid mode={mode(@current_user)} prices={@prices} />
          <p class="mt-8 text-[12px] text-ink55 font-mono">
            {gettext("Prices are in EUR, excl. VAT. Cancel any time from the billing portal.")}
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp mode(nil), do: :public
  defp mode(_user), do: :authed
end
