defmodule Colt.Jobs.CategorizeReply do
  @moduledoc """
  Per-inbound classification job. Wraps `Colt.Services.Sending.CategorizeReply`.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [
      keys: [:email_id],
      period: 86_400,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias Colt.Services.Sending.CategorizeReply

  def enqueue(email_id) when is_binary(email_id) do
    %{"email_id" => email_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    CategorizeReply.run(email_id)
  end
end
