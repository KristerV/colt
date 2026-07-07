defmodule Colt.Services.Sales.RecordStatusEvent do
  @moduledoc """
  Writes one `StatusEvent` to a thread's unified feed. Used by both funnels:
  the sending transitions (mark_replied, manual_override, stop_sequence,
  mark_bounced, approve …) and the sales-stage moves.

  A feed write is a secondary concern — it must never break the transition
  that triggered it. Every entry point returns `:ok` and logs on failure
  rather than propagating an error into the caller's `with` chain.
  """

  require Logger

  alias Colt.Resources.{StatusEvent, Thread}

  @doc """
  Record an event against a thread id directly. `opts` may carry `:actor`
  and `:reason`. Returns `:ok` always.
  """
  def run(thread_id, kind, from, to, opts \\ []) when is_binary(thread_id) do
    actor = Keyword.get(opts, :actor)
    reason = Keyword.get(opts, :reason)

    case StatusEvent.record(thread_id, kind, from, to, reason,
           actor: actor,
           authorize?: actor != nil
         ) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.warning("record_status_event: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Record an event for a contact, resolving its thread first. No-op (logged)
  when the contact has no thread yet.
  """
  def for_contact(contact_id, kind, from, to, opts \\ []) when is_binary(contact_id) do
    case Thread.for_contact(contact_id, authorize?: false) do
      {:ok, %Thread{id: thread_id}} ->
        run(thread_id, kind, from, to, opts)

      _ ->
        Logger.warning("record_status_event: no thread for contact #{contact_id}")
        :ok
    end
  end
end
