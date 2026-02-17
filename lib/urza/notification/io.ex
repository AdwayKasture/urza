defmodule Urza.Notification.IO do
  @moduledoc """
  IO-based notification adapter that prints events to stdout.
  """

  @behaviour Urza.NotificationAdapter

  @impl true
  def notify(agent_name, event) do
    IO.puts("[#{agent_name}] #{inspect(event)}")
  end
end
