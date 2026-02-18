defmodule Urza.Demo do
  @moduledoc """
  Demo module for showcasing AI agent capabilities.
  """

  alias Urza.AgentSupervisor

  @doc """
  Creates and starts a math agent with the calculator tool.

  ## Examples

      Urza.Demo.math_agent()
      Urza.Demo.math_agent("calculate the sum of 1,2,3")

  """
  def math_agent(goal \\ "add 2, 3, 5, 7 then subtract 12") do
    name = generate_math_agent_name()
    Urza.Toolset.register_tool(Urza.Workers.Calculator)

    AgentSupervisor.start_agent(
      name: name,
      goal: """
      You are a helpful math assistant. Your task is to perform calculations accurately.
      Use the calculator tool to perform mathematical operations step by step.
      #{goal}
      """,
      tools: ["calculator"]
    )
  end

  defp generate_math_agent_name do
    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16() |> String.slice(0..3)
    "math-#{random_suffix}"
  end
end
