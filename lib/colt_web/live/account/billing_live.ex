defmodule ColtWeb.Account.BillingLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Billing")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:billing}>
      <div class="max-w-[640px] border border-rule rounded-[2px] bg-paper p-8">
        <div class="font-mono text-[11px] tracking-[0.12em] uppercase text-ink55 mb-3.5">
          Account · Billing
        </div>
        <h1 class="font-serif font-normal text-[32px] leading-[1.05] tracking-[-0.03em] m-0 text-pretty">
          Plans coming soon.
        </h1>
        <p class="mt-5 text-[15px] leading-[1.55] text-ink55 max-w-[520px] text-pretty">
          Liid is in invite-only beta. Reach out at <a
            href="mailto:hello@liid.app"
            class="underline decoration-ink40 hover:decoration-ink"
          >
            hello@liid.app
          </a>.
        </p>
        <button
          type="button"
          disabled
          class="mt-7 inline-flex items-center gap-2 border rounded-[2px] px-[18px] py-[10px] text-[13px] font-medium bg-ink text-paper border-ink opacity-40 cursor-not-allowed"
        >
          Choose plan
        </button>
      </div>
    </Layouts.app>
    """
  end
end
