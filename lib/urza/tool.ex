defmodule Urza.Tool do
  @moduledoc """
  A behaviour for Urza tools.
  Each tool is a thin wrapper around an Oban worker that operates on a context map.
  """

  # TODO use reqllm tool api  
  @callback run(map()) :: {:ok, any()} 

  @callback name() :: String.t()

  @callback description() :: String.t()

  @callback parameter_schema() :: Keyword.t()

  @callback return_schema() :: Keyword.t()

  @optional_callbacks [description: 0] 
  
end
