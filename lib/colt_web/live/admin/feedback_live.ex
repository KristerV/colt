defmodule ColtWeb.Admin.FeedbackLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Feedback

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :items, Feedback.list!(actor: socket.assigns.current_user))}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    item = Feedback.get!(id, actor: actor)
    {:ok, _} = Feedback.toggle(item, actor: actor)
    {:noreply, assign(socket, :items, Feedback.list!(actor: socket.assigns.current_user))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div>
          <.link navigate="/admin" class="text-sm opacity-60 hover:opacity-100">&larr; Admin</.link>
          <h1 class="text-3xl font-semibold mt-1">Feedback</h1>
        </div>

        <div :if={@items == []} class="text-ink55 text-sm font-mono">
          No feedback yet.
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
    <div class={[
      "border border-ink20 rounded-sharp p-5 flex flex-col gap-4",
      @item.status == :done && "opacity-60"
    ]}>
      <div class="flex items-start justify-between gap-3">
        <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55">
          {status_label(@item.status)} ·
          <span class="text-ink40">{format_when(@item.inserted_at)}</span>
        </div>
        <div class="font-mono text-[10px] text-ink40 truncate max-w-[180px]">
          {user_label(@item.user)}
        </div>
      </div>

      <div class={[
        "text-[14px] leading-[1.5] whitespace-pre-wrap text-ink",
        @item.status == :done && "line-through"
      ]}>
        {@item.body}
      </div>

      <div class="flex justify-end">
        <button
          type="button"
          phx-click="toggle"
          phx-value-id={@item.id}
          class="font-mono text-[11px] uppercase tracking-[0.08em] text-ink55 hover:text-ink cursor-pointer border border-ink20 rounded-sharp px-3 py-1.5 bg-transparent"
        >
          {if @item.status == :open, do: "mark done", else: "reopen"}
        </button>
      </div>
    </div>
    """
  end

  defp status_label(:open), do: "open"
  defp status_label(:done), do: "done"

  defp user_label(%{email: email}), do: to_string(email)
  defp user_label(_), do: "anonymous"

  defp format_when(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
