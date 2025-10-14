defmodule Urza.Toolset do



  def get(name) do
    case name do
      "echo" -> Urza.Tools.Echo
      "calculator" -> Urza.Tools.Calculator
    end
  end
  
end
