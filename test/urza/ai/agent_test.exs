defmodule Urza.AI.AgentTest do
  use ExUnit.Case, async: false

  alias Urza.AI.Agent

  import Mox
  import Urza.Test.Fixtures
  alias Urza.AI.LLMAdapterMock

  @model "google:gemini-2.5-flash"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Application.put_env(:urza, :notification_receiver_pid, self())

    on_exit(fn ->
      Application.delete_env(:urza, :notification_receiver_pid)
    end)

    :ok
  end

  test "agent completes task with calculator tool" do
    agent_name = "test_calculator_#{System.unique_integer()}"
    goal = "Calculate 5 + 3"

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 2
      [system_msg, user_msg] = messages

      system_content = extract_message_content(system_msg)
      _user_content = extract_message_content(user_msg)

      assert String.contains?(system_content, "calculator")
      assert String.contains?(system_content, goal)

      {:ok, mock_llm_response(~s({"tool": "calculator", "args": {"op": "add", "a": 5, "b": 3}}))}
    end)

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 4

      assert Enum.any?(messages, fn msg ->
               content = extract_message_content(msg)
               String.contains?(content, "executing calculator")
             end)

      {:ok, mock_llm_response(~s({"completion": {"result": "8"}}))}
    end)

    {:ok, pid} =
      Agent.start_link(
        name: agent_name,
        goal: goal,
        tools: ["calculator"]
      )

    Process.monitor(pid)

    assert_receive {^agent_name, _, :agent_started}, 1000
    assert_receive {^agent_name, _, {:tool_started, "calculator", _}}, 1000

    Agent.send_tool_result(agent_name, "8")

    assert_receive {^agent_name, _, {:tool_completed, "8"}}

    assert_receive {^agent_name, _, {:agent_completed, %{"completion" => completion}}}

    assert completion["result"] == "8"

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000
  end

  test "agent uses web tool to fetch data" do
    agent_name = "test_web_#{System.unique_integer()}"
    goal = "Get information if this is a good website"
    input = "https://example.com"

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      [system_msg, user_msg] = messages

      system_content = extract_message_content(system_msg)
      user_content = extract_message_content(user_msg)

      assert String.contains?(system_content, "web")
      assert String.contains?(system_content, goal)
      assert String.contains?(user_content, input)

      {:ok, mock_llm_response(~s({"tool": "web", "args": {"url": "https://example.com"}}))}
    end)

    expect(LLMAdapterMock, :generate_text, fn @model, _messages ->
      {:ok,
       mock_llm_response(
         ~s({"completion": {"result": "Example Domain", "content": "This domain is for use in illustrative examples..."}})
       )}
    end)

    {:ok, pid} =
      Agent.start_link(
        name: agent_name,
        goal: goal,
        input: input,
        tools: ["web"]
      )

    Process.monitor(pid)

    assert_receive {^agent_name, _, :agent_started}, 1000
    assert_receive {^agent_name, _, {:tool_started, "web", _}}, 1000

    Agent.send_tool_result(agent_name, "<html><body>Example Domain</body></html>")

    assert_receive {^agent_name, _, {:tool_completed, _}}

    assert_receive {^agent_name, _, {:agent_completed, _}}

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000
  end

  test "agent with custom goal and model" do
    agent_name = "test_custom_#{System.unique_integer()}"
    custom_model = "openai:gpt-4"
    custom_goal = "You are a math expert. Use the calculator tool."

    expect(LLMAdapterMock, :generate_text, fn ^custom_model, _messages ->
      {:ok,
       mock_llm_response(~s({"tool": "calculator", "args": {"op": "multiply", "a": 2, "b": 3}}))}
    end)

    expect(LLMAdapterMock, :generate_text, fn ^custom_model, _messages ->
      {:ok, mock_llm_response(~s({"completion": {"result": "6"}}))}
    end)

    {:ok, pid} =
      Agent.start_link(
        name: agent_name,
        input: "What is 2 times 3?",
        goal: custom_goal,
        model: custom_model,
        tools: ["calculator"]
      )

    Process.monitor(pid)

    Agent.send_tool_result(agent_name, "6")

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000
  end

  test "agent handles malformed JSON response" do
    agent_name = "test_malformed_#{System.unique_integer()}"

    expect(LLMAdapterMock, :generate_text, fn @model, _messages ->
      {:ok, mock_llm_response("This is not JSON")}
    end)

    {:ok, pid} =
      Agent.start_link(
        name: agent_name,
        input: "Test",
        tools: ["calculator"],
        goal: "add 300 and 400"
      )

    Process.flag(:trap_exit, true)

    :timer.sleep(200)
    refute Process.alive?(pid)
  end

  test "agent handles invalid tool args" do
    agent_name = "test_invalid_args_#{System.unique_integer()}"

    expect(LLMAdapterMock, :generate_text, fn @model, _messages ->
      {:ok, mock_llm_response(~s({"tool": "calculator", "args": "not a map"}))}
    end)

    {:ok, pid} =
      Agent.start_link(
        name: agent_name,
        input: "Test",
        goal: "Say hello world",
        tools: ["calculator"]
      )

    Process.flag(:trap_exit, true)

    :timer.sleep(200)
    refute Process.alive?(pid)
  end
end
