defmodule Colt.Jobs.PollTracking do
  @moduledoc """
  Pull open + click counts for recently sent outbound emails in campaigns
  that have tracking on. Webhooks are deferred (v1 polls everything — see
  §15/§11 of docs/email-sending.md); this cron is the equivalent for
  tracking events.

  Cadence: every 10 minutes. Window: last 7 days. Per row we ask Nylas
  for the latest message payload and extract `tracking.opens` /
  `tracking.links` counts (Nylas v3 surface; verify shape at integration
  time). Updates only when counts change to keep `tracking_synced_at`
  meaningful.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 540, states: [:available, :scheduled, :executing]]

  require Logger

  alias Colt.Nylas
  alias Colt.Resources.{EmailAccount, OutboundEmail}

  @lookback_days 7
  @batch_limit 200

  @impl true
  def perform(_job) do
    since = DateTime.utc_now() |> DateTime.add(-@lookback_days * 86_400, :second)

    case OutboundEmail.list_recent_for_tracking(since,
           load: [:email_account],
           authorize?: false
         ) do
      {:ok, rows} ->
        rows
        |> Enum.take(@batch_limit)
        |> Enum.each(&sync_one/1)

        {:ok, min(length(rows), @batch_limit)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_one(%OutboundEmail{email_account: %EmailAccount{} = inbox} = email) do
    case Nylas.get_message(inbox, email.nylas_message_id) do
      {:ok, msg} ->
        {opens, clicks} = extract_counts(msg)

        if opens != email.opens_count or clicks != email.clicks_count do
          OutboundEmail.update_tracking_counts(email, opens, clicks, authorize?: false)
        end

      {:error, reason} ->
        Logger.debug("poll_tracking: #{email.id} skipped — #{inspect(reason)}")
        :error
    end
  end

  defp sync_one(_), do: :noop

  # Nylas v3 attaches tracking to the message payload. Field naming has
  # shifted between previews — try the documented shape first, then a
  # couple of fallbacks. Missing fields default to current counts (no
  # downgrade).
  defp extract_counts(msg) do
    tracking = Map.get(msg, "tracking") || Map.get(msg, :tracking) || %{}

    opens =
      tracking
      |> get_any(["opens", "open_count", :opens, :open_count])
      |> to_count()

    clicks =
      tracking
      |> get_any(["links", "link_clicks", "clicks", :links, :link_clicks, :clicks])
      |> to_count()

    {opens, clicks}
  end

  defp get_any(map, keys), do: Enum.find_value(keys, fn k -> Map.get(map, k) end)

  defp to_count(n) when is_integer(n) and n >= 0, do: n
  defp to_count(events) when is_list(events), do: length(events)
  defp to_count(_), do: 0
end
