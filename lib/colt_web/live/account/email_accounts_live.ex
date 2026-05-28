defmodule ColtWeb.Account.EmailAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Nylas
  alias Colt.Resources.EmailAccount
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Email accounts"))
     |> load_accounts()}
  end

  def handle_event("disconnect", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with {:ok, account} <- EmailAccount.get(id, actor: user),
         :ok <- revoke_at_nylas(account),
         {:ok, _} <- EmailAccount.disconnect(account, actor: user) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Inbox disconnected. Billing stopped at Nylas."))
       |> load_accounts()}
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

  def handle_event("set_quota", %{"id" => id, "value" => raw}, socket) do
    quota =
      case Integer.parse(to_string(raw)) do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    user = socket.assigns.current_user

    with {:ok, account} <- EmailAccount.get(id, actor: user),
         {:ok, _} <- EmailAccount.set_quota(account, quota, actor: user) do
      {:noreply, load_accounts(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp load_accounts(socket) do
    accounts =
      EmailAccount.list_for_user!(socket.assigns.current_user.id,
        actor: socket.assigns.current_user
      )

    assign(socket, accounts: accounts)
  end

  # Revoke MUST succeed before we mark the row :disconnected — Nylas bills per
  # active grant, so a silent local-only state change would leak money.
  defp revoke_at_nylas(%{nylas_grant_id: nil}), do: :ok
  defp revoke_at_nylas(account), do: Nylas.revoke(account)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:email_accounts}>
      <div class="max-w-[860px] w-full">
        <div class="flex items-end justify-between gap-6 mb-10">
          <Liid.headline
            kicker={gettext("Account · Email accounts")}
            sub={
              gettext(
                "Inboxes you've connected through Nylas. Pick any of them per campaign under Sending accounts."
              )
            }
          >
            {raw(gettext("Connected <em>inboxes</em>."))}
          </Liid.headline>
        </div>

        <div class="flex flex-wrap gap-3 mb-10">
          <.link href={~p"/email-accounts/connect/google"} class="no-underline">
            <Liid.btn variant={:primary} mono>
              {gettext("Connect Gmail")} <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
          <.link href={~p"/email-accounts/connect/m365"} class="no-underline">
            <Liid.btn mono>
              {gettext("Connect Outlook")} <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
          <.link href={~p"/email-accounts/connect/imap"} class="no-underline">
            <Liid.btn mono>
              {gettext("Connect IMAP")} <Liid.icon name="arrow" />
            </Liid.btn>
          </.link>
        </div>

        <div
          :if={@accounts == []}
          class="border border-rule rounded-[2px] bg-paper px-8 py-12 text-center"
        >
          <div class="font-serif text-[24px] tracking-[-0.02em] text-ink">
            {gettext("No inboxes yet.")}
          </div>
          <div class="mt-2 text-[13px] text-ink55">
            {gettext("Hit \"Connect\" above and Nylas's hosted auth will walk you through it.")}
          </div>
        </div>

        <ul :if={@accounts != []} class="border-t border-rule">
          <li :for={a <- @accounts} class="border-b border-rule">
            <div class="flex items-center gap-6 py-4 px-2">
              <div class="flex-1 min-w-0">
                <div class="font-serif text-[20px] tracking-[-0.015em] truncate">
                  {a.address}
                </div>
                <div class="mt-1 font-mono text-[11px] text-ink40 tracking-[0.04em] flex items-center gap-3">
                  <span class="uppercase">{a.provider}</span>
                  <span>·</span>
                  <span class="uppercase">{a.status}</span>
                  <span :if={a.tz}>·</span>
                  <span :if={a.tz}>{a.tz}</span>
                </div>
              </div>
              <form
                :if={a.status != :disconnected}
                phx-change="set_quota"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="id" value={a.id} />
                <label class="font-mono text-[10px] tracking-[0.08em] uppercase text-ink55">
                  {gettext("quota")}
                </label>
                <input
                  type="number"
                  name="value"
                  value={a.daily_quota}
                  min="0"
                  phx-debounce="400"
                  class="w-[64px] px-2 py-1 border border-ink20 rounded-[2px] font-mono text-[12px] text-center bg-paper text-ink tabular-nums outline-none"
                />
                <span class="font-mono text-[10px] text-ink40">{gettext("/day")}</span>
              </form>
              <.link
                navigate={~p"/email-accounts/#{a.id}/stats"}
                class="no-underline px-2.5 py-1 border border-ink20 font-mono text-[10px] tracking-[0.08em] uppercase text-ink55 rounded-[2px] hover:text-ink hover:border-ink40"
              >
                {gettext("stats")}
              </.link>
              <Liid.btn
                :if={a.status != :disconnected}
                size={:small}
                mono
                phx-click="disconnect"
                phx-value-id={a.id}
                phx-disable-with={gettext("Disconnecting…")}
                data-confirm={gettext("Disconnect %{address}?", address: a.address)}
              >
                {gettext("Disconnect")}
              </Liid.btn>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
