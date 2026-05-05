defmodule ColtWeb.Layouts do
  @moduledoc """
  Layouts for the Liid app.

  Use `<Layouts.app>` from any LiveView. It wraps content in the Liid screen
  (paper bg + top bar) and emits flash messages.
  """
  use ColtWeb, :html

  alias ColtWeb.Components.Liid

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_user, :map, default: nil
  attr :step, :any, default: nil
  attr :campaign_name, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <Liid.screen
      step={@step}
      current_user={@current_user}
      campaign_name={@campaign_name}
      class={@class}
    >
      {render_slot(@inner_block)}
    </Liid.screen>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end
end
