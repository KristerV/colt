defmodule ColtWeb.Sending.TrainingSequencesLive do
  @moduledoc """
  Admin-only. Shows the example pool the AI Writer draws from for one variant
  — the prior sequences it few-shots off when drafting a new contact under
  this template. Read-only, one example at a time via a dropdown.
  """

  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, Sequence}
  alias Colt.Services.Sending.EmailWriter
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_admin_required}

  def mount(%{"id" => campaign_id, "variant_id" => sequence_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, campaign} <- Campaign.get(campaign_id, actor: actor),
         {:ok, sequence} <- Sequence.get(sequence_id, actor: actor) do
      examples = EmailWriter.examples_for_sequence(sequence.id)

      {:ok,
       assign(socket,
         page_title: gettext("Training — %{name}", name: sequence.name),
         campaign: campaign,
         sequence: sequence,
         examples: examples,
         selected_index: 0
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("select_example", %{"index" => index}, socket) do
    {:noreply, assign(socket, selected_index: String.to_integer(index))}
  end

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
        <.link
          navigate={~p"/campaigns/#{@campaign.id}/variants"}
          class="inline-flex items-center gap-1 text-[12px] text-inkFaint hover:text-ink"
        >
          {gettext("← Back to variants")}
        </.link>

        <Liid.headline
          kicker={gettext("Sending · Training · %{name}", name: @sequence.name)}
          sub={
            gettext("The example sequences the writer few-shots off for this variant, newest first.")
          }
        >
          {raw(gettext("What the <em>writer</em> learns from."))}
        </Liid.headline>

        <div
          :if={@examples == []}
          class="mt-10 px-5 py-6 border border-border rounded-[11px] bg-card text-[13px] text-inkFaint"
        >
          {gettext(
            "No saved sequences yet for this variant — the writer has nothing to learn from until a first sequence is hand-written and sent under it."
          )}
        </div>

        <div :if={@examples != []} class="mt-10 flex flex-col gap-4">
          <form phx-change="select_example">
            <select
              name="index"
              class="w-full px-3 py-2 border border-border bg-card text-[13px] text-ink rounded-[8px] outline-none cursor-pointer focus:border-accentRing"
            >
              <option
                :for={{ex, i} <- Enum.with_index(@examples)}
                value={i}
                selected={i == @selected_index}
              >
                {example_label(ex, i)}
              </option>
            </select>
          </form>

          <.example_steps example={Enum.at(@examples, @selected_index)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :example, :map, required: true

  defp example_steps(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <.step_card :for={step <- @example.steps} step={step} />
    </div>
    """
  end

  attr :step, :map, required: true

  defp step_card(assigns) do
    ~H"""
    <div
      class="px-5 py-4 border border-border rounded-[11px] bg-card"
      style="box-shadow:var(--shadow)"
    >
      <div class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
        {EmailWriter.step_label(@step.position)}
      </div>
      <div class="mt-2 text-[14px] font-semibold text-ink">{@step.subject}</div>
      <div class="mt-2 text-[13px] text-inkSoft whitespace-pre-wrap">{@step.body}</div>
    </div>
    """
  end

  defp example_label(ex, index) do
    company = ex.company && ex.company.name
    who = [ex.person_title, company] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" at ")
    date = ex.recency && Calendar.strftime(ex.recency, "%Y-%m-%d")

    case {who, date} do
      {"", nil} -> gettext("Example %{n}", n: index + 1)
      {"", date} -> gettext("Example %{n} — %{date}", n: index + 1, date: date)
      {who, nil} -> who
      {who, date} -> "#{who} — #{date}"
    end
  end
end
