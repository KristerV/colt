defmodule ColtWeb.Sending.PanicHook do
  @moduledoc """
  Live hook that lets any sending LiveView automatically react to the
  sidebar's PanicToggle without each LV reimplementing handle_info.

  Add to a LiveView with:

      on_mount {ColtWeb.Sending.PanicHook, :default}

  The hook expects `:campaign` in `socket.assigns`. It refreshes that
  assign whenever the PanicToggle component sends `{:panic_toggled,
  campaign}` to the parent process.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :panic_toggled, :handle_info, &handle/2)}
  end

  defp handle({:panic_toggled, campaign}, socket) do
    {:halt, assign(socket, :campaign, campaign)}
  end

  defp handle(_other, socket), do: {:cont, socket}
end
