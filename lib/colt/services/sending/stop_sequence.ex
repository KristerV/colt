defmodule Colt.Services.Sending.StopSequence do
  @moduledoc """
  Manual "Stop sequence" from the thread view. Halts every drafted /
  scheduled outbound for the contact's thread and flips the contact to
  `:no_reply`. Distinct from a reply-triggered halt (which keeps the
  contact `:replied`).
  """

  alias Colt.Resources.{CampaignContact, Thread}
  alias Colt.Services.Sales.RecordStatusEvent
  alias Colt.Services.Sending.HaltSequence

  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id,
             load: [:thread],
             actor: actor,
             authorize?: actor != nil
           ),
         from = status_label(contact.status),
         {:ok, halted} <- maybe_halt(contact.thread),
         {:ok, updated} <-
           CampaignContact.stop_sequence(contact, actor: actor, authorize?: actor != nil) do
      record_event(contact.thread, from, actor)
      {:ok, %{contact: updated, halted: halted}}
    end
  end

  defp maybe_halt(nil), do: {:ok, 0}
  defp maybe_halt(%Thread{id: id}), do: HaltSequence.run(id)

  defp record_event(nil, _from, _actor), do: :ok

  defp record_event(%Thread{id: thread_id}, from, actor) do
    RecordStatusEvent.run(thread_id, :send_status, from, "no reply",
      actor: actor,
      reason: "sequence stopped"
    )
  end

  defp status_label(status) when is_atom(status),
    do: status |> to_string() |> String.replace("_", " ")

  defp status_label(_), do: nil
end
