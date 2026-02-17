defmodule Urza.Persistence.ETS do
  @moduledoc """
  In-memory persistence adapter using ETS for storage.
  """

  @behaviour Urza.PersistenceAdapter

  @threads_table :urza_threads
  @messages_table :urza_messages

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def init([]) do
    {:ok, nil}
  end

  def start_link(_opts \\ []) do
    :ets.new(@threads_table, [:set, :named_table, :public, {:read_concurrency, true}])
    :ets.new(@messages_table, [:set, :named_table, :public, {:read_concurrency, true}])

    case :ets.lookup(@threads_table, "thread_counter") do
      [] -> :ets.insert(@threads_table, {"thread_counter", 0})
      _ -> :ok
    end

    {:ok, self()}
  end

  @impl Urza.PersistenceAdapter
  def create_thread(state) do
    thread_id = next_thread_id()

    thread_data = %{
      id: thread_id,
      name: state.name,
      input: state.input,
      status: "running",
      result: nil,
      error_message: nil,
      seq: 0,
      history: [],
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    :ets.insert(@threads_table, {thread_id, thread_data})
    {:ok, thread_id}
  end

  @impl Urza.PersistenceAdapter
  def get_thread(thread_id) do
    case :ets.lookup(@threads_table, thread_id) do
      [{^thread_id, data}] -> data
      [] -> nil
    end
  end

  @impl Urza.PersistenceAdapter
  def persist_state(thread_id, state) do
    thread_data = %{
      id: thread_id,
      name: state.name,
      input: state.input,
      status: state.status || "running",
      result: state.result,
      error_message: state.error_message,
      seq: state.seq,
      history: state.history,
      updated_at: DateTime.utc_now()
    }

    :ets.insert(@threads_table, {thread_id, thread_data})
    :ok
  end

  @impl Urza.PersistenceAdapter
  def persist_error(thread_id, reason) do
    case :ets.lookup(@threads_table, thread_id) do
      [{^thread_id, data}] ->
        updated_data =
          Map.merge(data, %{
            status: "error",
            error_message: reason,
            updated_at: DateTime.utc_now()
          })

        :ets.insert(@threads_table, {thread_id, updated_data})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Urza.PersistenceAdapter
  def persist_result(thread_id, result) do
    case :ets.lookup(@threads_table, thread_id) do
      [{^thread_id, data}] ->
        updated_data =
          Map.merge(data, %{
            status: "completed",
            result: result,
            updated_at: DateTime.utc_now()
          })

        :ets.insert(@threads_table, {thread_id, updated_data})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Urza.PersistenceAdapter
  def get_result(thread_id) do
    case :ets.lookup(@threads_table, thread_id) do
      [{^thread_id, data}] ->
        Map.get(data, :result)

      [] ->
        nil
    end
  end

  defp next_thread_id do
    :ets.update_counter(@threads_table, "thread_counter", 1)
    |> Integer.to_string()
  end
end
