defmodule ColtWeb.Account.EmailAccountsLive do
  use ColtWeb, :live_view

  alias Colt.Jobs.ImportMailbox
  alias Colt.Resources.{EmailAccount, OutboundEmail}
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

  @avg_window_days 7

  defp load_accounts(socket) do
    user = socket.assigns.current_user
    accounts = EmailAccount.list_for_user!(user.id, actor: user)

    assign(socket, accounts: accounts, daily_avg: daily_avg(user))
  end

  # One read of the user's sent mail over the trailing window, grouped per
  # inbox into a sent/day average shown on each row.
  defp daily_avg(user) do
    since = DateTime.add(DateTime.utc_now(), -@avg_window_days * 86_400, :second)

    OutboundEmail.list_sent_for_user_since!(user.id, since, actor: user)
    |> Enum.frequencies_by(& &1.email_account_id)
    |> Map.new(fn {id, n} -> {id, n / @avg_window_days} end)
  end

  defp daily_avg_label(avg) when is_float(avg), do: :erlang.float_to_binary(avg, decimals: 1)
  defp daily_avg_label(_), do: "0"

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

        <div :if={@accounts != []} class="space-y-3">
          <div
            :for={a <- @accounts}
            id={"acct-#{a.id}"}
            class="flex items-stretch border border-border rounded-[11px] bg-card overflow-hidden"
            style="box-shadow:var(--shadow)"
          >
            <.link
              navigate={~p"/email-accounts/#{a.id}/settings"}
              class="flex-1 min-w-0 no-underline py-4 pl-5 pr-4 hover:bg-paperAlt"
            >
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
              </div>
            </.link>

            <.link
              navigate={~p"/email-accounts/#{a.id}/stats"}
              title={gettext("Sending stats")}
              class="group no-underline shrink-0 text-right py-4 px-5 border-l border-border hover:bg-paperAlt"
            >
              <div class="text-[22px] leading-none font-bold tabular-nums tracking-[-0.02em] text-ink group-hover:text-accent">
                {daily_avg_label(@daily_avg[a.id])}
              </div>
              <div class="mt-1.5 text-[10.5px] tracking-[0.06em] uppercase text-inkFaint font-semibold">
                {gettext("avg/day · 7d")}
              </div>
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
