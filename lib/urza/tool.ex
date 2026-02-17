defmodule Urza.Tool do
  @moduledoc """
  A behaviour for tools that can be used by AI agents.
  """

  @doc """
  Execute the tool with the given arguments.
  Returns {:ok, result} on success or {:error, reason} on failure.
  """
  @callback run(map()) :: {:ok, any()} | {:error, any()}

  @doc """
  Returns the unique name of the tool as a string.
  This is used to identify the tool in agent interactions.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.
  This helps the AI understand when and how to use the tool.
  """
  @callback description() :: String.t()

  @doc """
  Returns the input schema for the tool as a keyword list.
  Defines what parameters the tool expects.
  """
  @callback input_schema() :: Keyword.t()

  @doc """
  Returns the output schema for the tool as a keyword list.
  Defines what the tool returns.
  """
  @callback output_schema() :: Keyword.t()

  @optional_callbacks [description: 0]
end
