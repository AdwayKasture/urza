defmodule Urza.Workers.WebTest do
  use ExUnit.Case, async: true

  alias Urza.Workers.Web

  test "name returns web" do
    assert Web.name() == "web"
  end

  test "description returns string" do
    assert is_binary(Web.description())
    assert String.contains?(Web.description(), "HTTP")
  end

  test "input_schema returns keyword list" do
    schema = Web.input_schema()
    assert is_list(schema)
    assert Keyword.has_key?(schema, :url)
  end

  test "output_schema returns keyword list" do
    schema = Web.output_schema()
    assert is_list(schema)
    assert Keyword.get(schema, :type) == :map
  end

  test "run with missing url returns error" do
    assert {:error, "Missing required argument 'url'."} = Web.run(%{})
  end
end
