defmodule Urza.Workflow do
  alias Urza.Tools.Calculator
  alias Urza.Tools.Echo
  alias Oban.Job
  alias Phoenix.PubSub
  alias Urza.Tools.Context
  use GenServer


  def start_link(opts) do
    GenServer.start_link(__MODULE__,opts)
  end

  #id is string
  @impl GenServer
  def init(%{id: id} = ctx) do
    PubSub.subscribe(Urza.PubSub,id)
    send(self(),:start)
    {:ok,ctx}
  end

  @impl GenServer
  def handle_info(:start,ctx) do
    ctx = queue_job(ctx)   
    {:noreply,ctx}
  end

  @impl GenServer
  def handle_info({job_id,ret},ctx = %Context{executing_job: job_id,acc: acc,work: []}) do
    acc = Map.merge(ret,acc)
    IO.inspect(acc)
    ctx = %{ctx|acc: acc}
    IO.inspect("completed execution !!!")
    {:noreply,ctx}
  end

  @impl GenServer
  def handle_info({job_id,ret},ctx = %Context{executing_job: job_id,acc: acc,work: [_hd|_tl]}) do
    acc = Map.merge(ret,acc)
    IO.inspect(acc)
    ctx = %{ctx|acc: acc}
    ctx = queue_job(ctx)
    {:noreply,ctx}
  end


  defp decode_args(args,acc) when is_map(args) do
    args
    |> Map.to_list()
    |> Enum.map(fn 
        {k,{:const,v}} -> {k,v} 
        {k,{:dyn,ref}} -> {k,acc[ref]} 
        end)
    |> Map.new()
  end

  def queue_job(%Context{id: id,work: [{tool,args,ref}|tl],acc: acc} = ctx) do

    meta = %{workflow_id: id,ref: ref}
    deref_args = decode_args(args,acc)  


    {:ok,%Job{id: job_id}} = 
    tool.new(deref_args,meta: meta)
    |> Oban.insert() 

    ctx = %{ctx|work: tl}
    %{ctx|executing_job: job_id}
  end

  @moduledoc """
  handle loops 
  hanlde branches
  handle ai agent
  handle human in loop


   TODO next steps to handle concurrent work
  """

  def test() do
    %Context{
      id: "122",
      work: [
        {Echo,%{"content" => {:const,"Hello world"}},nil},
        {Calculator,%{"l" => {:const,1},"r" => {:const,2},"op" => {:const,"add"}},"$1"},
        {Calculator,%{"l" => {:const,8},"r" => {:const,8},"op" => {:const,"multiply"}},"$2"},
        {Calculator,%{"l" => {:dyn,"$1"},"r" => {:dyn,"$2"},"op" => {:const,"multiply"}},"$3"},
      ]
    }
  end


end
