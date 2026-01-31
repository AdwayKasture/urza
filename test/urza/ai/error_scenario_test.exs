defmodule Urza.AI.ErrorScenarioTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  import Mox
  import Urza.Test.AgentTestHelpers

  @error_scenarios [
    %{
      name: "malformed_json_response",
      goal: "Test malformed JSON handling",
      tools: ["echo"],
      ai_responses: ["{invalid json"],
      expected_error: "Failed to parse AI response"
    },
    %{
      name: "empty_json_response",
      goal: "Test empty response handling",
      tools: ["echo"],
      ai_responses: [""],
      expected_error: "Failed to parse AI response"
    },
    %{
      name: "non_json_response",
      goal: "Test non-JSON response handling",
      tools: ["echo"],
      ai_responses: ["This is not JSON, just plain text"],
      expected_error: "Failed to parse AI response"
    },
    %{
      name: "invalid_tool_call_missing_args",
      goal: "Test missing args handling",
      tools: ["echo"],
      ai_responses: [~s({"tool": "echo"})],
      expected_error: "Invalid AI response format"
    },
    %{
      name: "tool_call_with_invalid_args",
      goal: "Test invalid args type handling",
      tools: ["echo"],
      ai_responses: [~s({"tool": "echo", "args": "not_an_object"})],
      expected_error: "Invalid tool args"
    },
    %{
      name: "agent_reports_error",
      goal: "Test when agent reports it cannot complete",
      tools: ["echo"],
      ai_responses: [~s({"error": "unable to do task due to insufficient permissions"})],
      expected_error: "unable to do task due to insufficient permissions"
    },
    %{
      name: "unknown_tool_call",
      goal: "Test unknown tool handling",
      tools: ["echo"],
      ai_responses: [~s({"tool": "unknown_tool", "args": {}})],
      expected_error: "Failed to queue tool job"
    }
  ]

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  for scenario <- @error_scenarios do
    test "error scenario: #{scenario.name}" do
      run_error_scenario(unquote(Macro.escape(scenario)))
    end
  end
end
