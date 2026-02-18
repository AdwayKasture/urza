defmodule Urza.NotificationAdapter do
  @moduledoc """
  Adapter module for agent lifecycle notifications.
  Third-party implementations should define these callbacks.
  """

  @callback agent_started(agent_name :: String.t(), thread_id :: term()) :: any()
  @callback tool_started(agent_name :: String.t(), tool_name :: String.t(), args :: map()) ::
              any()
  @callback tool_completed(agent_name :: String.t(), result :: term()) :: any()
  @callback agent_completed(agent_name :: String.t(), result :: map()) :: any()
  @callback error(agent_name :: String.t(), error :: term()) :: any()
  @callback terminated(agent_name :: String.t(), reason :: term()) :: any()

  def agent_started(agent_name, thread_id) do
    case impl() do
      nil -> :ok
      adapter -> adapter.agent_started(agent_name, thread_id)
    end
  end

  def tool_started(agent_name, tool_name, args) do
    case impl() do
      nil -> :ok
      adapter -> adapter.tool_started(agent_name, tool_name, args)
    end
  end

  def tool_completed(agent_name, result) do
    case impl() do
      nil -> :ok
      adapter -> adapter.tool_completed(agent_name, result)
    end
  end

  def agent_completed(agent_name, result) do
    case impl() do
      nil -> :ok
      adapter -> adapter.agent_completed(agent_name, result)
    end
  end

  def error(agent_name, error) do
    case impl() do
      nil -> :ok
      adapter -> adapter.error(agent_name, error)
    end
  end

  def terminated(agent_name, reason) do
    case impl() do
      nil -> :ok
      adapter -> adapter.terminated(agent_name, reason)
    end
  end

  defp impl do
    Application.get_env(:urza, :notification_adapter)
  end
end
