defmodule ColtWeb.Account.EmailAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Jobs.ImportMailbox
  alias Colt.Nylas
  alias Colt.Resources.EmailAccount
  alias Colt.Services.EmailAccount.ImportMailboxes
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  @max_csv_size 2_000_000

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Email accounts"))
     |> allow_upload(:mailboxes,
       accept: ~w(.csv text/csv),
       max_entries: 1,
       max_file_size: @max_csv_size,
       auto_upload: true,
       progress: &handle_import_progress/3
     )
     |> load_accounts()}
  end

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

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

  def handle_event("set_name", %{"id" => id, "value" => raw}, socket) do
    name = raw |> to_string() |> String.trim()
    name = if name == "", do: nil, else: name
    user = socket.assigns.current_user

    with {:ok, account} <- EmailAccount.get(id, actor: user),
         {:ok, _} <- EmailAccount.update_details(account, name, actor: user) do
      {:noreply, load_accounts(socket)}
    else
      _ -> {:noreply, socket}
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

  # Auto-import fires once the upload finishes; nothing to do until then.
  defp handle_import_progress(:mailboxes, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_import_progress(:mailboxes, %{done?: true}, socket) do
    user = socket.assigns.current_user

    [parsed] =
      consume_uploaded_entries(socket, :mailboxes, fn %{path: path}, _entry ->
        {:ok, ImportMailboxes.run(File.read!(path))}
      end)

    {:noreply, flash_import_result(socket, user, parsed)}
  end

  defp flash_import_result(socket, user, {:ok, [_ | _] = mailboxes}) do
    Enum.each(mailboxes, &ImportMailbox.enqueue(user.id, &1))

    put_flash(
      socket,
      :info,
      gettext(
        "Importing %{n} inbox(es). They'll appear here as Nylas validates each login.",
        n: length(mailboxes)
      )
    )
  end

  defp flash_import_result(socket, _user, {:ok, []}),
    do: put_flash(socket, :error, gettext("No inboxes found in that CSV."))

  defp flash_import_result(socket, _user, {:error, :unknown_format}),
    do:
      put_flash(
        socket,
        :error,
        gettext("Unrecognized CSV — expected a mailboxes or Google Workspace export.")
      )

  defp flash_import_result(socket, _user, _other),
    do: put_flash(socket, :error, gettext("Could not read that CSV."))

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

          <form phx-change="validate_import" class="contents">
            <.live_file_input upload={@uploads.mailboxes} class="sr-only" />
            <label
              for={@uploads.mailboxes.ref}
              class="inline-flex items-center gap-2 border border-ink20 rounded-[2px] font-medium font-mono tracking-[0.04em] cursor-pointer px-[18px] py-[10px] text-[13px] bg-transparent text-ink hover:border-ink"
            >
              {gettext("Import from CSV")} <Liid.icon name="file" size={13} />
            </label>
          </form>
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
                <form
                  :if={a.status != :disconnected}
                  phx-change="set_name"
                  class="mt-2 flex items-center gap-2"
                >
                  <input type="hidden" name="id" value={a.id} />
                  <label class="font-mono text-[10px] tracking-[0.08em] uppercase text-ink55">
                    {gettext("sender name")}
                  </label>
                  <input
                    type="text"
                    name="value"
                    value={a.display_name}
                    placeholder={gettext("e.g. Jane Doe")}
                    phx-debounce="500"
                    class="w-[220px] px-2 py-1 border border-ink20 rounded-[2px] font-mono text-[12px] bg-paper text-ink outline-none focus:border-ink40"
                  />
                </form>
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
