defmodule Urza.Test.Fixtures do
  @moduledoc """
  Test fixtures for mocking LLM responses and other test data.
  """
  alias ReqLLM.{Response, Message, Context}
  alias ReqLLM.Message.ContentPart

  @doc """
  Creates a mock LLM response with the given text content.
  """
  def mock_llm_response(text, usage \\ %{}) do
    mock_message = %Message{
      role: :assistant,
      content: [%ContentPart{type: :text, text: text}]
    }

    mock_context = %Context{}

    %Response{
      id: "mock_res_id_#{System.unique_integer([:positive])}",
      model: "mock:test-model",
      context: mock_context,
      message: mock_message,
      object: nil,
      stream?: false,
      stream: nil,
      usage: usage,
      finish_reason: :stop,
      provider_meta: %{duration_ms: 100},
      error: nil
    }
  end

  @doc """
  Helper to extract message content from ReqLLM format.
  """
  def extract_message_content(message) do
    message.content |> Enum.map(& &1.text) |> Enum.join("")
  end

  @doc """
  Creates a mock tool call response.
  """
  def mock_tool_call(tool_name, args) do
    ~s({"tool": "#{tool_name}", "args": #{Jason.encode!(args)}})
  end

  @doc """
  Creates a mock completion response.
  """
  def mock_completion(result) do
    ~s({"completion": #{Jason.encode!(result)}})
  end
end
