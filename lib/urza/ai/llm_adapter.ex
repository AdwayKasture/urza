defmodule Urza.AI.LLMAdapter do
  @moduledoc """
  Adapter module for LLM interactions that provides a consistent interface
  and allows for mocking in tests using Mox.
  """

  @callback generate_text(model :: String.t(), messages :: list()) ::
              {:ok, ReqLLM.Response.t()} | {:error, term()}

  @callback user_message(content :: String.t()) :: ReqLLM.Context.t()
  @callback system_message(content :: String.t()) :: ReqLLM.Context.t()

  def generate_text(model, messages) do
    impl().generate_text(model, messages)
  end

  defp impl do
    Application.get_env(:urza, :llm_adapter, ReqLLM)
  end
  
end
