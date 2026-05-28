defmodule ColtWeb.Plugs.Locale do
  @moduledoc """
  Resolves the request locale and applies it to Gettext.

  Priority:
    1. `:locale` cookie (explicit user choice)
    2. `current_user.locale` (logged-in user preference)
    3. Host TLD (.ee → et, .fi → fi, .no → nb, ...)
    4. Default ("en")

  Also stores the resolved locale in the session so LiveViews can pick it up
  via `ColtWeb.LiveLocale` on_mount.
  """
  import Plug.Conn

  @cookie "locale"
  @cookie_opts [max_age: 60 * 60 * 24 * 365, same_site: "Lax"]

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Application.get_env(:colt, :locales, [])
    available = Keyword.get(cfg, :available, ["en"])
    default = Keyword.get(cfg, :default, "en")
    tld_map = Keyword.get(cfg, :tld_map, %{})

    locale =
      from_cookie(conn, available) ||
        from_user(conn, available) ||
        from_host(conn, tld_map, available) ||
        default

    Gettext.put_locale(ColtWeb.Gettext, locale)

    conn = maybe_backfill_user_locale(conn, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
    |> maybe_persist_cookie(locale)
  end

  defp maybe_backfill_user_locale(conn, locale) do
    case conn.assigns[:current_user] do
      %Colt.Accounts.User{locale: nil} = user ->
        _ = Colt.Accounts.set_user_locale(user, locale, actor: user)
        conn

      _ ->
        conn
    end
  end

  defp from_cookie(conn, available) do
    conn = fetch_cookies(conn)

    case conn.cookies[@cookie] do
      loc when is_binary(loc) -> if loc in available, do: loc
      _ -> nil
    end
  end

  defp from_user(conn, available) do
    case conn.assigns[:current_user] do
      %{locale: loc} when is_binary(loc) -> if loc in available, do: loc
      _ -> nil
    end
  end

  defp from_host(conn, tld_map, available) do
    tld =
      conn.host
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> to_string()
      |> String.downcase()

    case Map.get(tld_map, tld) do
      loc when is_binary(loc) -> if loc in available, do: loc
      _ -> nil
    end
  end

  defp maybe_persist_cookie(conn, locale) do
    case conn.cookies[@cookie] do
      ^locale -> conn
      _ -> put_resp_cookie(conn, @cookie, locale, @cookie_opts)
    end
  end

  @doc "Cookie name used for the locale override."
  def cookie_name, do: @cookie

  @doc "Default cookie options for the locale cookie."
  def cookie_opts, do: @cookie_opts
end
