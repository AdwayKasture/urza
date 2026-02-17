defmodule Urza.NotificationAdapter do
  @moduledoc """
  Adapter module for notifications that provides a consistent interface
  and allows for different notification backends via configuration.
  """

  @callback notify(agent_id :: String.t(), event :: tuple()) :: any()

  def notify(agent_name, event) do
    case impl() do
      nil -> :ok
      adapter -> adapter.notify(agent_name, event)
    end
  end

  defp impl do
    Application.get_env(:urza, :notification_adapter)
  end
end
