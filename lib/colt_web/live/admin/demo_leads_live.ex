defmodule ColtWeb.Admin.DemoLeadsLive do
  @moduledoc """
  `/admin/demo-leads` — what people chose at the end of the `/demo` deck.

  Three kinds land here: someone asking for a call, someone saying Liid isn't
  what they need, and the bare record that someone went off to register. The
  third has nothing to act on but is the denominator for the other two, so it
  is listed rather than hidden.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.DemoLead

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Demo leads") |> load()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    lead = DemoLead.get!(id, actor: actor)
    {:ok, _} = DemoLead.toggle(lead, actor: actor)

    {:noreply, load(socket)}
  end

  defp load(socket) do
    assign(socket, :items, DemoLead.list!(actor: socket.assigns.current_user))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">Demo leads</h1>

        <div :if={@items == []} class="text-ink55 text-[13px]">
          Nothing submitted yet.
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.card :for={item <- @items} item={item} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true

  defp card(assigns) do
    ~H"""
    <div
      class={[
        "border border-border rounded-[11px] bg-card p-5 flex flex-col gap-3",
        @item.status == :done && "opacity-60"
      ]}
      style="box-shadow:var(--shadow)"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="flex items-center gap-2 text-[10px] font-semibold tracking-[0.08em] uppercase">
          <span class={["w-1.5 h-1.5 rounded-full shrink-0", dot_class(@item)]} />
          <span class={kind_class(@item.kind)}>{kind_label(@item.kind)}</span>
          <span class="text-ink40 normal-case font-normal tracking-normal tabular-nums">
            · {format_when(@item.inserted_at)}
          </span>
        </div>
        <div class="text-[11px] text-ink40 truncate max-w-[180px]">{@item.variant}</div>
      </div>

      <div :if={contact_line(@item) != ""} class="text-[15px] font-semibold text-ink">
        {contact_line(@item)}
      </div>

      <div :if={@item.message} class="text-[14px] leading-[1.5] whitespace-pre-wrap text-ink">
        {@item.message}
      </div>

      <div class="flex items-center justify-between gap-3">
        <div class="text-[11px] text-ink40 truncate">
          slide: {@item.slide}
          <%= if @item.campaign_contact do %>
            · {contact_name(@item.campaign_contact)}
          <% end %>
        </div>
        <button
          type="button"
          phx-click="toggle"
          phx-value-id={@item.id}
          class="text-[11px] font-semibold uppercase tracking-[0.06em] text-ink55 hover:text-ink cursor-pointer border border-borderStrong rounded-[8px] px-3 py-1.5 bg-card shrink-0"
        >
          {if @item.status == :new, do: "mark done", else: "reopen"}
        </button>
      </div>
    </div>
    """
  end

  defp contact_line(item) do
    [item.name, item.phone, item.email]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  # English, like the rest of /admin. The Estonian labels belong on the deck
  # and in the Discord ping, not here.
  defp contact_name(%{person: %{name: name}}) when is_binary(name), do: name
  defp contact_name(_), do: "linked contact"

  defp kind_label(:call_request), do: "wants a call"
  defp kind_label(:not_a_fit), do: "not a fit"
  defp kind_label(:try_it), do: "went to register"

  defp kind_class(:call_request), do: "text-accent"
  defp kind_class(:not_a_fit), do: "text-amber"
  defp kind_class(:try_it), do: "text-ink55"

  defp dot_class(%{status: :done}), do: "bg-green"
  defp dot_class(%{kind: :call_request}), do: "bg-accent"
  defp dot_class(_), do: "bg-amber"

  defp format_when(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
