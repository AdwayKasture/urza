defmodule Urza.Toolset do
  alias ReqLLM.Schema

  def get(name) do
    case name do
      "echo" -> Urza.Tools.Echo
      "calculator" -> Urza.Tools.Calculator
    end
  end

  def format_tool(module) do
    schema =
      module.parameter_schema()
      |> Schema.to_json()
      |> JSON.encode!()

    """
      name: #{module.name()},
      description: #{module.description()},
      parameter_schema: #{schema}
    """
  end
end
