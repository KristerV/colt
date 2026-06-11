defmodule ColtWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use ColtWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {ColtWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  # Requires a signed-in user with an active plan (admins always pass — see
  # `Colt.Accounts.User.paid?/1`). Guards the post-pricing campaign steps so an
  # unpaid user can't skip the pricing gate by navigating there via the menu.
  def on_mount(:live_plan_required, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      user ->
        if Colt.Accounts.User.paid?(user) do
          {:cont, socket}
        else
          {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/pricing")}
        end
    end
  end

  def on_mount(:live_admin_required, _params, _session, socket) do
    case socket.assigns[:current_user] do
      %{is_admin: true} -> {:cont, socket}
      %{} -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end
end
