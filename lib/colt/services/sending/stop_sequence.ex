defmodule Colt.Services.Sending.StopSequence do
  @moduledoc """
  Manual "Stop sequence" from the thread view. Halts every drafted /
  scheduled outbound for the contact's thread and flips the contact to
  `:no_reply`. Distinct from a reply-triggered halt (which keeps the
  contact `:replied`).
  """

  alias Colt.Resources.{CampaignContact, Thread}
  alias Colt.Services.Sending.HaltSequence

  def run(contact_id, opts \\ []) when is_binary(contact_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, contact} <-
           Ash.get(CampaignContact, contact_id, load: [:thread], actor: actor, authorize?: actor != nil),
         {:ok, halted} <- maybe_halt(contact.thread),
         {:ok, contact} <-
           CampaignContact.stop_sequence(contact, actor: actor, authorize?: actor != nil) do
      {:ok, %{contact: contact, halted: halted}}
    end
  end

  defp maybe_halt(nil), do: {:ok, 0}
  defp maybe_halt(%Thread{id: id}), do: HaltSequence.run(id)
end
