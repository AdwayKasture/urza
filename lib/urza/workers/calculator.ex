defmodule Urza.Workers.Calculator do
  @moduledoc """
  Tool worker for performing mathematical calculations.
  """
  @behaviour Urza.Tool
  alias Urza.AI.Agent
  require Logger

  use Oban.Worker, queue: :default


  defguardp are_numbers(a,b) when is_number(a) and is_number(b)

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
    "This tool performs mathematical calculations. Supports basic arithmetic operations: add, subtract, multiply, divide."
  end

  @impl Urza.Tool
  def run(%{"op" => "add", "a" => a, "b" => b}) when are_numbers(a,b) do
    {:ok, a + b}
  end

  def run(%{"op" => "subtract", "a" => a, "b" => b}) when are_numbers(a,b) do
    {:ok, a - b}
  end

  def run(%{"op" => "multiply", "a" => a, "b" => b}) when are_numbers(a,b) do
    {:ok, a * b}
  end

  def run(%{"op" => "divide", "a" => a, "b" => b}) when are_numbers(a,b) do
    if b == 0 do
      {:error, "Division by zero"}
    else
      {:ok, a / b}
    end
  end

  def run(%{"op" => op}) when op not in ["add","subtract","multiply","divide"] do
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
end
