defmodule Urza.AI.AgentTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  alias Urza.AI.Agent

  import Mox
  import Urza.Test.Fixtures
  alias Urza.AI.LLMAdapterMock

  @model "google:gemini-2.5-flash"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  test "tool_call -> tool_call -> final result with proper events and jobs" do
    agent_id = "test_agent_#{System.unique_integer()}"
    goal = "Calculate the sum of 33 and 27, then multiply by 2"

    Phoenix.PubSub.subscribe(Urza.PubSub, "agent:#{agent_id}:logs")

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 2
      [system_msg, user_msg] = messages

      user_content = extract_message_content(user_msg)
      assert String.contains?(user_content, goal)

      system_content = extract_message_content(system_msg)
      assert String.contains?(system_content, "calculator")

      {:ok,
       mock_llm_response(~s({"tool": "calculator", "args": {"l": 33, "r": 27, "op": "add"}}))}
    end)

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 4

      assert Enum.any?(messages, fn msg ->
               content = extract_message_content(msg)
               String.contains?(content, "executing calculator")
             end)

      {:ok,
       mock_llm_response(~s({"tool": "calculator", "args": {"l": 60, "r": 2, "op": "multiply"}}))}
    end)

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 6

      assert Enum.any?(messages, fn msg ->
               content = extract_message_content(msg)
               String.contains?(content, "executing calculator")
             end)

      {:ok, mock_llm_response(~s({"answer": "The final result is 120", "confidence": 9}))}
    end)

    {:ok, pid} =
      Agent.start_link(
        id: agent_id,
        ref: "test_ref_#{agent_id}",
        goal: goal,
        available_tools: ["calculator"]
      )

    Ecto.Adapters.SQL.Sandbox.allow(Urza.Repo, self(), pid)

    assert_receive {:ai_thinking, ^agent_id}

    assert_receive {:tool_started, ^agent_id, "calculator",
                    %{"l" => 33, "r" => 27, "op" => "add"}}

    assert_enqueued(
      [
        worker: "Urza.Tools.Calculator",
        args: %{"l" => 33, "r" => 27, "op" => "add"}
      ],
      100
    )

    Agent.send_tool_result(agent_id, "60")

    assert_receive {:tool_completed, ^agent_id, "60"}

    assert_receive {:ai_thinking, ^agent_id}

    assert_enqueued(
      [
        worker: "Urza.Tools.Calculator",
        args: %{"l" => 60, "r" => 2, "op" => "multiply"}
      ],
      100
    )

    assert_receive {:tool_started, ^agent_id, "calculator",
                    %{"l" => 60, "r" => 2, "op" => "multiply"}}

    Agent.send_tool_result(agent_id, "120")

    assert_receive {:tool_completed, ^agent_id, "120"}

    assert_receive {:ai_thinking, ^agent_id}

    assert_receive {:agent_completed, ^agent_id, result}

    assert result["answer"] == "The final result is 120"
    assert result["confidence"] == 9

    refute_receive _, 100

    assert [
             %{worker: "Urza.Tools.Calculator"},
             %{worker: "Urza.Tools.Calculator"}
           ] = all_enqueued()
  end

  test "agent reports error when it cannot complete the task" do
    agent_id = "test_agent_error_#{System.unique_integer()}"
    goal = "Access a restricted resource"

    Phoenix.PubSub.subscribe(Urza.PubSub, "agent:#{agent_id}:logs")

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 2
      {:ok, mock_llm_response(~s({"error": "unable to do task due to access restrictions"}))}
    end)

    Process.flag(:trap_exit, true)

    {:ok, pid} =
      Agent.start_link(
        id: agent_id,
        ref: "test_ref_#{agent_id}",
        goal: goal,
        available_tools: ["echo"]
      )

    Ecto.Adapters.SQL.Sandbox.allow(Urza.Repo, self(), pid)

    assert_receive {:ai_thinking, ^agent_id}

    assert_receive {:agent_error, ^agent_id, "unable to do task due to access restrictions"}

    refute_receive {:tool_started, _, _, _}, 100
    refute_receive {:agent_completed, _, _}, 100

    :timer.sleep(100)
    refute Process.alive?(pid)
  end
end
