defmodule Urza.Test.ScenarioHelpers do
  @moduledoc """
  Helpers for running AI agent scenarios in tests.
  """

  import ExUnit.Assertions
  import Mox
  import Urza.Test.Fixtures
  alias Urza.AI.LLMAdapterMock

  @default_model "google:gemini-2.5-flash"

  @doc """
  Runs a scenario that tests the full agent lifecycle with a sequence of tool calls
  followed by a completion.

  ## Scenario structure:
  - name: unique identifier for the test
  - input: the input to the agent
  - goal: the system prompt/goal for the agent
  - model: the LLM model to use (optional, defaults to #{@default_model})
  - tool_sequence: list of {tool_name, args, mock_response} tuples
  - expected_completion: the expected completion result
  """
  def run_scenario(scenario) do
    agent_name = "test_agent_#{scenario.name}_#{System.unique_integer()}"
    input = scenario.input
    goal = scenario[:goal] || "You are a helpful AI assistant."
    model = scenario[:model] || @default_model
    expected_completion = scenario.expected_completion

    # Build mock expectations for LLM calls
    # First call: return first tool
    {first_tool, first_args, _first_response} = List.first(scenario.tool_sequence)

    expect(LLMAdapterMock, :generate_text, fn ^model, messages ->
      assert length(messages) == 2
      [system_msg, user_msg] = messages

      system_content = extract_message_content(system_msg)
      user_content = extract_message_content(user_msg)

      assert String.contains?(system_content, first_tool)

      assert String.contains?(user_content, input)

      {:ok,
       mock_llm_response(~s({"tool": "#{first_tool}", "args": #{Jason.encode!(first_args)}}))}
    end)

    # Mock subsequent tool calls (one per tool in sequence after the first)
    # After each tool result, the LLM is called again
    tool_sequence = tl(scenario.tool_sequence)

    Enum.each(tool_sequence, fn {tool_name, args, _response} ->
      expect(LLMAdapterMock, :generate_text, fn ^model, _messages ->
        {:ok, mock_llm_response(~s({"tool": "#{tool_name}", "args": #{Jason.encode!(args)}}))}
      end)
    end)

    # Final call: return completion
    expect(LLMAdapterMock, :generate_text, fn ^model, _messages ->
      {:ok, mock_llm_response(~s({"completion": #{Jason.encode!(expected_completion)}}))}
    end)

    # Start agent
    {:ok, pid} =
      Urza.AI.Agent.start_link(
        name: agent_name,
        input: input,
        goal: goal,
        model: model,
        tools: scenario[:tools] || ["web", "calculator"]
      )

    Process.monitor(pid)

    # Process tool sequence
    Enum.each(scenario.tool_sequence, fn {_tool_name, _args, response} ->
      Urza.AI.Agent.send_tool_result(agent_name, response)
    end)

    # Wait for agent to complete - use notification to get thread_id BEFORE agent terminates
    assert_receive {^agent_name, _thread_id,
                    {:agent_completed, ^agent_name, %{"completion" => result}}},
                   1000

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000

    IO.inspect(result)
    result
  end

  @doc """
  Runs an error scenario that tests error handling.
  """
  def run_error_scenario(scenario) do
    agent_name = "error_agent_#{scenario.name}_#{System.unique_integer()}"
    input = scenario.input
    goal = scenario[:goal] || "You are a helpful AI assistant."
    model = scenario[:model] || @default_model

    # Build mock expectations for LLM calls
    Enum.each(scenario.ai_responses, fn ai_response ->
      expect(LLMAdapterMock, :generate_text, fn ^model, messages ->
        assert length(messages) == 2
        [system_msg, user_msg] = messages

        system_content = extract_message_content(system_msg)
        user_content = extract_message_content(user_msg)

        assert String.contains?(system_content, "web") or
                 String.contains?(system_content, "calculator")

        assert String.contains?(user_content, input)

        {:ok, mock_llm_response(ai_response)}
      end)
    end)

    # Start agent
    {:ok, pid} =
      Urza.AI.Agent.start_link(
        name: agent_name,
        input: input,
        goal: goal,
        model: model,
        tools: scenario[:tools] || ["web", "calculator"]
      )

    Process.flag(:trap_exit, true)

    # Wait for agent to terminate
    :timer.sleep(200)

    # Verify process has terminated
    refute Process.alive?(pid)
  end
end
