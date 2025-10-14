defmodule Urza.Orchestrator do
  use GenServer,restart: :transient


  def start_link(%{workflow_id: workflow_id} = opts) do
    GenServer.start_link(__MODULE__,opts,name: via_tuple(workflow_id))
  end

  defp via_tuple(id),do: {:via,Registry,{Urza.AgentRegistry,id}}
    
  @impl GenServer
  def init(%{user_id: _user_id,}) do
    {:ok,:ok}   
  end
  
end
