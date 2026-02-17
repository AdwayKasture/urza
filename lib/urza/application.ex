defmodule Urza.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database repository
      Urza.Repo,
      # Registry for agent process discovery
      {Registry, keys: :unique, name: Urza.AgentRegistry},
      # Registry for workflow process discovery
      {Registry, keys: :unique, name: Urza.WorkflowRegistry},
      # DynamicSupervisor for agent processes
      Urza.AgentSupervisor,
      # DynamicSupervisor for workflow processes
      Urza.WorkflowSupervisor,
      # In-memory persistence adapter
      Urza.Persistence.ETS,
      # Oban for background job processing
      {Oban, Application.get_env(:urza, Oban, [])}
    ]

    opts = [strategy: :one_for_one, name: Urza.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
