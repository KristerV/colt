defmodule Colt.Services.Enrichment.VerifyEmail do
  @moduledoc """
  Calls MyEmailVerifier to check whether a single email address is real.

  Returns `{:ok, :valid | :catch_all | :invalid}`. Transport-level errors bubble
  up so the caller can retry.

  `:catch_all` is reported rather than folded into `:valid`, because **what it
  means depends on where the address came from** and only the caller knows that:

  - A **scraped or registry-given** address on a catch-all domain is still good —
    a human published it, the domain accepting everything doesn't unpublish it.
  - A **guessed** address on a catch-all domain is worthless — the domain accepts
    every local part, so "it verified" carries no information at all.

  See `docs/specs/contact-acquisition.md` §3.
  """
  require Logger

  @base_url "https://api.myemailverifier.com/api/validate_single.php"

  def run(email) when is_binary(email) and email != "" do
    with {:ok, api_key} <- get_api_key(),
         {:ok, status} <- verify(email, api_key) do
      {:ok, status}
    end
  end

  def run(_), do: {:error, :no_email}

  defp get_api_key do
    case Application.get_env(:colt, :myemailverifier)[:api_key] do
      nil -> {:error, "myemailverifier api_key not configured"}
      "" -> {:error, "myemailverifier api_key not configured"}
      key -> {:ok, key}
    end
  end

  defp verify(email, api_key) do
    case Req.get(@base_url,
           params: [apikey: api_key, email: email],
           receive_timeout: 30_000,
           retry: :safe_transient,
           max_retries: 3
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_status(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("myemailverifier http #{status}: #{inspect(body)}")
        {:error, "myemailverifier http #{status}"}

      {:error, reason} ->
        Logger.warning("myemailverifier request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_status(%{"Status" => status}) do
    result =
      case status do
        "Valid" -> :valid
        "Catch-all" -> :catch_all
        _ -> :invalid
      end

    {:ok, result}
  end

  defp parse_status(body) do
    Logger.warning("myemailverifier unexpected response: #{inspect(body)}")
    {:error, :unexpected_response}
  end
end
