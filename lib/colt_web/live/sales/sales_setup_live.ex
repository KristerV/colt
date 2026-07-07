defmodule ColtWeb.Sales.SalesSetupLive do
  @moduledoc """
  Sales-funnel setup — define the campaign's stages. Admin-only (golden).
  Reorderable list of stage cards with inline rename, add, delete, and a
  per-stage kind control (active / won / lost). Seeds the starter set on
  first visit so the user never starts from a blank slate.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, SalesStage}
  alias Colt.Services.Sales.SeedStages
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  @kinds [:active, :won, :lost]

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        {:ok, _} = SeedStages.run(campaign.id, actor: actor)

        socket =
          socket
          |> assign(
            page_title: gettext("Sales setup — %{name}", name: campaign.name),
            campaign: campaign,
            error: nil
          )
          |> load_stages()

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("add_stage", _params, socket) do
    actor = socket.assigns.current_user
    position = next_position(socket.assigns.stages)

    case SalesStage.create(socket.assigns.campaign.id, gettext("New stage"), position,
           actor: actor
         ) do
      {:ok, _} -> {:noreply, load_stages(socket)}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  # Persist the rename but patch the stage in-memory rather than reloading the
  # whole list — reloading would re-render the input the user is typing in.
  def handle_event("rename", %{"id" => id, "name" => name}, socket) do
    with %SalesStage{} = stage <- find_stage(socket, id),
         {:ok, updated} <- SalesStage.rename(stage, name, actor: socket.assigns.current_user) do
      stages = Enum.map(socket.assigns.stages, &if(&1.id == id, do: updated, else: &1))
      {:noreply, assign(socket, stages: stages)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_kind", %{"id" => id, "kind" => kind}, socket)
      when kind in ["active", "won", "lost"] do
    with %SalesStage{} = stage <- find_stage(socket, id),
         {:ok, _} <-
           SalesStage.set_kind(stage, String.to_existing_atom(kind),
             actor: socket.assigns.current_user
           ) do
      {:noreply, load_stages(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    {:noreply, swap(socket, id, dir) |> load_stages()}
  end

  def handle_event("delete_stage", %{"id" => id}, socket) do
    with %SalesStage{} = stage <- find_stage(socket, id),
         {:ok, _} <- SalesStage.destroy(stage, actor: socket.assigns.current_user) do
      {:noreply, load_stages(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp load_stages(socket) do
    actor = socket.assigns.current_user

    stages =
      case SalesStage.list_for_campaign(socket.assigns.campaign.id, actor: actor) do
        {:ok, rows} -> rows
        _ -> []
      end

    assign(socket, stages: stages)
  end

  defp find_stage(socket, id), do: Enum.find(socket.assigns.stages, &(&1.id == id))

  defp next_position([]), do: 0
  defp next_position(stages), do: (stages |> Enum.map(& &1.position) |> Enum.max()) + 1

  # Adjacent-position swap. Reposition writes both rows; there is no unique
  # index on position, so a transient duplicate between the two updates is
  # harmless.
  defp swap(socket, id, dir) do
    actor = socket.assigns.current_user
    stages = socket.assigns.stages
    idx = Enum.find_index(stages, &(&1.id == id))
    neighbor_idx = if dir == "up", do: idx && idx - 1, else: idx && idx + 1

    with true <- is_integer(idx),
         true <- neighbor_idx >= 0 and neighbor_idx < length(stages),
         a <- Enum.at(stages, idx),
         b <- Enum.at(stages, neighbor_idx) do
      SalesStage.reposition(a, b.position, actor: actor)
      SalesStage.reposition(b, a.position, actor: actor)
    end

    socket
  end

  defp kind_label(:active), do: gettext("Active")
  defp kind_label(:won), do: gettext("Won")
  defp kind_label(:lost), do: gettext("Lost")

  # ── Render ───────────────────────────────────────────────────────────

  def render(assigns) do
    assigns = assign(assigns, kinds: @kinds)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:sales_setup}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="max-w-[720px]">
        <div class="flex items-start justify-between gap-4">
          <Liid.headline kicker={gettext("Sales · Setup")}>
            {raw(gettext("The stages you move deals <em class=\"text-accent\">through</em>."))}
          </Liid.headline>
          <Liid.admin_badge label={gettext("Admin")} />
        </div>

        <div class="mt-4 text-[13px] text-inkSoft leading-[1.55] max-w-[520px]">
          {gettext(
            "Active stages form the funnel; Won and Lost are the exits it converts toward. Reorder to match how you actually sell."
          )}
        </div>

        <div :if={@error} class="mt-4 text-[12.5px] text-red">{@error}</div>

        <div class="mt-6 flex flex-col gap-3">
          <.stage_card
            :for={{stage, i} <- Enum.with_index(@stages)}
            stage={stage}
            first?={i == 0}
            last?={i == length(@stages) - 1}
            kinds={@kinds}
          />
        </div>

        <div class="mt-4">
          <Liid.btn phx-click="add_stage">
            <Liid.icon name="plus" size={12} /> {gettext("Add stage")}
          </Liid.btn>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :stage, :map, required: true
  attr :first?, :boolean, required: true
  attr :last?, :boolean, required: true
  attr :kinds, :list, required: true

  defp stage_card(assigns) do
    ~H"""
    <div
      class="bg-card border border-border rounded-[11px] px-4 py-3.5 flex items-center gap-3"
      style="box-shadow:var(--shadow)"
    >
      <div class="flex flex-col gap-0.5 shrink-0">
        <button
          type="button"
          phx-click="move"
          phx-value-id={@stage.id}
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
          phx-value-id={@stage.id}
          phx-value-dir="down"
          disabled={@last?}
          class="w-6 h-5 flex items-center justify-center rounded-[6px] text-inkFaint hover:text-ink hover:bg-paperAlt disabled:opacity-30 disabled:pointer-events-none cursor-pointer"
          aria-label={gettext("Move down")}
        >
          <span class="text-[13px] leading-none">▼</span>
        </button>
      </div>

      <span class={[
        "w-[7px] h-[7px] rounded-full shrink-0",
        kind_dot(@stage.kind)
      ]} />

      <form phx-change="rename" class="flex-1 min-w-0">
        <input type="hidden" name="id" value={@stage.id} />
        <input
          type="text"
          name="name"
          value={@stage.name}
          phx-debounce="500"
          class="w-full bg-transparent border border-transparent hover:border-border focus:border-accentRing rounded-[8px] px-2.5 py-1.5 text-[14px] font-semibold text-ink outline-none"
        />
      </form>

      <div class="flex items-center gap-1 shrink-0 bg-paperAlt rounded-[8px] p-0.5">
        <button
          :for={k <- @kinds}
          type="button"
          phx-click="set_kind"
          phx-value-id={@stage.id}
          phx-value-kind={to_string(k)}
          class={[
            "text-[11.5px] font-semibold px-2.5 py-1 rounded-[6px] cursor-pointer",
            if(@stage.kind == k,
              do: "bg-card text-accent [box-shadow:var(--shadow)]",
              else: "text-inkFaint hover:text-inkSoft"
            )
          ]}
        >
          {kind_label(k)}
        </button>
      </div>

      <button
        type="button"
        phx-click="delete_stage"
        phx-value-id={@stage.id}
        data-confirm={gettext("Delete this stage? Contacts in it will drop out of the funnel.")}
        class="shrink-0 w-7 h-7 flex items-center justify-center rounded-[7px] text-inkFaint hover:text-red hover:bg-redSoft cursor-pointer"
        aria-label={gettext("Delete stage")}
      >
        <Liid.icon name="x" size={13} />
      </button>
    </div>
    """
  end

  defp kind_dot(:active), do: "bg-accent"
  defp kind_dot(:won), do: "bg-green"
  defp kind_dot(:lost), do: "bg-inkFaint"
end
