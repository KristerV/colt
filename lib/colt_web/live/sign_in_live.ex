defmodule ColtWeb.SignInLive do
  @moduledoc """
  Sign-in page. Wraps AshAuthentication's `SignIn` component and adds a note
  that registration is closed — new accounts are created by hand on request.
  """
  use ColtWeb, :live_view

  alias AshAuthentication.Phoenix.Components

  @contact_email "liid@krister.ee"

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Sign in — Liid"),
       contact_email: @contact_email,
       overrides: Map.get(session, "overrides", [AshAuthentication.Phoenix.Overrides.Default]),
       otp_app: nil,
       path: session["path"] || "/",
       reset_path: session["reset_path"],
       register_path: session["register_path"],
       current_tenant: session["tenant"],
       resources: session["resources"],
       context: session["context"] || %{},
       auth_routes_prefix: session["auth_routes_prefix"],
       gettext_fn: session["gettext_fn"]
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas text-ink px-4 py-12 flex flex-col items-center justify-center gap-4">
      <.live_component
        module={Components.SignIn}
        otp_app={@otp_app}
        live_action={@live_action}
        path={@path}
        auth_routes_prefix={@auth_routes_prefix}
        resources={@resources}
        reset_path={@reset_path}
        register_path={@register_path}
        id="sign-in"
        overrides={@overrides}
        current_tenant={@current_tenant}
        context={@context}
        gettext_fn={@gettext_fn}
      />

      <div class="w-full max-w-[420px] bg-card border border-border rounded-[11px] shadow-card px-6 py-5 text-[14px] text-inkSoft">
        <p class="font-semibold text-ink mb-1">{gettext("No account yet?")}</p>
        <p>
          {gettext("Liid is invite-only for now. To get an account, email")}
          <a
            href={"mailto:#{@contact_email}"}
            class="text-accent font-semibold no-underline hover:underline"
          >
            {@contact_email}
          </a>.
        </p>
      </div>
    </div>
    """
  end
end
