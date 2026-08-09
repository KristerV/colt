defmodule ColtWeb.Sales.ChecklistLive do
  @moduledoc """
  The campaign's sales checklist — the things you work through with every
  contact. Admin-only (golden). Reorderable cards with inline rename, add and
  delete.

  These are not stages and not statuses: a contact ticks them off
  independently in the thread view, and where the contact sits on the board is
  decided by their next action date and outcome, not by this list.

  Nothing is seeded on mount. The checklist is optional, and an on-visit seed
  would resurrect the starter set every time someone cleared it deliberately —
  so the empty state offers it as a button instead.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, ChecklistItem}
  alias Colt.Services.Sales.SeedChecklist
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("Checklist — %{name}", name: campaign.name),
            campaign: campaign,
            error: nil
          )
          |> load_items()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("add_item", _params, socket) do
    actor = socket.assigns.current_user
    position = next_position(socket.assigns.items)

    case ChecklistItem.create(socket.assigns.campaign.id, gettext("New item"), position,
           actor: actor
         ) do
      {:ok, _} -> {:noreply, load_items(socket)}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  def handle_event("seed", _params, socket) do
    case SeedChecklist.run(socket.assigns.campaign.id, actor: socket.assigns.current_user) do
      {:ok, _} -> {:noreply, load_items(socket)}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  # Persist the rename but patch the item in-memory rather than reloading the
  # whole list — reloading would re-render the input the user is typing in.
  def handle_event("rename", %{"_id" => id, "name" => name}, socket) do
    with %ChecklistItem{} = item <- find_item(socket, id),
         {:ok, updated} <- ChecklistItem.rename(item, name, actor: socket.assigns.current_user) do
      items = Enum.map(socket.assigns.items, &if(&1.id == id, do: updated, else: &1))
      {:noreply, assign(socket, items: items)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    {:noreply, swap(socket, id, dir) |> load_items()}
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    with %ChecklistItem{} = item <- find_item(socket, id),
         {:ok, _} <- ChecklistItem.destroy(item, actor: socket.assigns.current_user) do
      {:noreply, load_items(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp load_items(socket) do
    actor = socket.assigns.current_user

    items =
      case ChecklistItem.list_for_campaign(socket.assigns.campaign.id, actor: actor) do
        {:ok, rows} -> rows
        _ -> []
      end

    assign(socket, items: items)
  end

  defp find_item(socket, id), do: Enum.find(socket.assigns.items, &(&1.id == id))

  defp next_position([]), do: 0
  defp next_position(items), do: (items |> Enum.map(& &1.position) |> Enum.max()) + 1

  # Adjacent-position swap. Reposition writes both rows; there is no unique
  # index on position, so a transient duplicate between the two updates is
  # harmless.
  defp swap(socket, id, dir) do
    actor = socket.assigns.current_user
    items = socket.assigns.items
    idx = Enum.find_index(items, &(&1.id == id))
    neighbor_idx = if dir == "up", do: idx && idx - 1, else: idx && idx + 1

    with true <- is_integer(idx),
         true <- neighbor_idx >= 0 and neighbor_idx < length(items),
         a <- Enum.at(items, idx),
         b <- Enum.at(items, neighbor_idx) do
      ChecklistItem.reposition(a, b.position, actor: actor)
      ChecklistItem.reposition(b, a.position, actor: actor)
    end

    socket
  end

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sales_checklist}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="max-w-[720px]">
        <div class="flex items-start justify-between gap-4">
          <Liid.headline kicker={gettext("Sales · Checklist")}>
            {raw(gettext("The things you do with <em class=\"text-accent\">everyone</em>."))}
          </Liid.headline>
          <Liid.admin_badge label={gettext("Admin")} />
        </div>

        <div class="mt-4 text-[13px] text-inkSoft leading-[1.55] max-w-[520px]">
          {gettext(
            "Every contact in the sales funnel gets this list as checkboxes in their thread. Tick them off in any order — they don't decide where a contact sits on the board."
          )}
        </div>

        <div :if={@error} class="mt-4 text-[12.5px] text-red">{@error}</div>

        <div :if={@items == []} class="mt-6">
          <div
            class="bg-card border border-border rounded-[11px] px-4 py-5 text-center"
            style="box-shadow:var(--shadow)"
          >
            <div class="text-[13px] text-inkSoft">
              {gettext("No checklist yet.")}
            </div>
            <div class="mt-3">
              <Liid.btn variant={:primary} phx-click="seed">
                {gettext("Use starter checklist")}
              </Liid.btn>
            </div>
          </div>
        </div>

        <div :if={@items != []} class="mt-6 flex flex-col gap-3">
          <.item_card
            :for={{item, i} <- Enum.with_index(@items)}
            item={item}
            first?={i == 0}
            last?={i == length(@items) - 1}
          />
        </div>

        <div class="mt-4">
          <Liid.btn phx-click="add_item">
            <Liid.icon name="plus" size={12} /> {gettext("Add item")}
          </Liid.btn>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true
  attr :first?, :boolean, required: true
  attr :last?, :boolean, required: true

  defp item_card(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] px-4 py-3.5 flex items-center gap-3"
      style="box-shadow:var(--shadow)"
    >
      <div class="flex flex-col gap-0.5 shrink-0">
        <button
          type="button"
          phx-click="move"
          phx-value-id={@item.id}
          phx-value-dir="up"
          disabled={@first?}
          class="w-6 h-5 flex items-center justify-center rounded-[6px] text-inkFaint hover:text-ink hover:bg-paperAlt disabled:opacity-30 disabled:pointer-events-none cursor-pointer"
          aria-label={gettext("Move up")}
        >
          <span class="text-[13px] leading-none">▲</span>
        </button>
        <button
          type="button"
          phx-click="move"
          phx-value-id={@item.id}
          phx-value-dir="down"
          disabled={@last?}
          class="w-6 h-5 flex items-center justify-center rounded-[6px] text-inkFaint hover:text-ink hover:bg-paperAlt disabled:opacity-30 disabled:pointer-events-none cursor-pointer"
          aria-label={gettext("Move down")}
        >
          <span class="text-[13px] leading-none">▼</span>
        </button>
      </div>

      <span class="w-[15px] h-[15px] rounded-[4px] border border-borderStrong shrink-0" />

      <form phx-change="rename" class="flex-1 min-w-0">
        <input type="hidden" name="_id" value={@item.id} />
        <input
          type="text"
          name="name"
          value={@item.name}
          phx-debounce="500"
          class="w-full bg-transparent border border-transparent hover:border-border focus:border-accentRing rounded-[8px] px-2.5 py-1.5 text-[14px] font-semibold text-ink outline-none"
        />
      </form>

      <button
        type="button"
        phx-click="delete_item"
        phx-value-id={@item.id}
        data-confirm={gettext("Delete this item? Any ticks against it are removed too.")}
        class="shrink-0 w-7 h-7 flex items-center justify-center rounded-[7px] text-inkFaint hover:text-red hover:bg-redSoft cursor-pointer"
        aria-label={gettext("Delete item")}
      >
        <Liid.icon name="x" size={13} />
      </button>
    </div>
    """
  end
end
