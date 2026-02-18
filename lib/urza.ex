defmodule Urza do
  @moduledoc """
  Urza - AI Agent Library for Elixir

  Urza provides a framework for building AI agents that use tools to accomplish tasks.
  It uses Oban as the backbone for background job processing, delegating all Oban
  configuration and management to the parent application.

  ## Key Features

  - **Tool-based Architecture**: Define tools that agents can use to interact with the world
  - **ReAct Pattern**: Agents follow the Reasoning + Acting pattern for task completion
  - **Oban Integration**: All tools are Oban workers for reliable background processing
  - **PersistentTerm Registry**: Tools are registered at startup for O(1) lookups
  - **Pluggable Adapters**: Swap out LLM, persistence, and notification adapters

  ## Requirements

  - Oban must be added as a dependency in the parent application
  - All tools MUST be Oban workers that implement the `Urza.Tool` behaviour
  - Tools must be registered before starting agents

  ## Quick Start

  ### 1. Add to your mix.exs

      defp deps do
        [
          {:urza, path: "../urza"},
          {:oban, "~> 2.20"}  # Required for background job processing
        ]
      end

  ### 2. Configure Oban

      # config/config.exs
      config :my_app, Oban,
        repo: MyApp.Repo,
        plugins: [Oban.Plugins.Pruner],
        queues: [
          default: 10,
          agent_tools: 20  # Queue for agent tool execution
        ]

  ### 3. Create Custom Tools

  All tools must be Oban workers and implement the `Urza.Tool` behaviour:

      defmodule MyApp.Tools.CustomSearch do
        use Oban.Worker, queue: :agent_tools
        @behaviour Urza.Tool
        
        alias Urza.AI.Agent
        
        @impl Oban.Worker
        def perform(%Oban.Job{args: args, meta: %{"id" => agent_id}}) do
          case run(args) do
            {:ok, result} ->
              Agent.send_tool_result(agent_id, to_string(result))
              :ok
            {:error, reason} ->
              {:error, reason}
          end
        end
        
        @impl Urza.Tool
        def name(), do: "custom_search"
        
        @impl Urza.Tool
        def description(), do: "Searches a custom database"
        
        @impl Urza.Tool
        def run(%{"query" => query}) do
          # Your search logic here
          {:ok, results}
        end
        
        @impl Urza.Tool
        def input_schema() do
          [
            query: [type: :string, required: true, doc: "Search query"]
          ]
        end
        
        @impl Urza.Tool
        def output_schema() do
          [type: :list, required: true]
        end
        
        @impl Urza.Tool
        def queue(), do: :agent_tools
      end

  ### 4. Register Tools and Start Application

      # lib/my_app/application.ex
      def start(_type, _args) do
        # Register tools before starting agents
        Urza.Toolset.register_tools([
          Urza.Workers.Calculator,
          Urza.Workers.Web,
          MyApp.Tools.CustomSearch
        ])
        
        children = [
          MyApp.Repo,
          {Oban, Application.fetch_env!(:my_app, Oban)},
          Urza.Supervisor
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ### 5. Start an Agent

      {:ok, agent_pid} = Urza.AgentSupervisor.start_agent(
        name: "researcher",
        goal: "Research the latest Elixir news and summarize findings",
        tools: ["web", "custom_search"],
        input: "Find recent Elixir programming updates"
      )

  ## Tool Contract

  All tools must:

  1. **Use `Oban.Worker`** - Be a proper Oban worker with `use Oban.Worker`
  2. **Implement `@behaviour Urza.Tool`** - Implement all required callbacks
  3. **Call `Agent.send_tool_result/2`** - In the `perform/1` callback, send results back
  4. **Be registered** - Call `Urza.Toolset.register_tool/1` or `register_tools/1` at startup

  ## Architecture

  Urza consists of several key components:

  - **Agent**: The core GenServer that orchestrates tool execution via Oban jobs
  - **Tool**: Behaviour that all tools must implement (requires Oban.Worker)
  - **Toolset**: PersistentTerm-based registry for tool lookup
  - **Workflow**: For composing multiple agents together
  - **Adapters**: Pluggable interfaces for LLM, persistence, and notifications

  ## Future: Tool Macro

  A macro will be added to simplify tool creation:

      defmodule MyApp.Tools.CustomTool do
        use Urza.Tool, queue: :agent_tools
        
        @impl Urza.Tool
        def run(args), do: {:ok, result}
      end

  """

  @doc """
  Returns the version of the Urza library.
  """
  def version do
    "0.1.0"
  end

  @doc """
  Returns a list of built-in tool modules available in Urza.
  """
  def built_in_tools do
    [
      Urza.Workers.Calculator,
      Urza.Workers.Web,
      Urza.Workers.Echo
    ]
  end
end
