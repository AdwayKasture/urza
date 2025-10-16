defmodule Urza.Tools.Branch do
  alias Phoenix.PubSub
  use Oban.Worker
  @behaviour Urza.Tool

  # note this is a special tool and send control flow nessage which is handled separately

  @impl Oban.Worker
  def perform(%Job{args: args, id: id, meta: %{"workflow_id" => wf}}) do
    {:ok, refs} = run(args)
    # publish  on id
    PubSub.broadcast(Urza.PubSub, wf, {:branch, id, refs})
    :ok
  end

  @impl Urza.Tool
  def name(), do: "used to demo branching"

  @impl Urza.Tool
  def description(), do: "checks condition and chooses to trigger true or false jobs"

  @impl Urza.Tool
  def run(%{"condition" => condition, "true" => t, "false" => f}) do
    case condition do
      true -> {:ok, [t]}
      false -> {:ok, [f]}
    end
  end

  @impl Urza.Tool
  def run(_), do: {:ok, "failed to run invalid inputs"}

  @impl Urza.Tool
  def parameter_schema() do
    [type: :string, required: true]
  end

  @impl Urza.Tool
  def return_schema() do
    [type: :string, required: true]
  end
end
