defmodule ColtWeb.Admin.SummaryHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:admin_tiles, ColtWeb.Admin.Summary.tiles())
      |> assign(:admin_current_path, nil)
      |> attach_hook(:admin_summary_path, :handle_params, &handle_path/3)

    {:cont, socket}
  end

  defp handle_path(_params, uri, socket) do
    path = uri |> URI.parse() |> Map.get(:path)
    {:cont, assign(socket, :admin_current_path, path)}
  end
end
