defmodule Urza.Tools.AgentRunner do
  @behaviour Urza.Tool

  @impl Urza.Tool
  def name, do: "agent_runner"

  @impl Urza.Tool
  def description, do: "Runs an AI agent to achieve a goal using a set of tools."

  @impl Urza.Tool
  def parameter_schema(), do: []

  @impl Urza.Tool
  def return_schema(), do: []

  @impl Urza.Tool
  def run(_), do: {:ok, :ok}

  # This tool is not an Oban worker, so it doesn't implement `perform`.
  # It's a virtual tool handled by the Urza.Workflow GenServer.
end
