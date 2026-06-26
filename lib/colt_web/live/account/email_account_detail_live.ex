defmodule ColtWeb.Account.EmailAccountDetailLive do
  @moduledoc """
  One connected inbox's own page: edit the signature (appended to nothing —
  the AI writer mirrors it, and hand-written first emails are seeded with it)
  and the daily quota, jump to sending stats, or disconnect.
  """
  use ColtWeb, :live_view

  alias Colt.Nylas
  alias Colt.Resources.EmailAccount
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"account_id" => account_id}, _session, socket) do
    actor = socket.assigns.current_user

    case EmailAccount.get(account_id, actor: actor) do
      {:ok, account} ->
        {:ok,
         assign(socket,
           page_title: gettext("Inbox — %{address}", address: account.address),
           account: account
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/email-accounts")}
    end
  end

  def handle_event("set_signature", %{"value" => raw}, socket) do
    sig = raw |> to_string() |> String.trim()
    sig = if sig == "", do: nil, else: sig

    case EmailAccount.update_details(socket.assigns.account, sig,
           actor: socket.assigns.current_user
         ) do
      {:ok, account} -> {:noreply, assign(socket, account: account)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_quota", %{"value" => raw}, socket) do
    quota =
      case Integer.parse(to_string(raw)) do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    case EmailAccount.set_quota(socket.assigns.account, quota, actor: socket.assigns.current_user) do
      {:ok, account} -> {:noreply, assign(socket, account: account)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("disconnect", _params, socket) do
    user = socket.assigns.current_user

    with :ok <- revoke_at_nylas(socket.assigns.account),
         {:ok, _} <- EmailAccount.disconnect(socket.assigns.account, actor: user) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Inbox disconnected. Billing stopped at Nylas."))
       |> push_navigate(to: ~p"/email-accounts")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Could not disconnect — Nylas is still billing for this inbox. Retry in a moment. (%{reason})",
             reason: inspect(reason)
           )
         )}
    end
  end

  # Revoke MUST succeed before we mark the row :disconnected — Nylas bills per
  # active grant, so a silent local-only state change would leak money.
  defp revoke_at_nylas(%{nylas_grant_id: nil}), do: :ok
  defp revoke_at_nylas(account), do: Nylas.revoke(account)

  defp status_chip_class(:healthy), do: "bg-greenSoft text-green"
  defp status_chip_class(:paused_bounces), do: "bg-amberSoft text-amber"
  defp status_chip_class(:auth_error), do: "bg-redSoft text-red"
  defp status_chip_class(_), do: "bg-paperAlt text-inkFaint"

  defp status_dot_style(:healthy), do: "background:var(--green)"
  defp status_dot_style(:paused_bounces), do: "background:var(--amber)"
  defp status_dot_style(:auth_error), do: "background:var(--red)"
  defp status_dot_style(_), do: "background:var(--inkFaint)"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:email_accounts}>
      <div class="max-w-[720px] w-full pb-16">
        <div class="mb-10">
          <Liid.headline kicker={gettext("Account · Email accounts")}>
            {raw(gettext("Inbox <em>settings</em>."))}
          </Liid.headline>
          <div class="flex items-center gap-2 mt-5">
            <.link navigate={~p"/email-accounts"} class="no-underline">
              <Liid.btn size={:small} mono>
                <Liid.icon name="chev-l" size={11} /> {gettext("All accounts")}
              </Liid.btn>
            </.link>
            <.link navigate={~p"/email-accounts/#{@account.id}/stats"} class="no-underline">
              <Liid.btn size={:small} mono>
                {gettext("Sending stats")} <Liid.icon name="arrow" size={11} />
              </Liid.btn>
            </.link>
          </div>
        </div>

        <div
          class="border border-border rounded-[11px] bg-card px-6 py-5 mb-4"
          style="box-shadow:var(--shadow)"
        >
          <div class="text-[19px] font-bold tracking-[-0.01em] truncate text-ink">
            {@account.address}
          </div>
          <div class="mt-2 flex items-center gap-2 flex-wrap">
            <span class="inline-flex items-center text-[10.5px] font-semibold tracking-[0.04em] uppercase text-inkSoft bg-paperAlt rounded-[8px] px-2 py-0.5">
              {@account.provider}
            </span>
            <span class={[
              "inline-flex items-center gap-1.5 text-[10.5px] font-semibold tracking-[0.04em] uppercase rounded-[8px] px-2 py-0.5",
              status_chip_class(@account.status)
            ]}>
              <span class="w-1.5 h-1.5 rounded-full" style={status_dot_style(@account.status)}></span>
              {@account.status}
            </span>
            <span :if={@account.tz} class="text-[11px] text-inkFaint tracking-[0.04em]">
              {@account.tz}
            </span>
          </div>
        </div>

        <div
          :if={@account.status != :disconnected}
          class="border border-border rounded-[11px] bg-card px-6 py-5 mb-4"
          style="box-shadow:var(--shadow)"
        >
          <label class="block text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-2">
            {gettext("Daily quota")}
          </label>
          <p class="text-[12px] text-inkSoft mb-3 leading-relaxed">
            {gettext("The most outreach emails Liid will send from this inbox per day.")}
          </p>
          <form id="quota-form" phx-change="set_quota" class="flex items-center gap-2">
            <input
              type="number"
              id="quota-input"
              name="value"
              value={@account.daily_quota}
              min="0"
              phx-debounce="400"
              class="w-[80px] px-2.5 py-2 border border-border rounded-[8px] text-[15px] font-semibold text-center bg-card text-ink tabular-nums outline-none focus:border-accent"
            />
            <span class="text-[11px] text-inkFaint tracking-[0.04em]">{gettext("emails / day")}</span>
          </form>
        </div>

        <div
          :if={@account.status != :disconnected}
          class="border border-border rounded-[11px] bg-card px-6 py-5 mb-4"
          style="box-shadow:var(--shadow)"
        >
          <form id="signature-form" phx-change="set_signature">
            <label class="block text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-2">
              {gettext("Signature")}
            </label>
            <p class="text-[12px] text-inkSoft mb-3 leading-relaxed">
              {gettext(
                "Your sign-off — name, and optionally phone, title, company. The writer reuses these details in the style of your past emails; your first hand-written sequence starts with it pre-filled in the body."
              )}
            </p>
            <textarea
              id="signature-input"
              name="value"
              rows="5"
              phx-debounce="500"
              phx-update="ignore"
              placeholder={gettext("Jane Doe\nHead of Sales, Acme\n+372 5555 1234")}
              class="w-full px-3 py-2.5 border border-border rounded-[8px] text-[13px] leading-relaxed bg-card text-ink outline-none focus:border-accent resize-y whitespace-pre-wrap"
            >{@account.display_name}</textarea>
          </form>
        </div>

        <div :if={@account.status != :disconnected} class="flex justify-end">
          <Liid.btn
            size={:small}
            mono
            phx-click="disconnect"
            phx-disable-with={gettext("Disconnecting…")}
            data-confirm={gettext("Disconnect %{address}?", address: @account.address)}
          >
            {gettext("Disconnect")}
          </Liid.btn>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
