defmodule Urza.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UrzaWeb.Telemetry,
      Urza.Repo,
      {Registry, keys: :unique, name: Urza.WorkflowRegistry},
      {Registry, keys: :unique, name: Urza.AgentRegistry},
      Urza.WorkflowSupervisor,
      {DNSCluster, query: Application.get_env(:urza, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Urza.PubSub},
      {Oban, Application.fetch_env!(:urza, Oban)},
      # Start a worker by calling: Urza.Worker.start_link(arg)
      # {Urza.Worker, arg},
      # Start to serve requests, typically the last entry
      UrzaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Urza.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UrzaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
