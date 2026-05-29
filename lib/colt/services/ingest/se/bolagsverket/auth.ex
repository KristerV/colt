defmodule Colt.Services.Ingest.Se.Bolagsverket.Auth do
  @moduledoc """
  Fetches an OAuth2 client-credentials access token for Bolagsverket's
  "Värdefulla datamängder" (HVD) API.

  Credentials come from `config :colt, :bolagsverket, client_id:, client_secret:`.
  In prod these are read from env in `runtime.exs`; in dev they're typically
  left unset, in which case `run/0` returns `{:error, :missing_api_key}` —
  the orchestrator surfaces that without crashing.

  The token is returned to the caller and threaded through the rest of the
  pipeline; we don't cache it across runs because Oban dispatches the ingest
  monthly and a token lasts ~1h.
  """

  require Logger

  @token_url "https://portal.api.bolagsverket.se/oauth2/token"
  @scope "vardefulla-datamangder:read vardefulla-datamangder:ping"

  def run do
    with {:ok, %{id: id, secret: secret}} <- credentials(),
         {:ok, token} <- fetch_token(id, secret) do
      {:ok, token}
    end
  end

  defp credentials do
    cfg = Application.get_env(:colt, :bolagsverket, [])
    id = Keyword.get(cfg, :client_id)
    secret = Keyword.get(cfg, :client_secret)

    cond do
      is_binary(id) and id != "" and is_binary(secret) and secret != "" ->
        {:ok, %{id: id, secret: secret}}

      true ->
        Logger.warning("Bolagsverket ingest skipped: missing client_id/client_secret")
        {:error, :missing_api_key}
    end
  end

  defp fetch_token(id, secret) do
    body = "grant_type=client_credentials&scope=#{URI.encode_www_form(@scope)}"

    case Req.post(@token_url,
           headers: [
             {"content-type", "application/x-www-form-urlencoded"}
           ],
           auth: {:basic, "#{id}:#{secret}"},
           body: body,
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      other ->
        {:error, {:bolagsverket_token, other}}
    end
  end
end
