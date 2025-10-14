defmodule Urza.Toolset do
  alias ReqLLM.Schema
  def get(name) do
    case name do
      "echo" -> Urza.Tools.Echo
      "calculator" -> Urza.Tools.Calculator
    end
  end

  def format_tool(module) do
    """
      name: #{module.name()},
      description: #{module.description()},
      parameter_schema: #{Schema.to_json(module.parameter_schema())}
    """
  end
end
