defmodule Urza.Tools.Calculator do
  alias Phoenix.PubSub
  use Oban.Worker
  @behaviour Urza.Tool

  @impl Oban.Worker
  def perform(%Job{args: args, id: id, meta: %{"workflow_id" => wf, "ref" => ref}}) do
    {:ok, ret} = run(args)
    # publish  on id
    PubSub.broadcast(Urza.PubSub, wf, {id, %{ref => ret}})
    :ok
  end

  @impl Urza.Tool
  def name(), do: "calculator"

  @impl Urza.Tool
  def description(),
    do: "This tool is used to do two number arithmetics add/subtract/multiply/divide"

  @impl Urza.Tool
  def run(%{"l" => l, "r" => r, "op" => op}) do
    case op do
      "add" -> {:ok, _ = l + r}
      "subtract" -> {:ok, _ = l - r}
      "multiply" -> {:ok, _ = l * r}
      "divide" -> {:ok, _ = l / r}
    end
  end

  @impl Urza.Tool
  def parameter_schema() do
  [
    l: [
      type: :float,
      required: true,
      doc: "The left-hand operand for the calculation."
    ],
    r: [
      type: :float,
      required: true,
      doc: "The right-hand operand for the calculation."
    ],
    o: [
      type: :string,
      # 'required' defaults to false, matching the absence of 'required: true'
      doc: "The operation to perform (e.g., 'add', 'multiply')."
    ]
  ]
  end

  @impl Urza.Tool
  def return_schema() do
    [type: :integer, required: true]
  end
end
