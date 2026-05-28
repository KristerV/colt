defmodule ColtWeb.LiveLocale do
  @moduledoc """
  on_mount hook that applies the locale to the LiveView process and assigns it
  to the socket.

      live_session :foo, on_mount: [ColtWeb.LiveLocale] do ... end
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    cfg = Application.get_env(:colt, :locales, [])
    available = Keyword.get(cfg, :available, ["en"])
    default = Keyword.get(cfg, :default, "en")

    locale =
      case session["locale"] do
        loc when is_binary(loc) -> if loc in available, do: loc, else: default
        _ -> default
      end

    Gettext.put_locale(ColtWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end
end
