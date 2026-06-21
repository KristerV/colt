defmodule ColtWeb.Account.BillingLive do
  use ColtWeb, :live_view

  alias ColtWeb.Components.BillingComponents

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    user =
      socket.assigns.current_user
      |> Ash.load!(
        [
          :remaining_capacity,
          :enriched_this_period_count,
          :monthly_screening_capacity,
          :remaining_screening,
          :screened_this_period_count
        ],
        authorize?: false
      )

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
      <div class="max-w-[1180px] mx-auto w-full space-y-6">
        <section
          class="border border-border rounded-[11px] bg-card p-8"
          style="box-shadow:var(--shadow-card)"
        >
          <div class="text-[11px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-3.5">
            {gettext("Account · Billing")}
          </div>
          <h1 class="text-[25px] font-semibold leading-[1.1] tracking-[-0.02em] m-0 text-pretty text-ink">
            {status_heading(@user)}
          </h1>

          <div
            :if={exhausted?(@user)}
            class="mt-6 bg-amberSoft border border-amber/30 rounded-[8px] px-4 py-3 text-[13px] text-amber"
          >
            {gettext(
              "You've hit a monthly limit — enrichment is paused until you upgrade or your plan renews."
            )}
          </div>

          <div class="mt-8 grid grid-cols-1 md:grid-cols-3 gap-4">
            <.usage_stat
              label={gettext("Contacts")}
              remaining={max(@user.remaining_capacity || 0, 0)}
              cap={@user.monthly_contact_capacity}
            />
            <.usage_stat
              label={gettext("Screenings")}
              remaining={max(@user.remaining_screening || 0, 0)}
              cap={@user.monthly_screening_capacity}
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
                class="inline-flex items-center gap-2 rounded-[8px] px-[18px] py-[10px] text-[13px] font-semibold bg-accent text-white cursor-pointer"
                style="box-shadow:0 1px 2px rgba(59,122,224,.3)"
              >
                {gettext("Manage subscription")}
              </button>
            </form>
            <a
              href="mailto:me@krister.ee"
              class="text-[11px] uppercase tracking-[0.08em] font-semibold text-inkSoft hover:text-ink no-underline"
            >
              {gettext("contact support")}
            </a>
          </div>
        </section>

        <section :if={@user.subscription_status != :active}>
          <div class="text-[11px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-4">
            {gettext("Pick a plan")}
          </div>
          <BillingComponents.plan_grid mode={:authed} prices={@prices} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :remaining, :integer, required: true
  attr :cap, :integer, required: true

  defp usage_stat(assigns) do
    ~H"""
    <div class="border border-border rounded-[11px] bg-card p-5" style="box-shadow:var(--shadow)">
      <div class="text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-2">
        {@label}
      </div>
      <div class="text-[28px] font-bold leading-none tracking-[-0.02em] text-ink tabular-nums">
        {fmt_int(@remaining)}<span class="text-inkFaint">/{fmt_int(@cap)}</span>
      </div>
      <div class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold mt-1.5">
        {gettext("remaining")}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="border border-border rounded-[11px] bg-card p-5" style="box-shadow:var(--shadow)">
      <div class="text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-2">
        {@label}
      </div>
      <div class="text-[28px] font-bold leading-none tracking-[-0.02em] text-ink tabular-nums">
        {@value}
      </div>
    </div>
    """
  end

  defp status_heading(%{subscription_status: :active}),
    do: raw(gettext("Your plan is <em class=\"text-accent\">active</em>."))

  defp status_heading(%{subscription_status: :past_due}),
    do: raw(gettext("Payment <em class=\"text-amber\">past due</em>."))

  defp status_heading(%{subscription_status: :canceled}),
    do: raw(gettext("Subscription <em class=\"text-inkFaint\">canceled</em>."))

  defp status_heading(_),
    do: raw(gettext("Pick a <em class=\"text-accent\">plan</em> to start enriching."))

  defp exhausted?(%{} = user) do
    Colt.Accounts.User.paid?(user) and
      (max(user.remaining_capacity || 0, 0) <= 0 or max(user.remaining_screening || 0, 0) <= 0)
  end

  defp fmt_int(nil), do: "0"
  defp fmt_int(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt_int(other), do: to_string(other)

  defp fmt_date(nil), do: "—"
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
end
