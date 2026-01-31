defmodule Urza.Toolset do
  alias ReqLLM.Schema

  def get(name) do
    case name do
      "echo" -> Urza.Tools.Echo
      "calculator" -> Urza.Tools.Calculator
      "wait" -> Urza.Tools.Wait
      "web" -> Urza.Tools.Web
      "lua" -> Urza.Tools.Lua
      _ -> raise "Unknown tool: #{name}"
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
