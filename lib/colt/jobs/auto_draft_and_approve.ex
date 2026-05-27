defmodule Colt.Jobs.AutoDraftAndApprove do
  @moduledoc """
  Oban worker on the `ai_writer` queue (concurrency 4). One job per
  CampaignContact when the campaign has `auto_approve_on?` true.

  Wraps `Colt.Services.Sending.AutoDraftAndApprove`. On final failure
  the job error surfaces in the Oban dashboard; the contact stays in
  `:pending_approval` and will retry on the next IngestEnriched click
  if the user re-runs it.
  """

  use Oban.Worker,
    queue: :ai_writer,
    max_attempts: 3,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Services.Sending.AutoDraftAndApprove

  def enqueue(contact_id) when is_binary(contact_id) do
    %{"contact_id" => contact_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(:math.pow(attempt, 3) * 30)
  end

  @impl true
  def perform(%Oban.Job{args: %{"contact_id" => contact_id}}) do
    AutoDraftAndApprove.run(contact_id)
  end
end
