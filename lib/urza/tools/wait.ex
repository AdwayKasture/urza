defmodule Urza.Tools.Wait do
  use Oban.Worker
  @behaviour Urza.Tool
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Job{args: args, id: id, meta: %{"workflow_id" => wf, "ref" => ref}}) do
    {:ok, ret} = run(args)
    # publish  on id
    PubSub.broadcast(Urza.PubSub, wf, {id, %{ref => ret}})
    :ok
  end

  @impl Urza.Tool
  def run(_) do
    1000..2000
    |> Enum.random()
    |> Process.sleep()

    {:ok, "sleeep!"}
  end

  @impl Urza.Tool
  def name(), do: "sleep"

  @impl Urza.Tool
  def description(), do: "Used to sleep a random duration"

  @impl Urza.Tool
  def return_schema(), do: []

  @impl Urza.Tool
  def parameter_schema(), do: []
end
