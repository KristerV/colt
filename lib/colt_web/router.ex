defmodule ColtWeb.Router do
  use ColtWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ColtWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug ColtWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :require_admin do
    plug :ensure_admin
  end

  pipeline :stripe_webhook do
    plug :accepts, ["json"]
  end

  scope "/", ColtWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [ColtWeb.LiveLocale, ColtWeb.UsageAssign] do
      live "/", HomeLive
      live "/search", SearchLive
      live "/campaigns", Campaigns.IndexLive
      live "/campaigns/new", Campaigns.NewLive
      live "/campaigns/:id/name", Campaigns.NameLive
      live "/campaigns/:id/icp", Campaigns.IcpLive
      live "/campaigns/:id/filters", Campaigns.FiltersLive
      live "/campaigns/:id/suppression", Campaigns.SuppressionLive
      live "/campaigns/:id/target", Campaigns.TargetLive
      live "/campaigns/:id/funnel", Campaigns.FunnelLive
      live "/campaigns/:id/funnel/:bucket", Campaigns.FunnelLive
      live "/campaigns/:id/pitch", Sending.PitchLive
      live "/campaigns/:id/sending-accounts", Sending.SendingAccountsLive, :index
      live "/campaigns/:id/sending-accounts/add", Sending.SendingAccountsLive, :picker
      live "/email-accounts/:account_id/settings", Account.EmailAccountDetailLive, :index
      live "/email-accounts/:account_id/stats", Account.EmailAccountStatsLive, :index
      live "/campaigns/:id/sending-funnel", Sending.SendingFunnelLive
      live "/campaigns/:id/sending-funnel/:bucket", Sending.SendingFunnelLive
      live "/campaigns/:id/sending-funnel/:bucket/:contact_id", Sending.SendingFunnelLive
      live "/campaigns/:id/sales/setup", Sales.SalesSetupLive
      live "/campaigns/:id/sales", Sales.SalesFunnelLive
      live "/campaigns/:id/sales/:stage", Sales.SalesFunnelLive
      live "/campaigns/:id/sales/:stage/:contact_id", Sales.SalesFunnelLive
      live "/campaigns/:id/write", Sending.WriteLive
      live "/campaigns/:id/write/:variant_id", Sending.WriteLive
      live "/campaigns/:id/variants", Sending.VariantsLive
      live "/campaigns/:id/settings", Sending.SettingsLive
      live "/email-accounts", Account.EmailAccountsLive
      live "/billing", Account.BillingLive
      live "/admin", AdminLive
      live "/admin/campaigns", Admin.CampaignsLive
      live "/admin/countries", Admin.CountriesLive
      live "/admin/storage", Admin.StorageLive
      live "/admin/costs", Admin.CostsLive
      live "/admin/clients-spending", Admin.ClientsSpendingLive
      live "/admin/clients", Admin.ClientsLive
      live "/admin/feedback", Admin.FeedbackLive
      live "/admin/system", Admin.SystemLive
      live "/admin/tracking-domain", Admin.TrackingDomainLive
    end

    ash_authentication_live_session :public_routes,
      on_mount: [ColtWeb.LiveLocale, {ColtWeb.LiveUserAuth, :live_user_optional}] do
      live "/pricing", PricingLive
      live "/privacy", PrivacyLive
      live "/terms", TermsLive
    end

    post "/locale", LocaleController, :set

    post "/billing/checkout", BillingController, :checkout
    post "/billing/portal", BillingController, :portal

    get "/campaigns/:id/export.csv", ExportController, :csv

    get "/email-accounts/connect/:provider", EmailAccountController, :connect
    get "/email-accounts/callback", EmailAccountController, :callback
  end

  scope "/" do
    pipe_through [:browser, :require_admin]

    oban_dashboard("/admin/oban")
    live_dashboard "/admin/phoenix", metrics: ColtWeb.Telemetry
  end

  scope "/", ColtWeb do
    pipe_through :browser

    auth_routes AuthController, Colt.Accounts.User, path: "/auth"

    sign_out_route AuthController,
                   "/sign-out",
                   overrides: [
                     ColtWeb.AuthOverrides,
                     Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                   ]

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{ColtWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    ColtWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  ColtWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Colt.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [ColtWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Colt.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [ColtWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  scope "/", ColtWeb do
    pipe_through :stripe_webhook
    post "/webhooks/stripe", StripeWebhookController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", ColtWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:colt, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  defp ensure_admin(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_admin: true} ->
        conn

      %{} ->
        conn
        |> Phoenix.Controller.put_flash(:error, "Admins only.")
        |> Phoenix.Controller.redirect(to: "/")
        |> Plug.Conn.halt()

      _ ->
        conn
        |> Phoenix.Controller.redirect(to: "/sign-in")
        |> Plug.Conn.halt()
    end
  end
end
