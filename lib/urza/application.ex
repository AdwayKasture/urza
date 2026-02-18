defmodule Urza.Application do
  @moduledoc """
  Application supervisor for Urza AI Agent library.

  ## Oban Requirement

  This library requires Oban to be running in the parent application. Oban is NOT
  started by this library - the parent application is responsible for:

  1. Adding Oban as a dependency in their mix.exs
  2. Configuring Oban in their config files
  3. Starting Oban in their application supervision tree BEFORE starting Urza
  4. Registering tools using `Urza.Toolset.register_tools/1` before starting agents

  ## Example Parent Application Setup

      # mix.exs
      defp deps do
        [
          {:urza, path: "../urza"},
          {:oban, "~> 2.20"}  # Required!
        ]
      end
      
      # config/config.exs
      config :my_app, Oban,
        repo: MyApp.Repo,
        plugins: [Oban.Plugins.Pruner],
        queues: [
          default: 10,
          agent_tools: 20
        ]
      
      # lib/my_app/application.ex
      def start(_type, _args) do
        # Register tools first (they are Oban workers)
        Urza.Toolset.register_tools([
          Urza.Workers.Calculator,
          Urza.Workers.Web,
          MyApp.Tools.CustomTool
        ])
        
        children = [
          MyApp.Repo,
          {Oban, Application.fetch_env!(:my_app, Oban)},  # Oban first!
          Urza.Supervisor  # Then Urza
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ## Tool Requirements

  All tools MUST be Oban workers that implement the `Urza.Tool` behaviour:

  - Use `use Oban.Worker` to become an Oban worker
  - Add `@behaviour Urza.Tool` to implement the behaviour
  - Implement all required callbacks: `name/0`, `run/1`, `input_schema/0`, `output_schema/0`, `queue/0`
  - Call `Urza.AI.Agent.send_tool_result/2` in the `perform/1` callback
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database repository (optional, used by persistence adapters)
      # Urza.Repo,
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
