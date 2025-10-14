defmodule Urza.Tools.Echo do
  alias Phoenix.PubSub
  use Oban.Worker
  @behaviour Urza.Tool

  @impl Oban.Worker
  def perform(%Job{args: args,id: id,meta: %{"workflow_id" => wf}}) do
    {:ok,_ret} = run(args)
    #publish  on id
    PubSub.broadcast(Urza.PubSub,wf,{id,%{}})
    :ok
  end

  @impl Urza.Tool
  def name(),do: "echo"

  @impl Urza.Tool
  def description(),do: "This tool is used to print text to console"

  @impl Urza.Tool
  def run(%{"content" => content}) do
   IO.puts("Echo: #{content}")
   {:ok,content}
  end

  @impl Urza.Tool
  def run(_),do: {:ok,"failed to run invalid inputs"}

  @impl Urza.Tool
  def parameter_schema() do
    [type: :string,required: true]
  end

  @impl Urza.Tool
  def return_schema() do
    [type: :string,required: true]
  end

end
