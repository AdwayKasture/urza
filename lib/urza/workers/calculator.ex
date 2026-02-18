defmodule Urza.Workers.Calculator do
  @moduledoc """
  Tool worker for performing mathematical calculations.

  This module is both an Oban Worker and implements the Urza.Tool behaviour.

  ## Registration

      Urza.Toolset.register_tool(Urza.Workers.Calculator)

  ## Oban Configuration

  Configure the queue in your parent application's Oban config:

      config :my_app, Oban,
        queues: [
          default: 10,
          calculations: 5
        ]

  By default uses the `:default` queue. Override by changing `queue/0` return value.
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
        Logger.error("CalculatorWorker failed for job #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Urza.Tool
  def name(), do: "calculator"

  @impl Urza.Tool
  def description() do
    "Performs mathematical calculations. Supports basic arithmetic operations: add, subtract, multiply, divide."
  end

  @impl Urza.Tool
  def run(%{"op" => "add", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a + b}
  end

  def run(%{"op" => "subtract", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a - b}
  end

  def run(%{"op" => "multiply", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a * b}
  end

  def run(%{"op" => "divide", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    if b == 0 do
      {:error, "Division by zero"}
    else
      {:ok, a / b}
    end
  end

  def run(%{"op" => op}) when op not in ["add", "subtract", "multiply", "divide"] do
    {:error, "Unsupported operation: #{op}. Must be 'add', 'subtract', 'multiply', or 'divide'."}
  end

  def run(_) do
    {:error, "Invalid arguments. Requires 'op', 'a', and 'b' parameters."}
  end

  @impl Urza.Tool
  def input_schema() do
    [
      op: [
        type: :string,
        required: true,
        doc: "The operation to perform. One of: 'add', 'subtract', 'multiply', 'divide'."
      ],
      a: [
        type: :number,
        required: true,
        doc: "The first operand."
      ],
      b: [
        type: :number,
        required: true,
        doc: "The second operand."
      ]
    ]
  end

  @impl Urza.Tool
  def output_schema() do
    [type: :number, required: true]
  end

  @impl Urza.Tool
  def queue(), do: :default
end
