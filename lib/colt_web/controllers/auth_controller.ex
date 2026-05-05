defmodule ColtWeb.AuthController do
  use ColtWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn =
      case activity do
        {:confirm_new_user, :confirm} ->
          put_flash(conn, :info, "Your email address has now been confirmed")

        {:password, :reset} ->
          put_flash(conn, :info, "Your password has successfully been reset")

        _ ->
          conn
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
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
