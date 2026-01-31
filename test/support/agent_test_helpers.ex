defmodule Urza.Test.AgentTestHelpers do
  @moduledoc """
  Helpers for running AI agent scenarios in tests.
  """

  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  import ExUnit.Assertions
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

  def run_scenario(scenario) do
    agent_id = "test_agent_#{scenario.name}_#{System.unique_integer()}"
    goal = scenario.goal

    Phoenix.PubSub.subscribe(Urza.PubSub, "agent:#{agent_id}:logs")

    {first_tool, first_args, _first_response} = List.first(scenario.tool_sequence)

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      assert length(messages) == 2
      [system_msg, user_msg] = messages

      system_content = extract_message_content(system_msg)
      user_content = extract_message_content(user_msg)
      assert String.contains?(user_content, goal)

      {:ok,
       mock_llm_response(~s({"tool": "#{first_tool}", "args": #{Jason.encode!(first_args)}}))}
    end)

    scenario.tool_sequence
    |> Enum.drop(1)
    |> Enum.with_index(1)
    |> Enum.each(fn {{tool, args, _response}, index} ->
      expect(LLMAdapterMock, :generate_text, fn @model, messages ->
        expected_history_length = 2 + index * 2
        assert length(messages) == expected_history_length

        previous_tools = Enum.take(scenario.tool_sequence, index)

        Enum.each(previous_tools, fn {prev_tool, _, _} ->
          assert Enum.any?(messages, fn msg ->
                   content = extract_message_content(msg)
                   String.contains?(content, "executing #{prev_tool}")
                 end)
        end)

        {:ok, mock_llm_response(~s({"tool": "#{tool}", "args": #{Jason.encode!(args)}}))}
      end)
    end)

    expect(LLMAdapterMock, :generate_text, fn @model, messages ->
      expected_final_length = 2 + length(scenario.tool_sequence) * 2
      assert length(messages) == expected_final_length

      Enum.each(scenario.tool_sequence, fn {tool, _, _} ->
        assert Enum.any?(messages, fn msg ->
                 content = extract_message_content(msg)
                 String.contains?(content, "executing #{tool}")
               end)
      end)

      {:ok, mock_llm_response(Jason.encode!(scenario.expected_result))}
    end)

    {:ok, pid} =
      Urza.AI.Agent.start_link(
        id: agent_id,
        ref: "test_ref_#{agent_id}",
        goal: goal,
        available_tools: scenario.tools
      )

    Ecto.Adapters.SQL.Sandbox.allow(Urza.Repo, self(), pid)
    Process.monitor(pid)

    Enum.each(scenario.tool_sequence, fn {tool_name, args, response} ->
      assert_receive {:ai_thinking, ^agent_id}
      assert_receive {:tool_started, ^agent_id, ^tool_name, ^args}

      worker_module =
        case tool_name do
          "echo" -> "Urza.Tools.Echo"
          "calculator" -> "Urza.Tools.Calculator"
          "wait" -> "Urza.Tools.Wait"
          _ -> "Urza.Tools.#{Macro.camelize(tool_name)}"
        end

      assert_enqueued([worker: worker_module, args: args], 100)

      Urza.AI.Agent.send_tool_result(agent_id, response)

      assert_receive {:tool_completed, ^agent_id, ^response}
    end)

    assert_receive {:ai_thinking, ^agent_id}
    assert_receive {:agent_completed, ^agent_id, result}

    assert result["answer"] == scenario.expected_result["answer"]
    assert result["confidence"] == scenario.expected_result["confidence"]

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000

    enqueued_workers = all_enqueued() |> Enum.map(& &1.worker) |> Enum.sort()

    expected_workers =
      scenario.tool_sequence
      |> Enum.map(fn {tool, _, _} ->
        case tool do
          "echo" -> "Urza.Tools.Echo"
          "calculator" -> "Urza.Tools.Calculator"
          "wait" -> "Urza.Tools.Wait"
          _ -> "Urza.Tools.#{Macro.camelize(tool)}"
        end
      end)
      |> Enum.sort()

    assert enqueued_workers == expected_workers
  end

  def run_error_scenario(scenario) do
    agent_id = "error_agent_#{scenario.name}_#{System.unique_integer()}"
    goal = scenario.goal

    Phoenix.PubSub.subscribe(Urza.PubSub, "agent:#{agent_id}:logs")

    Enum.each(scenario.ai_responses, fn ai_response ->
      expect(LLMAdapterMock, :generate_text, fn @model, messages ->
        assert length(messages) == 2
        [system_msg, user_msg] = messages

        user_content = extract_message_content(user_msg)
        assert String.contains?(user_content, goal)

        {:ok, mock_llm_response(ai_response)}
      end)
    end)

    {:ok, pid} =
      Urza.AI.Agent.start_link(
        id: agent_id,
        ref: "test_ref_#{agent_id}",
        goal: goal,
        available_tools: scenario.tools || ["echo"]
      )

    Ecto.Adapters.SQL.Sandbox.allow(Urza.Repo, self(), pid)
    Process.flag(:trap_exit, true)

    assert_receive {:ai_thinking, ^agent_id}, 2000

    case scenario.name do
      "malformed_json_response" <> _ ->
        assert_receive {:error, ^agent_id, error_message}
        assert String.contains?(error_message, "Failed to parse AI response")

      "empty_json_response" <> _ ->
        assert_receive {:error, ^agent_id, error_message}
        assert String.contains?(error_message, "Failed to parse AI response")

      "non_json_response" <> _ ->
        assert_receive {:error, ^agent_id, error_message}
        assert String.contains?(error_message, "Failed to parse AI response")

      "invalid_tool_call_missing_args" <> _ ->
        assert_receive {:error, ^agent_id, error_message}
        assert String.contains?(error_message, "Invalid AI response format")

      "tool_call_with_invalid_args" <> _ ->
        assert_receive {:error, ^agent_id, error_message}
        assert String.contains?(error_message, "Invalid tool args")

      "agent_reports_error" <> _ ->
        assert_receive {:agent_error, ^agent_id, error_message}
        assert String.contains?(error_message, scenario.expected_error)

      _ ->
        assert_receive {:error, ^agent_id, _error_message}
    end

    refute_receive {:tool_completed, _, _}, 100
    refute_receive {:agent_completed, _, _}, 100

    :timer.sleep(100)
    refute Process.alive?(pid)
  end
end
