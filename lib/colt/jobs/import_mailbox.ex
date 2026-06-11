defmodule Colt.Jobs.ImportMailbox do
  @moduledoc """
  Per-inbox CSV-import job. Thin Oban wrapper around
  `Colt.Services.EmailAccount.ConnectImapMailbox` — one job per mailbox row so
  a single bad credential doesn't sink the whole upload and each connect can
  retry independently. Unique on `user_id + address` so a double-submit doesn't
  mint duplicate Nylas grants.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      keys: [:user_id, :address],
      period: 3600,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Colt.Services.EmailAccount.ConnectImapMailbox

  @doc "Enqueue one mailbox spec (from `ImportMailboxes.run/1`) for `user_id`."
  def enqueue(user_id, mailbox) when is_binary(user_id) and is_map(mailbox) do
    %{
      "user_id" => user_id,
      "address" => mailbox.address,
      "display_name" => mailbox.display_name,
      "tz" => mailbox.tz,
      "settings" => mailbox.settings
    }
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"user_id" => user_id} = mailbox}) do
    case ConnectImapMailbox.run(user_id, mailbox) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
    end
  end
end
