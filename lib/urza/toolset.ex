defmodule Urza.Toolset do
  @moduledoc """
  Registry and formatter for available tools.
  """
  alias ReqLLM.Schema

  @doc """
  Returns the worker module for a given tool name.
  """
  @spec get(String.t()) :: module()
  def get(name) do
    case name do
      "web" -> Urza.Workers.Web
      "calculator" -> Urza.Workers.Calculator
      _ -> raise "Unknown tool: #{name}"
    end
  end

  @doc """
  Formats a tool module for inclusion in LLM system prompts.
  """
  @spec format_tool(module()) :: String.t()
  def format_tool(module) do
    schema =
      module.input_schema()
      |> Schema.to_json()
      |> JSON.encode!()

    """
    name: #{module.name()},
    description: #{module.description()},
    input_schema: #{schema}
    """
  end
end
