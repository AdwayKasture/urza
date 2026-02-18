defmodule Urza.Workers.Echo do
  @moduledoc """
  Tool worker for printing messages to IO.

  This module is both an Oban Worker and implements the Urza.Tool behaviour.

  ## Registration

      Urza.Toolset.register_tool(Urza.Workers.Echo)

  ## Oban Configuration

  Configure the queue in your parent application's Oban config:

      config :my_app, Oban,
        queues: [default: 10]

  By default uses the `:default` queue.
  """
  use Oban.Worker, queue: :default
  @behaviour Urza.Tool

  alias Urza.AI.Agent
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, meta: %{"id" => id}}) do
    case run(args) do
      {:ok, result} ->
        Agent.send_tool_result(id, to_string(result))
        :ok

      {:error, reason} ->
        Logger.error("EchoWorker failed for job #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Urza.Tool
  def name(), do: "echo"

  @impl Urza.Tool
  def description() do
    "Prints a message to standard output (IO). Useful for displaying results or debugging."
  end

  @impl Urza.Tool
  def run(%{"message" => message}) do
    IO.puts("[Echo] #{message}")
    {:ok, message}
  end

  def run(_) do
    {:error, "Invalid arguments. Requires 'message' parameter."}
  end

  @impl Urza.Tool
  def input_schema() do
    [
      message: [
        type: :string,
        required: true,
        doc: "The message to print to IO."
      ]
    ]
  end

  @impl Urza.Tool
  def output_schema() do
    [type: :string, required: true]
  end

  @impl Urza.Tool
  def queue(), do: :default
end
