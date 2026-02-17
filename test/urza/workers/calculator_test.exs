defmodule Urza.Workers.CalculatorTest do
  use ExUnit.Case, async: true

  alias Urza.Workers.Calculator

  test "name returns calculator" do
    assert Calculator.name() == "calculator"
  end

  test "description returns string" do
    assert is_binary(Calculator.description())
    assert String.contains?(Calculator.description(), "mathematical")
  end

  test "add operation" do
    assert {:ok, 8} = Calculator.run(%{"op" => "add", "a" => 5, "b" => 3})
    assert {:ok, 0} = Calculator.run(%{"op" => "add", "a" => -5, "b" => 5})
  end

  test "subtract operation" do
    assert {:ok, 2} = Calculator.run(%{"op" => "subtract", "a" => 5, "b" => 3})
    assert {:ok, -10} = Calculator.run(%{"op" => "subtract", "a" => -5, "b" => 5})
  end

  test "multiply operation" do
    assert {:ok, 15} = Calculator.run(%{"op" => "multiply", "a" => 5, "b" => 3})
    assert {:ok, 0} = Calculator.run(%{"op" => "multiply", "a" => 5, "b" => 0})
  end

  test "divide operation" do
    assert {:ok, 2.5} = Calculator.run(%{"op" => "divide", "a" => 5, "b" => 2})
    assert {:ok, 1.0} = Calculator.run(%{"op" => "divide", "a" => 5, "b" => 5})
  end

  test "divide by zero returns error" do
    assert {:error, "Division by zero"} = Calculator.run(%{"op" => "divide", "a" => 5, "b" => 0})
  end

  test "unsupported operation returns error" do
    assert {:error,
            "Unsupported operation: power. Must be 'add', 'subtract', 'multiply', or 'divide'."} =
             Calculator.run(%{"op" => "power", "a" => 2, "b" => 3})
  end

  test "invalid arguments returns error" do
    assert {:error, "Invalid arguments. Requires 'op', 'a', and 'b' parameters."} =
             Calculator.run(%{"foo" => "bar"})
  end

  test "input_schema returns keyword list" do
    schema = Calculator.input_schema()
    assert is_list(schema)
    assert Keyword.has_key?(schema, :op)
    assert Keyword.has_key?(schema, :a)
    assert Keyword.has_key?(schema, :b)
  end

  test "output_schema returns keyword list" do
    schema = Calculator.output_schema()
    assert is_list(schema)
    assert Keyword.get(schema, :type) == :number
  end
end
