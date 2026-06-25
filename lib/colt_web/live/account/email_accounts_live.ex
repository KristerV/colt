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

  def handle_event("set_name", %{"_id" => id, "value" => raw}, socket) do
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

  def handle_event("set_quota", %{"_id" => id, "value" => raw}, socket) do
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
              class="inline-flex items-center gap-2 border border-borderStrong rounded-[8px] font-semibold cursor-pointer px-[18px] py-[10px] text-[13px] bg-card text-inkSoft hover:text-ink hover:border-ink"
            >
              {gettext("Import from CSV")} <Liid.icon name="file" size={13} />
            </label>
          </form>
        </div>

        <div
          :if={@accounts == []}
          class="border border-border rounded-[11px] bg-card px-8 py-12 text-center"
          style="box-shadow:var(--shadow)"
        >
          <div class="text-[20px] font-bold tracking-[-0.01em] text-ink">
            {gettext("No inboxes yet.")}
          </div>
          <div class="mt-2 text-[13px] text-inkSoft">
            {gettext("Hit \"Connect\" above and Nylas's hosted auth will walk you through it.")}
          </div>
        </div>

        <ul :if={@accounts != []} class="space-y-3">
          <li
            :for={a <- @accounts}
            id={"acct-#{a.id}"}
            class="border border-border rounded-[11px] bg-card"
            style="box-shadow:var(--shadow)"
          >
            <div class="flex flex-col md:flex-row md:items-center gap-4 md:gap-6 py-4 px-5">
              <div class="flex-1 min-w-0">
                <div class="text-[17px] font-bold tracking-[-0.01em] truncate text-ink">
                  {a.address}
                </div>
                <div class="mt-1.5 flex items-center gap-2 flex-wrap">
                  <span class="inline-flex items-center text-[10.5px] font-semibold tracking-[0.04em] uppercase text-inkSoft bg-paperAlt rounded-[8px] px-2 py-0.5">
                    {a.provider}
                  </span>
                  <span class={[
                    "inline-flex items-center gap-1.5 text-[10.5px] font-semibold tracking-[0.04em] uppercase rounded-[8px] px-2 py-0.5",
                    status_chip_class(a.status)
                  ]}>
                    <span class="w-1.5 h-1.5 rounded-full" style={status_dot_style(a.status)}></span>
                    {a.status}
                  </span>
                  <span
                    :if={a.tz}
                    class="text-[11px] text-inkFaint tracking-[0.04em]"
                  >
                    {a.tz}
                  </span>
                </div>
                <form
                  :if={a.status != :disconnected}
                  id={"name-form-#{a.id}"}
                  phx-change="set_name"
                  phx-update="ignore"
                  class="mt-3 flex items-center gap-2"
                >
                  <input type="hidden" name="_id" value={a.id} />
                  <label class="text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold shrink-0">
                    {gettext("sender name")}
                  </label>
                  <input
                    type="text"
                    id={"name-input-#{a.id}"}
                    name="value"
                    value={a.display_name}
                    placeholder={gettext("e.g. Jane Doe")}
                    phx-debounce="500"
                    class="w-full md:w-[220px] px-2.5 py-1.5 border border-border rounded-[8px] text-[12px] bg-card text-ink outline-none focus:border-accent"
                  />
                </form>
              </div>
              <form
                :if={a.status != :disconnected}
                id={"quota-form-#{a.id}"}
                phx-change="set_quota"
                phx-update="ignore"
                class="flex items-center gap-2 shrink-0"
              >
                <input type="hidden" name="_id" value={a.id} />
                <label class="text-[10.5px] tracking-[0.08em] uppercase text-inkSoft font-semibold">
                  {gettext("quota")}
                </label>
                <input
                  type="number"
                  id={"quota-input-#{a.id}"}
                  name="value"
                  value={a.daily_quota}
                  min="0"
                  phx-debounce="400"
                  class="w-[64px] px-2.5 py-1.5 border border-border rounded-[8px] text-[12px] text-center bg-card text-ink tabular-nums outline-none focus:border-accent"
                />
                <span class="text-[10.5px] text-inkFaint">{gettext("/day")}</span>
              </form>
              <div class="flex items-center gap-2 shrink-0">
                <.link
                  navigate={~p"/email-accounts/#{a.id}/stats"}
                  class="no-underline px-3 py-1.5 border border-borderStrong text-[10.5px] tracking-[0.08em] uppercase font-semibold text-inkSoft rounded-[8px] hover:text-ink hover:border-ink"
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
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
