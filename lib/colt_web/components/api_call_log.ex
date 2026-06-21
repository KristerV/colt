defmodule ColtWeb.Components.ApiCallLog do
  @moduledoc """
  Admin debug components for inspecting recorded LLM / search API calls.

    * `api_call_row/1` — one collapsible row (header summary + expandable body)
    * `api_call_list/1` — list of `api_call_row`s
    * `api_call_detail/1` — full body (prompt / response / meta) without the
      header; used by the costs page modal when only one call is shown
  """
  use Phoenix.Component

  alias ColtWeb.Components.Liid

  attr :calls, :list, required: true
  attr :expanded_id, :string, default: nil
  attr :empty_label, :string, default: "No LLM calls recorded for this record."

  def api_call_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <%= if @calls == [] do %>
        <div class="text-[12px] text-ink40 italic">{@empty_label}</div>
      <% else %>
        <.api_call_row :for={c <- @calls} call={c} expanded?={@expanded_id == c.id} />
      <% end %>
    </div>
    """
  end

  attr :call, :map, required: true
  attr :expanded?, :boolean, default: false

  def api_call_row(assigns) do
    ~H"""
    <div class="border border-border rounded-[11px] bg-card" style="box-shadow:var(--shadow)">
      <button
        type="button"
        phx-click="toggle_api_call"
        phx-value-id={@call.id}
        class="w-full text-left px-3 py-2.5 flex items-center gap-3 cursor-pointer hover:bg-paperAlt rounded-[11px]"
      >
        <span class={["w-1.5 h-1.5 rounded-full shrink-0", status_dot(@call.status)]}></span>
        <span class={[
          "text-[10px] font-semibold uppercase tracking-[0.06em]",
          status_color(@call.status)
        ]}>
          {@call.status}
        </span>
        <span class="text-[12px] font-medium text-ink truncate">{@call.task || "—"}</span>
        <span class="text-[11px] text-ink40 truncate flex-1">{@call.model}</span>
        <span class="text-[11px] text-ink55 tabular-nums">
          ${format_money(@call.cost_usd)}
        </span>
        <span class="text-[11px] text-ink40 tabular-nums">{@call.latency_ms}ms</span>
        <span class="text-[11px] text-ink40 tabular-nums">{format_time(@call.inserted_at)}</span>
        <Liid.icon name="chev" size={11} class={@expanded? && "rotate-180"} />
      </button>

      <div :if={@expanded?} class="border-t border-border px-3 py-3">
        <.api_call_detail call={@call} />
      </div>
    </div>
    """
  end

  attr :call, :map, required: true

  def api_call_detail(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 text-[11px] text-ink70">
      <div class="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-1">
        <.meta_pair label="task" value={@call.task || "—"} />
        <.meta_pair label="model" value={@call.model || "—"} />
        <.meta_pair label="provider" value={to_string(@call.provider)} />
        <.meta_pair label="status" value={to_string(@call.status)} />
        <.meta_pair label="in tokens" value={@call.input_tokens} />
        <.meta_pair label="out tokens" value={@call.output_tokens} />
        <.meta_pair label="cost" value={"$#{format_money(@call.cost_usd)}"} />
        <.meta_pair label="latency" value={"#{@call.latency_ms}ms"} />
        <.meta_pair label="cached" value={to_string(@call.cached)} />
        <.meta_pair label="time" value={format_time(@call.inserted_at)} />
        <.meta_pair
          :if={@call.subject_type}
          label="subject"
          value={"#{@call.subject_type}/#{short_id(@call.subject_id)}"}
        />
        <.meta_pair :if={@call.campaign_id} label="campaign" value={short_id(@call.campaign_id)} />
      </div>

      <div :if={@call.error}>
        <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-red mb-1">Error</div>
        <pre class="text-[11px] text-red whitespace-pre-wrap break-all bg-redSoft p-2 rounded-[8px]"><%= @call.error %></pre>
      </div>

      <div :if={@call.query}>
        <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 mb-1">Query</div>
        <pre class="text-[11px] text-ink70 whitespace-pre-wrap break-all bg-paperAlt p-2 rounded-[8px]"><%= @call.query %></pre>
      </div>

      <div :if={@call.prompt}>
        <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 mb-1">
          Prompt
        </div>
        <pre class="text-[11px] text-ink70 leading-[1.5] whitespace-pre-wrap break-all bg-paperAlt p-3 rounded-[8px] max-h-[420px] overflow-auto"><%= @call.prompt %></pre>
      </div>

      <div :if={@call.response}>
        <div class="text-[10px] font-semibold tracking-[0.08em] uppercase text-ink55 mb-1">
          Response
        </div>
        <pre class="text-[11px] text-ink70 leading-[1.5] whitespace-pre-wrap break-all bg-paperAlt p-3 rounded-[8px] max-h-[420px] overflow-auto"><%= @call.response %></pre>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp meta_pair(assigns) do
    ~H"""
    <div class="flex justify-between gap-2 border-b border-border py-1">
      <span class="text-ink40 uppercase text-[10px] font-semibold tracking-[0.06em]">{@label}</span>
      <span class="text-ink tabular-nums truncate">{@value || "—"}</span>
    </div>
    """
  end

  defp status_color(:ok), do: "text-green"
  defp status_color(:error), do: "text-red"
  defp status_color(_), do: "text-ink40"

  defp status_dot(:ok), do: "bg-green"
  defp status_dot(:error), do: "bg-red"
  defp status_dot(_), do: "bg-ink40"

  defp format_money(nil), do: "0.0000"
  defp format_money(%Decimal{} = d), do: d |> Decimal.round(4) |> Decimal.to_string(:normal)
  defp format_money(n) when is_number(n), do: n |> Decimal.from_float() |> format_money()
  defp format_money(_), do: "0.0000"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M:%S")
  defp format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M:%S")
  defp format_time(_), do: ""

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(id), do: to_string(id) |> String.slice(0, 8)
end
