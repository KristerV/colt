defmodule Colt.Jobs.LabelTemplate do
  @moduledoc """
  Classify one approved opener into an outreach template (§6.2). Thin
  wrapper around `Colt.Services.Sending.LabelTemplate` so the LLM call
  stays off the approval request path and Oban owns retry/backoff.

  Runs as the system actor (authorize?: false) — it's post-approval
  bookkeeping, not user-initiated.
  """

  use Oban.Worker,
    queue: :ai_writer,
    max_attempts: 3,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Sending.LabelTemplate

  def enqueue(opener_id) when is_binary(opener_id) do
    %{"opener_id" => opener_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"opener_id" => opener_id}}) do
    with {:ok, opener} <-
           Ash.get(OutboundEmail, opener_id,
             load: [thread: [:campaign_contact]],
             authorize?: false
           ),
         {:ok, _labeled} <- LabelTemplate.run(opener) do
      :ok
    end
  end
end
