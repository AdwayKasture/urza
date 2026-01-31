defmodule Urza.Test.Fixtures do
  alias ReqLLM.{Response, Message, Context}
  alias ReqLLM.Message.ContentPart

  @moduledoc """
  Test fixtures and helpers for mocking LLM responses.
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

  def extract_message_content(message) do
    message.content |> Enum.map(& &1.text) |> Enum.join("")
  end
end
