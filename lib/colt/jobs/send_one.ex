defmodule Colt.Jobs.SendOne do
  @moduledoc """
  Send one Email row through Nylas. Thin wrapper around
  `Colt.Services.Sending.SendOne` so Oban handles retry/backoff and
  per-row isolation.

  Per §5.3: max 3 attempts with exponential backoff. On final failure the
  service has not flipped `Email.status` to `:failed`; we do that here so
  it's tied to job-attempt exhaustion, not to a single transient error.
  """

  use Oban.Worker,
    queue: :sending,
    max_attempts: 3,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Colt.Resources.OutboundEmail
  alias Colt.Services.Sending.SendOne

  def enqueue(email_id) when is_binary(email_id) do
    %{"email_id" => email_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def backoff(%Oban.Job{attempt: attempt}) do
    # 30s, 120s, 300s
    trunc(:math.pow(attempt, 3) * 30)
  end

  @impl true
  def perform(%Oban.Job{args: %{"email_id" => email_id}, attempt: attempt, max_attempts: max}) do
    case SendOne.run(email_id) do
      {:ok, _} = ok ->
        ok

      {:error, reason} when attempt >= max ->
        mark_failed(email_id)
        {:error, reason}

      {:error, _reason} = err ->
        err
    end
  end

  defp mark_failed(email_id) do
    case Ash.get(OutboundEmail, email_id, authorize?: false) do
      {:ok, email} -> OutboundEmail.mark_failed(email, authorize?: false)
      _ -> :ok
    end
  end
end
