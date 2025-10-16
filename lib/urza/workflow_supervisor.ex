defmodule Urza.WorkflowSupervisor do
  alias Urza.Workflow
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Client function to start a new Urza.Workflow
  def start_workflow(id, work, initial_acc \\ %{}) do
    child_spec = {Workflow, {id, work, initial_acc}}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
