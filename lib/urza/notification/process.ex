defmodule Urza.Notification.Process do
  @moduledoc """
  An implementation of Urza.NotificationAdapter that sends notifications
  directly to a configured process PID.
  To be used with assert_recieve in tests
  """
  @behaviour Urza.NotificationAdapter

  defp receiver_pid, do: Application.get_env(:urza, :notification_receiver_pid)

  @impl Urza.NotificationAdapter
  def agent_started(agent_name, thread_id) do
    send(receiver_pid(), {agent_name, thread_id, :agent_started})
    :ok
  end

  @impl Urza.NotificationAdapter
  def tool_started(agent_name, tool_name, args) do
    send(receiver_pid(), {agent_name, nil, {:tool_started, tool_name, args}})
    :ok
  end

  @impl Urza.NotificationAdapter
  def tool_completed(agent_name, result) do
    send(receiver_pid(), {agent_name, nil, {:tool_completed, result}})
    :ok
  end

  @impl Urza.NotificationAdapter
  def agent_completed(agent_name, result) do
    send(receiver_pid(), {agent_name, nil, {:agent_completed, result}})
    :ok
  end

  @impl Urza.NotificationAdapter
  def error(agent_name, error) do
    send(receiver_pid(), {agent_name, nil, {:error, error}})
    :ok
  end

  @impl Urza.NotificationAdapter
  def terminated(agent_name, reason) do
    send(receiver_pid(), {agent_name, nil, {:terminated, reason}})
    :ok
  end
end
