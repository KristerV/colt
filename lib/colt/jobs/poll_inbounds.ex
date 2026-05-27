defmodule Colt.Jobs.PollInbounds do
  @moduledoc """
  Inbound poller. Lists new messages per healthy `EmailAccount` since
  `last_sync_at`, fans them out to `Colt.Jobs.IngestInboundMessage`, and
  bumps `last_sync_at` to the newest `received_at` we observed.

  Cadence: 1-minute cron, same cadence as the send loop. Idempotency is
  handled downstream — `IngestInboundMessage` no-ops on any
  `nylas_message_id` we've already stored.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 55, states: [:available, :scheduled, :executing]]

  require Logger

  alias Colt.Nylas
  alias Colt.Resources.EmailAccount

  @lookback_padding_seconds 60
  @page_limit 50

  @impl true
  def perform(_job) do
    Enum.each(list_healthy(), &poll_one/1)
    :ok
  end

  defp list_healthy do
    case EmailAccount.list_healthy(authorize?: false) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  defp poll_one(%EmailAccount{} = account) do
    since = lookback(account.last_sync_at)

    case Nylas.list_messages(account, received_after: since, in: "INBOX", limit: @page_limit) do
      {:ok, messages} when is_list(messages) ->
        Enum.each(messages, fn msg ->
          case Map.get(msg, "id") do
            id when is_binary(id) ->
              Colt.Jobs.IngestInboundMessage.enqueue(account.id, id)

            _ ->
              :noop
          end
        end)

        bump_cursor(account, messages)

      {:error, reason} ->
        Logger.warning("poll_inbounds: #{account.address} failed — #{inspect(reason)}")
        :error
    end
  end

  defp lookback(nil) do
    # First-ever poll: only the most recent few minutes so we don't slurp
    # an entire historical inbox.
    DateTime.utc_now() |> DateTime.add(-5 * 60, :second) |> DateTime.to_unix(:second)
  end

  defp lookback(%DateTime{} = last) do
    # Tiny overlap so a message that landed in the same second isn't
    # missed. Idempotency at ingest covers the dupe risk.
    last
    |> DateTime.add(-@lookback_padding_seconds, :second)
    |> DateTime.to_unix(:second)
  end

  defp bump_cursor(account, messages) do
    latest =
      messages
      |> Enum.map(&Map.get(&1, "date"))
      |> Enum.filter(&is_integer/1)
      |> Enum.max(fn -> nil end)

    new_cursor =
      case latest do
        nil -> DateTime.utc_now()
        secs -> DateTime.from_unix!(secs, :second)
      end

    EmailAccount.touch_sync(account, new_cursor, authorize?: false)
  end
end
