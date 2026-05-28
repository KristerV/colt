defmodule ColtWeb.LocaleController do
  @moduledoc """
  Switches the active locale. Sets the `locale` cookie and — if a user is
  signed in — also persists `user.locale` so the choice follows them.
  """
  use ColtWeb, :controller

  alias ColtWeb.Plugs.Locale

  @available ~w(en et lv lt fi sv nb da is)

  def set(conn, %{"locale" => locale} = params) do
    if locale in @available do
      _ = maybe_update_user(conn, locale)

      conn
      |> put_resp_cookie(Locale.cookie_name(), locale, Locale.cookie_opts())
      |> put_session(:locale, locale)
      |> redirect(to: redirect_to(params, conn))
    else
      conn
      |> put_flash(:error, "Unsupported locale.")
      |> redirect(to: redirect_to(params, conn))
    end
  end

  defp maybe_update_user(conn, locale) do
    case conn.assigns[:current_user] do
      %Colt.Accounts.User{} = user ->
        Colt.Accounts.set_user_locale(user, locale, actor: user)

      _ ->
        :ok
    end
  end

  defp redirect_to(%{"return_to" => path}, _conn) when is_binary(path) do
    if String.starts_with?(path, "/"), do: path, else: "/"
  end

  defp redirect_to(_params, conn) do
    case get_req_header(conn, "referer") do
      [ref | _] ->
        uri = URI.parse(ref)
        if uri.path, do: uri.path, else: "/"

      _ ->
        "/"
    end
  end
end
