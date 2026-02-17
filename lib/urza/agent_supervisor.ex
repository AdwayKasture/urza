defmodule Urza.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing agent processes.
  """
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new agent under supervision.
  """
  def start_agent(opts) do
    spec = {Urza.AI.Agent, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops an agent by its PID.
  """
  def stop_agent(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Lists all running agent processes.
  """
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
