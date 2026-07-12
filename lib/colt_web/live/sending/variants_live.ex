defmodule ColtWeb.Sending.VariantsLive do
  @moduledoc """
  The A/B scoreboard. One row per variant — sent · replied · reply-rate — with
  an Active toggle (in/out of the rotation) and inline rename. This is where
  you read the experiment and retire losing arms. No writing or structure
  editing happens here; that's the Write screen.
  """

  use ColtWeb, :live_view

  alias Colt.Markets
  alias Colt.Resources.{Campaign, CampaignContact, Sequence}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}
  on_mount {ColtWeb.Sending.PanicHook, :default}
  on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, campaign} ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Variants — %{name}", name: campaign.name),
           campaign: campaign
         )
         |> load_variants()}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, seq} <- Sequence.get(id, actor: actor),
         {:ok, _} <- Sequence.set_enabled(seq, !seq.enabled, actor: actor) do
      {:noreply, load_variants(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("rename", %{"seq_id" => id, "value" => name}, socket) do
    actor = socket.assigns.current_user
    name = String.trim(name)

    if name != "" do
      with {:ok, seq} <- Sequence.get(id, actor: actor) do
        Sequence.set_name(seq, name, actor: actor)
      end
    end

    {:noreply, load_variants(socket)}
  end

  def handle_event("new_variant", _params, socket) do
    actor = socket.assigns.current_user
    campaign = socket.assigns.campaign
    name = variant_name(length(socket.assigns.variants))

    {:ok, seq} = Sequence.create_named(campaign.id, name, actor: actor)
    Sequence.set_language(seq, Markets.drafting_language(Campaign.selected_markets(campaign)),
      actor: actor
    )

    # Hand off to Write to author its first (seed) sequence.
    {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/write/#{seq.id}")}
  end

  # ── Data ───────────────────────────────────────────────────────────────

  defp load_variants(socket) do
    actor = socket.assigns.current_user
    campaign_id = socket.assigns.campaign.id

    sequences = Sequence.list_for_campaign!(campaign_id, actor: actor)

    contacts =
      case CampaignContact.list_for_campaign(campaign_id, actor: actor) do
        {:ok, list} -> list
        _ -> []
      end

    by_sequence = Enum.group_by(contacts, & &1.sequence_id)

    variants =
      Enum.map(sequences, fn seq ->
        cs = Map.get(by_sequence, seq.id, [])
        sent = Enum.count(cs, &(&1.status != :pending_approval))
        replied = Enum.count(cs, &(&1.status == :replied))

        %{
          sequence: seq,
          sent: sent,
          replied: replied,
          reply_rate: if(sent > 0, do: round(replied * 100 / sent), else: nil)
        }
      end)

    assign(socket, variants: variants)
  end

  defp variant_name(index) when index < 26, do: gettext("Variant %{l}", l: <<65 + index::utf8>>)
  defp variant_name(index), do: gettext("Variant %{n}", n: index + 1)

  # ── Render ───────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active={:variants}
      campaign={@campaign}
      campaign_id={@campaign.id}
      campaign_name={@campaign.name}
    >
      <div class="w-full max-w-[680px] mx-auto md:px-6 py-6">
        <Liid.headline
          kicker={gettext("Sending · Variants")}
          sub={
            gettext(
              "Each variant is one approach the writer is testing. Reply-rate is the scoreboard. Turn one off to drop it from the rotation."
            )
          }
        >
          {raw(gettext("The <em>A/B</em> board."))}
        </Liid.headline>

        <div class="mt-10 flex flex-col gap-3">
          <.variant_row :for={v <- @variants} v={v} />

          <button
            type="button"
            phx-click="new_variant"
            class="mt-1 py-3 border border-dashed border-borderStrong text-inkSoft text-[12px] font-medium rounded-[11px] cursor-pointer hover:border-accentRing hover:text-accent hover:bg-accentSoft transition-colors"
          >
            {gettext("+ new variant")}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :v, :map, required: true

  defp variant_row(assigns) do
    assigns = assign(assigns, :seq, assigns.v.sequence)

    ~H"""
    <div
      id={"variant-row-#{@seq.id}"}
      class={[
        "flex items-center gap-4 px-5 py-4 border rounded-[11px] bg-card transition-opacity",
        if(@seq.enabled, do: "border-border", else: "border-border opacity-60")
      ]}
      style="box-shadow:var(--shadow)"
    >
      <form id={"rename-form-#{@seq.id}"} phx-change="rename" class="flex-1 min-w-0">
        <input type="hidden" name="seq_id" value={@seq.id} />
        <input
          type="text"
          id={"rename-input-#{@seq.id}"}
          name="value"
          value={@seq.name}
          phx-debounce="blur"
          class="w-full bg-transparent text-[15px] font-semibold text-ink outline-none border-0 p-0"
        />
        <div class="mt-1 text-[11.5px] text-inkFaint tabular-nums">
          {gettext("sent to %{n}", n: @v.sent)} · {gettext("%{n} replied", n: @v.replied)}
          <span :if={@v.reply_rate} class="text-inkSoft font-medium">· {@v.reply_rate}%</span>
        </div>
      </form>

      <.active_toggle on={@seq.enabled} id={@seq.id} />
    </div>
    """
  end

  attr :on, :boolean, required: true
  attr :id, :string, required: true

  defp active_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_active"
      phx-value-id={@id}
      title={
        if @on,
          do: gettext("Active — in the A/B rotation. Click to retire it."),
          else: gettext("Off — not in the rotation. Click to put it back in the test.")
      }
      class="shrink-0 inline-flex items-center gap-2 cursor-pointer bg-transparent border-0 p-0"
    >
      <span class={[
        "text-[9px] tracking-[0.12em] uppercase font-semibold",
        if(@on, do: "text-accent", else: "text-inkFaint")
      ]}>
        {gettext("active")}
      </span>
      <span class="relative inline-block w-[34px] h-[18px] rounded-full">
        <span
          class="absolute inset-0 rounded-full"
          style={"background: #{if @on, do: "var(--accent)", else: "var(--ink20)"}; transition: background .12s;"}
        />
        <span
          class="absolute top-[2px] w-[14px] h-[14px] rounded-full bg-card"
          style={"left: #{if @on, do: "18px", else: "2px"}; box-shadow: 0 1px 2px rgba(0,0,0,0.2); transition: left .12s;"}
        />
      </span>
    </button>
    """
  end
end
