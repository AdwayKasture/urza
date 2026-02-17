defmodule Urza.Notification.Process do
  @moduledoc """
  An implementation of Urza.NotificationAdapter that sends notifications
  directly to a configured process PID.
  To be used with assert_recieve in tests
  """
  @behaviour Urza.NotificationAdapter

  defp receiver_pid, do: Application.get_env(:urza, :notification_receiver_pid)

  @impl Urza.NotificationAdapter
  def notify(agent_id_or_state, event) do
    agent_name = extract_agent_name(agent_id_or_state)
    thread_id = extract_thread_id(agent_id_or_state)
    send(receiver_pid(), {agent_name, thread_id, event})
    :ok
  end

  defp extract_agent_name(%{name: name}), do: name
  defp extract_agent_name(name) when is_binary(name), do: name

  defp extract_thread_id(%{thread_id: thread_id}), do: thread_id
  defp extract_thread_id(_), do: nil
end
