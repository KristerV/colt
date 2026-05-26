defmodule ColtWeb.EmailAccountController do
  @moduledoc """
  Nylas hosted-auth round-trip.

  * `GET /email-accounts/connect/:provider` — generate a CSRF state, stash it
    in the session, and redirect the browser to Nylas's hosted-auth screen.
  * `GET /email-accounts/callback` — Nylas redirects here with `?code=…&state=…`.
    We verify state, exchange the code for a grant, persist the `EmailAccount`,
    then send the user back to `/email-accounts`.
  """
  use ColtWeb, :controller

  require Logger

  alias Colt.Nylas
  alias Colt.Resources.EmailAccount

  @session_state_key "nylas_oauth_state"

  def connect(conn, %{"provider" => provider_param}) do
    with {:ok, user} <- current_user(conn),
         {:ok, provider} <- parse_provider(provider_param) do
      state = generate_state()

      url =
        Nylas.hosted_auth_url(provider,
          state: state,
          login_hint: user.email && to_string(user.email)
        )

      conn
      |> put_session(@session_state_key, state)
      |> redirect(external: url)
    else
      {:error, :no_user} ->
        conn |> redirect(to: ~p"/sign-in")

      {:error, :bad_provider} ->
        conn
        |> put_flash(:error, "Unknown provider.")
        |> redirect(to: ~p"/email-accounts")
    end
  end

  def callback(conn, params) do
    expected_state = get_session(conn, @session_state_key)
    conn = delete_session(conn, @session_state_key)

    with {:ok, user} <- current_user(conn),
         :ok <- check_no_error(params),
         {:ok, code} <- fetch_param(params, "code"),
         :ok <- check_state(expected_state, params["state"]),
         {:ok, grant} <- Nylas.exchange_callback(code),
         {:ok, _account} <- persist_account(grant, user) do
      conn
      |> put_flash(:info, "Inbox connected.")
      |> redirect(to: ~p"/email-accounts")
    else
      {:error, reason} ->
        Logger.warning("nylas callback rejected: #{inspect(reason)}")

        conn
        |> put_flash(:error, callback_error_message(reason))
        |> redirect(to: ~p"/email-accounts")
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :no_user}
      user -> {:ok, user}
    end
  end

  defp parse_provider("google"), do: {:ok, :google}
  defp parse_provider("m365"), do: {:ok, :m365}
  defp parse_provider("microsoft"), do: {:ok, :m365}
  defp parse_provider("imap"), do: {:ok, :imap}
  defp parse_provider(_), do: {:error, :bad_provider}

  defp generate_state, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp check_state(nil, _), do: {:error, :missing_state}
  defp check_state(_, nil), do: {:error, :missing_state}

  defp check_state(expected, got) do
    if Plug.Crypto.secure_compare(expected, got), do: :ok, else: {:error, :state_mismatch}
  end

  defp check_no_error(%{"error" => err}), do: {:error, {:provider_error, err}}
  defp check_no_error(_), do: :ok

  defp fetch_param(params, key) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_param, key}}
    end
  end

  defp persist_account(grant, user) do
    provider = grant |> Map.get("provider", "imap") |> provider_atom()
    address = Map.get(grant, "email") || Map.get(grant, "email_address") || "unknown"

    EmailAccount.create_from_nylas(
      provider,
      address,
      Map.get(grant, "name"),
      Map.fetch!(grant, "grant_id"),
      Map.get(grant, "timezone") || "Europe/Tallinn",
      actor: user
    )
  end

  defp provider_atom("google"), do: :google
  defp provider_atom("microsoft"), do: :m365
  defp provider_atom("imap"), do: :imap
  defp provider_atom(_), do: :imap

  defp callback_error_message({:provider_error, err}), do: "Nylas refused the connect: #{err}"
  defp callback_error_message(:state_mismatch), do: "Connect link expired. Try again."
  defp callback_error_message(:missing_state), do: "Connect link expired. Try again."
  defp callback_error_message({:missing_param, _}), do: "Missing callback parameters."
  defp callback_error_message(_), do: "Could not connect inbox. Check logs."
end
