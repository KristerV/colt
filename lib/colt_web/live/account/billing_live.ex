defmodule ColtWeb.Account.BillingLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.BillingComponents

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    user =
      socket.assigns.current_user
      |> Ash.load!([:remaining_capacity, :enriched_this_period_count], authorize?: false)

    {:ok,
     assign(socket,
       page_title: gettext("Billing"),
       user: user,
       prices: BillingComponents.configured_prices()
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:billing}>
      <div class="max-w-[1180px] mx-auto w-full space-y-10">
        <section class="border border-rule rounded-[2px] bg-paper p-8">
          <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-3.5">
            {gettext("Account · Billing")}
          </div>
          <h1 class="font-serif font-normal text-[40px] leading-[1.02] tracking-[-0.03em] m-0 text-pretty">
            {status_heading(@user)}
          </h1>

          <div class="mt-8 grid grid-cols-1 md:grid-cols-4 gap-6">
            <.stat label={gettext("Monthly cap")} value={fmt_int(@user.monthly_contact_capacity)} />
            <.stat
              label={gettext("Used this period")}
              value={fmt_int(@user.enriched_this_period_count)}
            />
            <.stat
              label={gettext("Remaining")}
              value={fmt_int(max(@user.remaining_capacity || 0, 0))}
            />
            <.stat label={gettext("Renews")} value={fmt_date(@user.subscription_period_end)} />
          </div>

          <div class="mt-8 flex flex-wrap items-center gap-3">
            <form
              :if={@user.stripe_customer_id}
              action={~p"/billing/portal"}
              method="post"
              class="contents"
            >
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <button
                type="submit"
                class="inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[13px] font-medium bg-ink text-paper border-ink cursor-pointer"
              >
                {gettext("Manage subscription")}
              </button>
            </form>
            <a
              href="mailto:hello@liid.app"
              class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink no-underline"
            >
              {gettext("contact support")}
            </a>
          </div>
        </section>

        <section>
          <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-4">
            {if @user.subscription_status == :active,
              do: gettext("Change plan"),
              else: gettext("Pick a plan")}
          </div>
          <BillingComponents.plan_grid mode={:authed} prices={@prices} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div>
      <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2">
        {@label}
      </div>
      <div class="font-mono text-[28px] leading-none tracking-[-0.02em] text-ink">
        {@value}
      </div>
    </div>
    """
  end

  defp status_heading(%{subscription_status: :active}),
    do: raw(gettext("Your plan is <em class=\"text-accent\">active</em>."))

  defp status_heading(%{subscription_status: :past_due}),
    do: raw(gettext("Payment <em class=\"text-warn\">past due</em>."))

  defp status_heading(%{subscription_status: :canceled}),
    do: raw(gettext("Subscription <em class=\"text-ink55\">canceled</em>."))

  defp status_heading(_),
    do: raw(gettext("Pick a <em class=\"text-accent\">plan</em> to start enriching."))

  defp fmt_int(nil), do: "0"
  defp fmt_int(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt_int(other), do: to_string(other)

  defp fmt_date(nil), do: "—"
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
end
