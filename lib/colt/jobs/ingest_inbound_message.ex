defmodule Colt.Jobs.IngestInboundMessage do
  @moduledoc """
  Per-message ingest job. Thin Oban wrapper around
  `Colt.Services.Sending.IngestInbound`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      keys: [:email_account_id, :nylas_message_id],
      period: 86_400,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias Colt.Services.Sending.IngestInbound

  def enqueue(email_account_id, nylas_message_id)
      when is_binary(email_account_id) and is_binary(nylas_message_id) do
    %{"email_account_id" => email_account_id, "nylas_message_id" => nylas_message_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{
        args: %{"email_account_id" => account_id, "nylas_message_id" => message_id}
      }) do
    case IngestInbound.run(account_id, message_id) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
    end
  end
end
