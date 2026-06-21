defmodule ColtWeb.Admin.FeedbackLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Feedback

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}
  on_mount ColtWeb.Admin.SummaryHook

  alias ColtWeb.Admin.Summary

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
        <Summary.summary_strip tiles={@admin_tiles} current_path={@admin_current_path} />
        <h1 class="text-[25px] font-semibold tracking-[-0.02em] text-ink">User <em>feedback</em></h1>

        <div :if={@items == []} class="text-ink55 text-[13px]">
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
    <div
      class={[
        "border border-border rounded-[11px] bg-card p-5 flex flex-col gap-4",
        @item.status == :done && "opacity-60"
      ]}
      style="box-shadow:var(--shadow)"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="flex items-center gap-2 text-[10px] font-semibold tracking-[0.08em] uppercase">
          <span class={[
            "w-1.5 h-1.5 rounded-full shrink-0",
            if(@item.status == :done, do: "bg-green", else: "bg-amber")
          ]}>
          </span>
          <span class="text-ink55">{status_label(@item.status)}</span>
          <span class="text-ink40 normal-case font-normal tracking-normal tabular-nums">
            · {format_when(@item.inserted_at)}
          </span>
        </div>
        <div class="text-[11px] text-ink40 truncate max-w-[180px]">
          {user_label(@item.user)}
        </div>
      </div>

      <div class={[
        "text-[14px] leading-[1.5] whitespace-pre-wrap text-ink",
        @item.status == :done && "line-through"
      ]}>
        {@item.body}
      </div>

      <div :if={@item.url} class="text-[11px] text-ink40 truncate">
        on {@item.url}
      </div>

      <div class="flex justify-end">
        <button
          type="button"
          phx-click="toggle"
          phx-value-id={@item.id}
          class="text-[11px] font-semibold uppercase tracking-[0.06em] text-ink55 hover:text-ink cursor-pointer border border-borderStrong rounded-[8px] px-3 py-1.5 bg-card"
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
