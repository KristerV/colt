defmodule Colt.Services.Sending.HaltSequence do
  @moduledoc """
  Flip every in-flight outbound Email on a thread (`:drafted`, `:approved`,
  `:scheduled`) to `:skipped`. Used by the reply categorizer and by manual
  "Stop sequence" actions (E7). Approved-but-unscheduled followups are
  swept too, so a reply leaves no orphaned queued steps behind.
  """

  alias Colt.Resources.OutboundEmail

  def run(thread_id) when is_binary(thread_id) do
    with {:ok, rows} <- OutboundEmail.list_halt_eligible_for_thread(thread_id, authorize?: false) do
      Enum.each(rows, fn email ->
        {:ok, _} = OutboundEmail.mark_skipped(email, authorize?: false)
      end)

      {:ok, length(rows)}
    end
  end
end
