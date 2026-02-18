defmodule Urza.Notification.IO do
  @moduledoc """
  IO-based notification adapter that prints events to stdout.
  """

  @behaviour Urza.NotificationAdapter

  @impl true
  def agent_started(agent_name, thread_id) do
    IO.puts("[#{agent_name}] Agent started (thread: #{inspect(thread_id)})")
  end

  @impl true
  def tool_started(agent_name, tool_name, args) do
    IO.puts("[#{agent_name}] Tool started: #{tool_name} with args: #{inspect(args)}")
  end

  @impl true
  def tool_completed(agent_name, result) do
    IO.puts("[#{agent_name}] Tool completed with result: #{inspect(result)}")
  end

  @impl true
  def agent_completed(agent_name, result) do
    IO.puts("[#{agent_name}] Agent completed with result: #{inspect(result)}")
  end

  @impl true
  def error(agent_name, error) do
    IO.puts("[#{agent_name}] Error: #{inspect(error)}")
  end

  @impl true
  def terminated(agent_name, reason) do
    IO.puts("[#{agent_name}] Terminated: #{inspect(reason)}")
  end
end
