defmodule Urza.AI.ScenarioTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  import Mox
  import Urza.Test.AgentTestHelpers

  @scenarios [
    %{
      name: "math_calculation_sequence",
      goal: "Calculate (10 + 20) * 3",
      tools: ["calculator"],
      tool_sequence: [
        {"calculator", %{"l" => 10, "r" => 20, "op" => "add"}, "30"},
        {"calculator", %{"l" => 30, "r" => 3, "op" => "multiply"}, "90"}
      ],
      expected_result: %{
        "answer" => "The final result is 90",
        "confidence" => 10
      }
    },
    %{
      name: "multi_step_with_echo",
      goal: "Add 5 and 3, then echo the result three times",
      tools: ["calculator", "echo"],
      tool_sequence: [
        {"calculator", %{"l" => 5, "r" => 3, "op" => "add"}, "8"},
        {"echo", %{"content" => "8"}, "8"},
        {"echo", %{"content" => "8"}, "8"}
      ],
      expected_result: %{
        "answer" => "Successfully calculated and echoed 8 three times",
        "confidence" => 9
      }
    },
    %{
      name: "single_tool_completion",
      goal: "Add 100 and 200",
      tools: ["calculator"],
      tool_sequence: [
        {"calculator", %{"l" => 100, "r" => 200, "op" => "add"}, "300"}
      ],
      expected_result: %{
        "answer" => "300",
        "confidence" => 10
      }
    }
  ]

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  for scenario <- @scenarios do
    test "scenario: #{scenario.name}" do
      run_scenario(unquote(Macro.escape(scenario)))
    end
  end
end
