defmodule Urza.Persistence.ETSTest do
  use ExUnit.Case, async: false

  alias Urza.Persistence.ETS

  setup do
    Application.put_env(:urza, :notification_receiver_pid, self())
    :ets.delete_all_objects(:urza_threads)
    :ets.delete_all_objects(:urza_messages)
    :ets.insert(:urza_threads, {"thread_counter", 0})

    {:ok, pid} = GenServer.start_link(ETS, [], name: ETS)

    on_exit(fn ->
      Application.delete_env(:urza, :notification_receiver_pid)
    end)

    %{pid: pid}
  end

  describe "create_thread/1" do
    test "creates a thread and returns ID", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello world",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      assert {:ok, thread_id} = ETS.create_thread(state)
      assert is_binary(thread_id)
      assert thread_id == "1"
    end
  end

  describe "get_thread/1" do
    test "returns thread data when exists", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello world",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      {:ok, thread_id} = ETS.create_thread(state)

      thread = ETS.get_thread(thread_id)

      assert thread.id == thread_id
      assert thread.name == "test_agent"
      assert thread.input == "hello world"
      assert thread.status == "running"
    end

    test "returns nil when thread does not exist", %{pid: _pid} do
      assert ETS.get_thread("999999") == nil
    end
  end

  describe "persist_state/2" do
    test "updates thread state", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello world",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      {:ok, thread_id} = ETS.create_thread(state)

      new_state = %{
        name: "test_agent",
        input: "hello world",
        status: "running",
        seq: 1,
        history: [%{role: "user", content: "test"}],
        result: nil,
        error_message: nil
      }

      assert :ok = ETS.persist_state(thread_id, new_state)

      thread = ETS.get_thread(thread_id)
      assert thread.seq == 1
      assert length(thread.history) == 1
    end

    test "updates status", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      {:ok, thread_id} = ETS.create_thread(state)

      new_state = %{
        name: "test_agent",
        input: "hello",
        status: "completed",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      :ok = ETS.persist_state(thread_id, new_state)

      thread = ETS.get_thread(thread_id)
      assert thread.status == "completed"
    end
  end

  describe "persist_error/2" do
    test "sets thread status to error with message", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      {:ok, thread_id} = ETS.create_thread(state)

      assert :ok = ETS.persist_error(thread_id, "Something went wrong")

      thread = ETS.get_thread(thread_id)
      assert thread.status == "error"
      assert thread.error_message == "Something went wrong"
    end

    test "returns error for non-existent thread", %{pid: _pid} do
      assert {:error, :not_found} = ETS.persist_error("999999", "error message")
    end
  end

  describe "persist_result/2" do
    test "sets thread status to completed with result", %{pid: _pid} do
      state = %{
        name: "test_agent",
        input: "hello",
        status: "running",
        seq: 0,
        history: [],
        result: nil,
        error_message: nil
      }

      {:ok, thread_id} = ETS.create_thread(state)

      result = %{"result" => "task completed", "details" => "success"}
      assert :ok = ETS.persist_result(thread_id, result)

      thread = ETS.get_thread(thread_id)
      assert thread.status == "completed"
      assert thread.result == result
    end

    test "returns error for non-existent thread", %{pid: _pid} do
      assert {:error, :not_found} = ETS.persist_result("999999", %{})
    end
  end

  describe "thread counter" do
    test "generates unique thread IDs", %{pid: _pid} do
      {:ok, id1} =
        ETS.create_thread(%{
          name: "a",
          input: "a",
          status: "running",
          seq: 0,
          history: [],
          result: nil,
          error_message: nil
        })

      {:ok, id2} =
        ETS.create_thread(%{
          name: "b",
          input: "b",
          status: "running",
          seq: 0,
          history: [],
          result: nil,
          error_message: nil
        })

      {:ok, id3} =
        ETS.create_thread(%{
          name: "c",
          input: "c",
          status: "running",
          seq: 0,
          history: [],
          result: nil,
          error_message: nil
        })

      assert id1 == "1"
      assert id2 == "2"
      assert id3 == "3"
    end
  end
end
