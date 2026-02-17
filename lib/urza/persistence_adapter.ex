defmodule Urza.PersistenceAdapter do
  @moduledoc """
  Adapter module for persistence operations that provides a consistent interface
  and allows for different storage backends via configuration.
  """

  @callback create_thread(state :: map()) :: {:ok, String.t()} | {:error, String.t()}
  @callback get_thread(thread_id :: String.t()) :: map() | nil
  @callback persist_state(thread_id :: String.t(), state :: map()) :: :ok
  @callback persist_error(thread_id :: String.t(), reason :: String.t()) :: :ok
  @callback persist_result(thread_id :: String.t(), result :: map()) :: :ok
  @callback get_result(thread_id :: String.t()) :: map() | nil

  # TODO: Add load_state/1 callback to restore agent state from persistence
  # This would enable agents to resume from saved state, useful for:
  # - Recovering from crashes
  # - Long-running conversations
  # - Scaling agent instances
  # def load_state(thread_id), do: impl().load_state(thread_id)

  def create_thread(state) do
    impl().create_thread(state)
  end

  def get_thread(thread_id) do
    impl().get_thread(thread_id)
  end

  def persist_state(thread_id, state) do
    impl().persist_state(thread_id, state)
  end

  def persist_error(thread_id, reason) do
    impl().persist_error(thread_id, reason)
  end

  def persist_result(thread_id, result) do
    impl().persist_result(thread_id, result)
  end

  def get_result(thread_id) do
    impl().get_result(thread_id)
  end

  defp impl do
    Application.get_env(:urza, :persistence_adapter)
  end
end
