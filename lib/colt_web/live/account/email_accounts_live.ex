defmodule ColtWeb.Account.EmailAccountsLive do
  use ColtWeb, :live_view

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Email accounts")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active={:email_accounts}>
      <ColtWeb.Sending.Stubs.coming_soon
        kicker="Account · Email accounts"
        title="Inbox connect lands in phase E1."
        body="Connect Gmail, Outlook or IMAP inboxes through Nylas's hosted auth. Connected inboxes here can be selected per-campaign in Sending accounts."
      />
    </Layouts.app>
    """
  end
end
