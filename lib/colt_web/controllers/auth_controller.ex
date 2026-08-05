defmodule ColtWeb.AuthController do
  use ColtWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/campaigns"

    conn =
      case activity do
        {:confirm_new_user, :confirm} ->
          put_flash(conn, :info, "Your email address has now been confirmed")

        {:password, :reset} ->
          put_flash(conn, :info, "Your password has successfully been reset")

        _ ->
          conn
      end

    # Every strategy funnels through here, so it's the one place that sees the moment
    # someone stops being an anonymous visitor. Bind explicitly rather than waiting for
    # `AbFunnel.Plug.Visitor` to do it on the next request: the plug ran on *this* request
    # while `current_user` was still nil, and without the binding the sign-in itself lands
    # under a visitor nobody can join to the deck session that led here.
    bind_visitor_to_person(conn, user)
    AbFunnel.track(conn, "signed_in")

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  defp bind_visitor_to_person(conn, user) do
    case AbFunnel.person_key_for(user) do
      key when is_binary(key) -> AbFunnel.identify(conn, key)
      _ -> :ok
    end
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:colt)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
