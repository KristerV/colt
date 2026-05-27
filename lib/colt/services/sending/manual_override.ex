defmodule Colt.Services.Sending.ManualOverride do
  @moduledoc """
  "Mark as…" action from the thread view. Sets the contact's terminal
  status + reply_category and halts the sequence so no further emails
  go out.
  """

  alias Colt.Resources.{CampaignContact, Thread}
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
         {:ok, halted} <- maybe_halt(contact.thread),
         {:ok, contact} <-
           CampaignContact.manual_override(contact, override,
             actor: actor,
             authorize?: actor != nil
           ) do
      {:ok, %{contact: contact, halted: halted}}
    end
  end

  defp maybe_halt(nil), do: {:ok, 0}
  defp maybe_halt(%Thread{id: id}), do: HaltSequence.run(id)
end
