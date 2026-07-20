defmodule Colt.Nylas do
  @moduledoc """
  Thin wrapper around the Nylas v3 EU API.

  Docs: https://developer.nylas.com/docs/v3/
  Base URL: configured via `:colt, :nylas, :api_uri` (default `https://api.eu.nylas.com`).

  Surface (E1):
    * `hosted_auth_url/2` — build the redirect URL for Nylas's hosted auth.
    * `exchange_callback/1` — swap the auth code for a `grant_id`.
    * `send_message/2` — `POST /v3/grants/{grant_id}/messages/send`.
    * `list_messages/2` — `GET /v3/grants/{grant_id}/messages`.
    * `list_folders/1` — `GET /v3/grants/{grant_id}/folders`.
    * `get_message/2` — `GET /v3/grants/{grant_id}/messages/{id}`.
    * `revoke/1` — `DELETE /v3/grants/{grant_id}` (server-key auth).

  Per project convention: every function returns `{:ok, term} | {:error, term}`.
  No retries in the client — Oban owns retry semantics for jobs that call us.
  """

  require Logger

  @auth_path "/v3/connect/auth"
  @token_path "/v3/connect/token"
  @custom_path "/v3/connect/custom"

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  URL for the Nylas hosted-auth screen. The user is redirected here from
  the "Connect Gmail / Outlook / IMAP" buttons. After they authorize,
  Nylas redirects them back to `redirect_uri` with `?code=…&state=…`.
  """
  @spec hosted_auth_url(:google | :m365 | :imap, keyword()) :: String.t()
  def hosted_auth_url(provider, opts) when provider in [:google, :m365, :imap] do
    cfg = config!()
    state = Keyword.fetch!(opts, :state)
    login_hint = Keyword.get(opts, :login_hint)

    params =
      %{
        client_id: cfg[:client_id],
        redirect_uri: cfg[:redirect_uri],
        response_type: "code",
        access_type: "offline",
        provider: provider_param(provider),
        state: state
      }
      |> maybe_put(:login_hint, login_hint)

    cfg[:api_uri] <> @auth_path <> "?" <> URI.encode_query(params)
  end

  @doc """
  Exchange the authorization `code` returned to our callback for a Nylas
  grant. Returns `{:ok, %{grant_id, email, provider, ...}}`.
  """
  @spec exchange_callback(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_callback(code) when is_binary(code) do
    cfg = config!()

    body = %{
      client_id: cfg[:client_id],
      client_secret: cfg[:api_key],
      grant_type: "authorization_code",
      code: code,
      redirect_uri: cfg[:redirect_uri]
    }

    cfg[:api_uri]
    |> Kernel.<>(@token_path)
    |> Req.post(json: body, retry: false, receive_timeout: 30_000)
    |> handle(:exchange)
  end

  @doc """
  Create a grant from raw IMAP/SMTP credentials via custom authentication
  (`POST /v3/connect/custom`) — no hosted-auth redirect. Used for bulk CSV
  import of inboxes (including Google Workspace accounts connected over IMAP
  with an app password).

  `settings` is the Nylas IMAP settings map with string keys:
  `imap_username`, `imap_password`, `imap_host`, `imap_port` and the matching
  `smtp_*` fields. Nylas only returns a grant if it can actually log in, so a
  `{:error, _}` here means bad creds / unreachable host.

  Returns the grant object `{:ok, %{"id" => grant_id, "email" => ..., ...}}`.
  """
  @spec create_imap_grant(map()) :: {:ok, map()} | {:error, term()}
  def create_imap_grant(settings) when is_map(settings) do
    request(:post, @custom_path, json: %{provider: "imap", settings: settings})
    |> handle(:create_grant)
  end

  @doc """
  Send a message through `email_account`'s Nylas grant.

  Required opts: `:to` (list of `%{email: , name: }` maps or plain strings),
  `:subject`, `:body`. Optional: `:reply_to_message_id`, `:tracking_options`.
  """
  @spec send_message(Colt.Resources.EmailAccount.t() | String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def send_message(account_or_grant, opts) do
    grant_id = grant_id_for(account_or_grant)

    payload =
      %{
        to: normalize_recipients(Keyword.fetch!(opts, :to)),
        subject: Keyword.fetch!(opts, :subject),
        body: Keyword.fetch!(opts, :body)
      }
      |> maybe_put(:reply_to_message_id, Keyword.get(opts, :reply_to_message_id))
      |> maybe_put(:tracking_options, Keyword.get(opts, :tracking_options))

    request(:post, "/v3/grants/#{grant_id}/messages/send", json: payload)
    |> handle(:send_message)
  end

  @doc """
  List messages for a grant. Opts: `:received_after` (unix ts), `:in` (folder),
  `:limit`.
  """
  @spec list_messages(Colt.Resources.EmailAccount.t() | String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def list_messages(account_or_grant, opts \\ []) do
    grant_id = grant_id_for(account_or_grant)

    params =
      opts
      |> Keyword.take([:received_after, :in, :limit, :unread])
      |> Enum.into(%{})

    request(:get, "/v3/grants/#{grant_id}/messages", params: params)
    |> handle(:list_messages)
  end

  @doc """
  List the grant's folders (labels). `GET /v3/grants/{grant_id}/folders`.
  Used to resolve the real inbox folder id — Nylas v3's `in` filter wants a
  folder id (e.g. `v0:<grant>:INBOX`), not the literal string `"INBOX"`.
  """
  @spec list_folders(Colt.Resources.EmailAccount.t() | String.t()) ::
          {:ok, list(map())} | {:error, term()}
  def list_folders(account_or_grant) do
    grant_id = grant_id_for(account_or_grant)

    request(:get, "/v3/grants/#{grant_id}/folders")
    |> handle(:list_folders)
  end

  @doc "Fetch one message by Nylas id."
  @spec get_message(Colt.Resources.EmailAccount.t() | String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_message(account_or_grant, message_id) when is_binary(message_id) do
    grant_id = grant_id_for(account_or_grant)

    # IMAP grants report the raw RFC Message-ID (e.g. "<x@mail.gmail.com>") as
    # the message id; its `<`, `>`, `@`, `=` must be percent-encoded or the
    # request target is rejected.
    encoded = URI.encode(message_id, &URI.char_unreserved?/1)

    request(:get, "/v3/grants/#{grant_id}/messages/#{encoded}")
    |> handle(:get_message)
  end

  @doc "Revoke (disconnect) a grant. Idempotent — 404s are treated as success."
  @spec revoke(Colt.Resources.EmailAccount.t() | String.t()) :: :ok | {:error, term()}
  def revoke(account_or_grant) do
    grant_id = grant_id_for(account_or_grant)

    case request(:delete, "/v3/grants/#{grant_id}") do
      {:ok, %Req.Response{status: status}} when status in 200..299 or status == 404 -> :ok
      other -> handle(other, :revoke)
    end
  end

  # ── Internals ───────────────────────────────────────────────────────

  defp request(method, path, opts \\ []) do
    cfg = config!()
    url = cfg[:api_uri] <> path

    Req.request(
      [
        method: method,
        url: url,
        headers: [
          {"authorization", "Bearer #{cfg[:api_key]}"},
          {"accept", "application/json"}
        ],
        retry: false,
        receive_timeout: 30_000
      ] ++ opts
    )
  end

  defp handle({:ok, %Req.Response{status: status, body: body}}, _label)
       when status in 200..299 do
    {:ok, unwrap(body)}
  end

  defp handle({:ok, %Req.Response{status: status, body: body}}, label) do
    Logger.warning("nylas #{label} http #{status}: #{inspect(body)}")
    {:error, {:http, status, body}}
  end

  defp handle({:error, %{__exception__: true} = exception}, label) do
    Logger.warning("nylas #{label} transport: #{Exception.message(exception)}")
    {:error, exception}
  end

  defp handle({:error, reason}, label) do
    Logger.warning("nylas #{label} error: #{inspect(reason)}")
    {:error, reason}
  end

  # Nylas v3 wraps single-resource responses in {"data": …, "request_id": …}.
  # List responses use the same wrapper with `data` as an array.
  defp unwrap(%{"data" => data}), do: data
  defp unwrap(other), do: other

  defp grant_id_for(%Colt.Resources.EmailAccount{nylas_grant_id: id}) when is_binary(id), do: id
  defp grant_id_for(id) when is_binary(id), do: id

  defp normalize_recipients(recipients) when is_list(recipients) do
    Enum.map(recipients, fn
      %{email: _} = r -> r
      email when is_binary(email) -> %{email: email}
    end)
  end

  defp normalize_recipients(email) when is_binary(email), do: [%{email: email}]

  defp provider_param(:google), do: "google"
  defp provider_param(:m365), do: "microsoft"
  defp provider_param(:imap), do: "imap"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp config! do
    cfg = Application.fetch_env!(:colt, :nylas)

    Enum.each([:api_uri, :client_id, :api_key, :redirect_uri], fn key ->
      Keyword.fetch!(cfg, key)
    end)

    cfg
  end
end
