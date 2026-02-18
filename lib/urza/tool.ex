defmodule Urza.Tool do
  @moduledoc """
  A behaviour for tools that can be used by AI agents.

  All tools in Urza MUST be Oban workers that implement this behaviour.
  Tools execute as background jobs and can communicate results back to agents.

  ## Required Implementations

  Every tool module must:
  1. Use `Oban.Worker` to become an Oban worker
  2. Implement all callbacks defined in this behaviour
  3. Call `Agent.send_tool_result/2` in their `perform/1` callback

  ## Example

      defmodule MyApp.Tools.Calculator do
        use Oban.Worker, queue: :default
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
        def name(), do: "calculator"
        
        @impl Urza.Tool
        def description() do
          "Performs basic arithmetic operations"
        end
        
        @impl Urza.Tool
        def run(%{"op" => "add", "a" => a, "b" => b}) do
          {:ok, a + b}
        end
        
        @impl Urza.Tool
        def input_schema() do
          [
            op: [type: :string, required: true],
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          ]
        end
        
        @impl Urza.Tool
        def output_schema() do
          [type: :number, required: true]
        end
        
        @impl Urza.Tool
        def queue(), do: :default
      end

  """

  @doc """
  Returns the unique name of the tool as a string.
  This is used to identify the tool in agent interactions.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.
  This helps the AI understand when and how to use the tool.
  """
  @callback description() :: String.t()

  @doc """
  Execute the tool with the given arguments.
  Returns {:ok, result} on success or {:error, reason} on failure.

  This function is called by the Oban worker's perform/1 callback.
  """
  @callback run(map()) :: {:ok, any()} | {:error, any()}

  @doc """
  Returns the input schema for the tool as a keyword list.
  Defines what parameters the tool expects.
  """
  @callback input_schema() :: Keyword.t()

  @doc """
  Returns the output schema for the tool as a keyword list.
  Defines what the tool returns.
  """
  @callback output_schema() :: Keyword.t()

  @doc """
  Returns the Oban queue name for this tool.
  This determines which queue the tool job will be placed in.
  """
  @callback queue() :: atom()

  @optional_callbacks [
    description: 0
  ]

  @doc """
  Creates an Oban job changeset for the given tool module.

  Uses the tool's `new/2` function (provided by Oban.Worker) to create
  a changeset with the appropriate queue.
  """
  def new_job(tool_module, args, meta \\ %{}) do
    tool_module.new(args, meta: meta)
  end
end
