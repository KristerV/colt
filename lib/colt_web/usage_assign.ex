defmodule ColtWeb.UsageAssign do
  @moduledoc """
  on_mount hook that loads the usage calcs onto `current_user` so the shared
  sidebar usage badge (`ColtWeb.Components.Liid.usage_badge/1`) can render
  without every LiveView threading a separate assign. Fresh on each mount;
  the funnel view re-runs it on enrichment progress for live ticking.

  No-op when there is no signed-in user (public pages share this live_session).
  """
  import Phoenix.Component, only: [assign: 3]

  alias Colt.Accounts.User

  @calcs [:remaining_capacity, :monthly_screening_capacity, :remaining_screening]

  def on_mount(:default, _params, _session, socket) do
    {:cont, assign(socket, :current_user, load_usage(socket.assigns[:current_user]))}
  end

  @doc "Reloads the usage calcs onto a user struct. Public so LiveViews can refresh live."
  def load_usage(%User{} = user), do: Ash.load!(user, @calcs, authorize?: false)
  def load_usage(other), do: other
end
