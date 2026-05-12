defmodule ColtWeb.Admin.SummaryHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, attach_hook: 4]

  @tick_ms 3000

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      :cpu_sup.util()
      :timer.send_interval(@tick_ms, :admin_summary_tick)
    end

    socket =
      socket
      |> assign(:admin_tiles, ColtWeb.Admin.Summary.tiles())
      |> assign(:admin_current_path, nil)
      |> attach_hook(:admin_summary_tick, :handle_info, &handle_message/2)
      |> attach_hook(:admin_summary_path, :handle_params, &handle_path/3)

    {:cont, socket}
  end

  defp handle_message(:admin_summary_tick, socket) do
    {:halt, assign(socket, :admin_tiles, ColtWeb.Admin.Summary.tiles())}
  end

  defp handle_message(_msg, socket), do: {:cont, socket}

  defp handle_path(_params, uri, socket) do
    path = uri |> URI.parse() |> Map.get(:path)
    {:cont, assign(socket, :admin_current_path, path)}
  end
end
