defmodule ColtWeb.SearchLive do
  @moduledoc """
  Global contact search. Type a phone number (or name / email / company) and
  see which of the owner's campaigns that person is in. Owner-scoped via
  `CampaignContact.search/1`. No click-through yet — there is no contact page.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.CampaignContact
  alias ColtWeb.Components.Liid
  alias Phoenix.LiveView.JS

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Search"), query: "", results: [])}
  end

  @min_query_length 3

  def handle_event("search", %{"q" => q}, socket) do
    results =
      case String.trim(q) do
        trimmed when byte_size(trimmed) >= @min_query_length ->
          CampaignContact.search!(trimmed, actor: socket.assigns.current_user)

        _ ->
          []
      end

    {:noreply, assign(socket, query: q, results: results)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-[760px] w-full">
        <Liid.headline
          kicker={gettext("Global search")}
          sub={
            gettext(
              "Type a phone number, name, email, or company to find them across all your campaigns."
            )
          }
        >
          {raw(gettext("Find a <em>contact</em>."))}
        </Liid.headline>

        <form phx-change="search" class="mt-8">
          <div class="relative">
            <span class="absolute left-4 top-1/2 -translate-y-1/2 text-inkFaint pointer-events-none">
              <Liid.icon name="search" size={18} />
            </span>
            <input
              type="text"
              name="q"
              value={@query}
              autocomplete="off"
              phx-debounce="200"
              autofocus
              phx-mounted={JS.focus()}
              placeholder={gettext("e.g. +372 5123 4567, Jane Doe, jane@acme.com")}
              class="w-full pl-11 pr-4 py-3.5 text-[15px] text-ink bg-card border border-border rounded-[11px] [box-shadow:var(--shadow)] outline-none focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentRing)] placeholder:text-inkFaint"
            />
          </div>
        </form>

        <div
          :if={searchable?(@query)}
          class="mt-3 text-[11.5px] text-inkFaint tracking-[0.02em] tabular-nums"
        >
          {ngettext("%{count} contact", "%{count} contacts", length(@results),
            count: length(@results)
          )}
        </div>

        <div
          :if={searchable?(@query) and @results == []}
          class="mt-4 border border-border rounded-[11px] bg-card px-8 py-10 text-center [box-shadow:var(--shadow)]"
        >
          <div class="text-[15px] font-semibold text-ink">
            {gettext("No matching contacts.")}
          </div>
          <div class="mt-2 text-[13px] text-inkSoft">
            {gettext("Nobody in your campaigns matches that.")}
          </div>
        </div>

        <ul :if={@results != []} class="mt-4 flex flex-col gap-3">
          <li
            :for={c <- @results}
            class="bg-card border border-border rounded-[11px] px-5 py-4 [box-shadow:var(--shadow)]"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="text-[16px] font-bold tracking-[-0.01em] text-ink truncate">
                  {c.person.name || gettext("Unnamed contact")}
                </div>
                <div
                  :if={c.person.title}
                  class="mt-0.5 text-[12.5px] text-inkSoft truncate"
                >
                  {c.person.title}
                </div>
              </div>
              <.status_chip status={c.status} />
            </div>

            <div class="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1.5 text-[13px]">
              <a
                :if={c.person.phone}
                href={"tel:#{c.person.phone}"}
                class="inline-flex items-center gap-1.5 text-accent no-underline hover:underline tabular-nums"
              >
                <Liid.icon name="phone" size={13} /> {c.person.phone}
              </a>
              <a
                :if={c.person.email}
                href={"mailto:#{c.person.email}"}
                class="inline-flex items-center gap-1.5 text-inkSoft no-underline hover:text-ink"
              >
                <Liid.icon name="mail" size={13} /> {c.person.email}
              </a>
            </div>

            <div class="mt-3 pt-3 border-t border-border/70">
              <div class="text-[13px] font-semibold text-ink">
                {c.person.company && c.person.company.name}
              </div>
              <div
                :if={c.person.company && c.person.company.ai_summary}
                class="mt-1 text-[12.5px] leading-[1.5] text-inkSoft line-clamp-2"
              >
                {c.person.company.ai_summary}
              </div>
            </div>

            <div class="mt-3 text-[11px] text-inkFaint tracking-[0.03em] flex items-center gap-1.5">
              <Liid.icon name="grid" size={12} />
              <span class="uppercase tracking-[0.06em] font-semibold">{gettext("Campaign")}</span>
              <span>·</span>
              <span class="text-inkSoft normal-case tracking-normal">{c.campaign.name}</span>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp searchable?(query), do: byte_size(String.trim(query)) >= @min_query_length

  attr :status, :atom, required: true

  defp status_chip(assigns) do
    {state, label} = status_meta(assigns.status)
    assigns = assign(assigns, state: state, label: label)

    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 text-[11px] font-semibold tracking-[0.02em] text-inkSoft">
      <Liid.status_dot state={@state} size={7} />
      {@label}
    </span>
    """
  end

  defp status_meta(:pending_approval), do: {:idle, gettext("Pending")}
  defp status_meta(:approved), do: {:work, gettext("Approved")}
  defp status_meta(:sending), do: {:work, gettext("Sending")}
  defp status_meta(:replied), do: {:done, gettext("Replied")}
  defp status_meta(:call_ready), do: {:done, gettext("Call ready")}
  defp status_meta(:no_reply), do: {:skip, gettext("No reply")}
  defp status_meta(:bounced), do: {:fail, gettext("Bounced")}
  defp status_meta(:failed), do: {:fail, gettext("Failed")}
  defp status_meta(_), do: {:idle, gettext("Unknown")}
end
