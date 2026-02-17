defmodule Urza.WorkflowSupervisor do
  @moduledoc """
  DynamicSupervisor for managing workflow processes.
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
  Starts a new workflow under supervision.

  ## Parameters

  * `id` - Unique identifier for the workflow
  * `work` - List of work items defining the DAG
  * `initial_acc` - Optional initial accumulator (default: %{})
  """
  def start_workflow(id, work, initial_acc \\ %{}) do
    spec = {Urza.Workflow, [id: id, work: work, acc: initial_acc]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a workflow by its PID.
  """
  def stop_workflow(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Lists all running workflow processes.
  """
  def list_workflows do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
