defmodule Colt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ColtWeb.Telemetry,
      Colt.Repo,
      {DNSCluster, query: Application.get_env(:colt, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:colt, :ash_domains),
         Application.fetch_env!(:colt, Oban)
       )},
      {Phoenix.PubSub, name: Colt.PubSub},
      # Start a worker by calling: Colt.Worker.start_link(arg)
      # {Colt.Worker, arg},
      # Start to serve requests, typically the last entry
      ColtWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :colt]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Colt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ColtWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
