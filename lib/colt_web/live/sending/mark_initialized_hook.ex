defmodule ColtWeb.Sending.MarkInitializedHook do
  @moduledoc """
  Latches `Campaign.sending_initialized?` = true the first time a user enters
  any sending-phase view, so the Campaigns list can route them back to the
  sending funnel. Idempotent; only writes when the flag is still false.

  Add to a sending LiveView with:

      on_mount {ColtWeb.Sending.MarkInitializedHook, :default}

  Expects `:current_user` in assigns (set by `LiveUserAuth`, which must run
  earlier in the on_mount list) and an `"id"` param naming the campaign.
  """

  alias Colt.Resources.Campaign

  def on_mount(:default, %{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Campaign.get(id, actor: actor) do
      {:ok, %{sending_initialized?: false} = campaign} ->
        Campaign.mark_sending_initialized(campaign, actor: actor)

      _ ->
        :ok
    end

    {:cont, socket}
  end
end
