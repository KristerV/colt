defmodule Colt.Services.Sending.DeferFollowup do
  @moduledoc """
  Push a thread's next pending send out to at least `not_before`, snapped to a
  valid burst slot. Used when an OOO auto-reply means the prospect won't see
  the next follow-up until they're back.

  Only the single currently-`:scheduled` row is moved — later steps schedule
  lazily off each actual send, so they cascade behind it automatically.

  Returns `{:ok, {:deferred, email_id, scheduled_at}}` when a send was moved,
  or `{:ok, :no_pending_send}` / `{:ok, :no_inbox}` when there's nothing to do.
  """

  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Sending.NextSlot

  def run(thread_id, %DateTime{} = not_before) when is_binary(thread_id) do
    with {:ok, email} <- next_send(thread_id) do
      defer(email, not_before)
    end
  end

  defp next_send(thread_id) do
    OutboundEmail.next_scheduled_for_thread(thread_id,
      load: [:email_account],
      authorize?: false,
      not_found_error?: false
    )
  end

  defp defer(nil, _not_before), do: {:ok, :no_pending_send}
  defp defer(%{email_account: nil}, _not_before), do: {:ok, :no_inbox}

  defp defer(email, not_before) do
    with {:ok, slot} <-
           NextSlot.run(email.email_account, not_before, step_position: email.step_position),
         {:ok, _} <-
           OutboundEmail.schedule(email, slot, email.email_account_id, authorize?: false) do
      {:ok, {:deferred, email.id, slot}}
    end
  end
end
