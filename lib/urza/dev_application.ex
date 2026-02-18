defmodule Urza.DevApplication do
  @moduledoc """
  Development application that starts Oban along with Urza.

  This is used during development and testing to provide a complete environment
  where Oban jobs can run. In production, the parent application is responsible
  for starting Oban before Urza.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database repository
      Urza.Repo,
      # Oban job processor (required for tools)
      {Oban, Application.fetch_env!(:urza, Oban)},
      # Registry for agent process discovery
      {Registry, keys: :unique, name: Urza.AgentRegistry},
      # Registry for workflow process discovery
      {Registry, keys: :unique, name: Urza.WorkflowRegistry},
      # DynamicSupervisor for agent processes
      Urza.AgentSupervisor,
      # DynamicSupervisor for workflow processes
      Urza.WorkflowSupervisor,
      # In-memory persistence adapter
      Urza.Persistence.ETS
    ]

    opts = [strategy: :one_for_one, name: Urza.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
