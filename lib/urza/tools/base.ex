defmodule Urza.Tools.Base do
  @moduledoc """
  A base macro for creating Urza tools with Oban worker integration.

  This macro abstracts away the boilerplate for:
  - Oban worker setup
  - PubSub broadcasting of results
  - Tool behaviour implementation

  ## Usage

      defmodule MyTool do
        use Urza.Tools.Base, queue: :default, max_attempts: 3

        @impl true
        def name, do: "my_tool"

        @impl true
        def description, do: "Does something useful"

        @impl true
        def run(%{"input" => input}) do
          {:ok, process(input)}
        end

        @impl true
        def parameter_schema do
          [
            input: [
              type: :string,
              required: true,
              doc: "The input to process"
            ]
          ]
        end

        @impl true
        def return_schema do
          [type: :string, required: true]
        end
      end

  ## Options

  - `:queue` - Oban queue name (default: :default)
  - `:max_attempts` - Maximum retry attempts (default: 1)
  - `:priority` - Job priority, 0 is highest (default: 0)
  """

  alias Phoenix.PubSub

  defmacro __using__(opts \\ []) do
    quote do
      @oban_opts unquote(opts)

      use Oban.Worker,
        queue: Keyword.get(@oban_opts, :queue, :default),
        max_attempts: Keyword.get(@oban_opts, :max_attempts, 1),
        priority: Keyword.get(@oban_opts, :priority, 0)

      @behaviour Urza.Tool

      @impl Oban.Worker
      def perform(%Oban.Job{args: args, id: id, meta: meta}) do
        {:ok, ret} = run(args)

        # Handle both agent context (id key) and workflow context (workflow_id key)
        topic =
          case meta do
            %{"workflow_id" => wf_id} -> wf_id
            %{"id" => agent_id} -> "agent:#{agent_id}:logs"
            _ -> nil
          end

        if topic do
          ref = meta["ref"]
          PubSub.broadcast(Urza.PubSub, topic, {id, %{ref => ret}})
        end

        :ok
      end

      @impl Urza.Tool
      def description, do: ""

      defoverridable description: 0
    end
  end
end
