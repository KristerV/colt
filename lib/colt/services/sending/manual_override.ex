defmodule Colt.Services.Sending.ManualOverride do
  @moduledoc """
  "Mark as…" action from the thread view. Sets the contact's terminal
  status + reply_category and halts the sequence so no further emails
  go out.
  """

  alias Colt.Resources.{CampaignContact, Thread}
  alias Colt.Services.Sales.RecordStatusEvent
  alias Colt.Services.Sending.HaltSequence

  @overrides [:interested, :not_interested, :ooo, :call_ready, :no_reply]

  def overrides, do: @overrides

  def run(contact_id, override, opts \\ [])
      when is_binary(contact_id) and override in @overrides do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id,
             load: [:thread],
             actor: actor,
             authorize?: actor != nil
           ),
         from = status_label(contact),
         {:ok, halted} <- maybe_halt(contact.thread),
         {:ok, updated} <-
           CampaignContact.manual_override(contact, override,
             actor: actor,
             authorize?: actor != nil
           ) do
      record_event(contact.thread, override, from, actor)
      {:ok, %{contact: updated, halted: halted}}
    end
  end

  defp maybe_halt(nil), do: {:ok, 0}
  defp maybe_halt(%Thread{id: id}), do: HaltSequence.run(id)

  defp record_event(nil, _override, _from, _actor), do: :ok

  defp record_event(%Thread{id: thread_id}, override, from, actor) do
    RecordStatusEvent.run(thread_id, override_kind(override), from, override_label(override),
      actor: actor
    )
  end

  # Category-style overrides read as reply outcomes; the rest are send-status.
  defp override_kind(o) when o in [:interested, :not_interested, :ooo], do: :reply_category
  defp override_kind(_), do: :send_status

  defp override_label(:interested), do: "interested"
  defp override_label(:not_interested), do: "not interested"
  defp override_label(:ooo), do: "out of office"
  defp override_label(:call_ready), do: "call ready"
  defp override_label(:no_reply), do: "no reply"

  defp status_label(%{status: :replied, reply_category: cat}) when not is_nil(cat),
    do: override_label(cat)

  defp status_label(%{status: status}), do: status |> to_string() |> String.replace("_", " ")
  defp status_label(_), do: nil
end
