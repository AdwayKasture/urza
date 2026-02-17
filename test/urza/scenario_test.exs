defmodule Urza.ScenarioTest do
  use ExUnit.Case, async: false

  import Mox
  import Urza.Test.ScenarioHelpers

  setup :set_mox_from_context
  setup :verify_on_exit!

  @moduletag :scenario

  setup do
    Application.put_env(:urza, :notification_receiver_pid, self())

    on_exit(fn ->
      Application.delete_env(:urza, :notification_receiver_pid)
    end)

    :ok
  end


  @tag :ak
  test "calculator scenario: multiple operations" do
    completion =
      run_scenario(%{
        name: "multiple_calculations",
        input: "Calculate 10 + 5, then multiply the result by 2",
        goal: "You are a math assistant. Use the calculator tool to perform calculations.",
        tool_sequence: [
          {"calculator", %{"op" => "add", "a" => 10, "b" => 5}, "15"},
          {"calculator", %{"op" => "multiply", "a" => 15, "b" => 2}, "30"}
        ],
        expected_completion: %{
          "result" => "30",
          "explanation" => "10 + 5 = 15, then 15 * 2 = 30"
        }
      })
    IO.inspect(completion)

    assert completion["result"] == "30"
  end

  test "web and calculator combined scenario" do
    completion =
      run_scenario(%{
        name: "web_then_calculate",
        input: "website: google",
        goal: "Fetch data from a website and perform calculations on it",
        tool_sequence: [
          {"web", %{"url" => "https://example.com/data"},
           "{\"value\": 100, \"multiplier\": 1.5}"},
          {"calculator", %{"op" => "multiply", "a" => 100, "b" => 1.5}, "150.0"}
        ],
        expected_completion: %{
          "result" => "150.0",
          "source" => "https://example.com/data"
        }
      })

    assert completion["result"] == "150.0"
  end
end
