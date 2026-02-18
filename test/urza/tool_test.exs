defmodule Urza.ToolTest do
  use ExUnit.Case, async: true

  alias Urza.Tool
  alias Urza.Workers.Calculator

  describe "new_job/3" do
    test "creates Oban job changeset" do
      changeset = Tool.new_job(Calculator, %{"op" => "add", "a" => 1, "b" => 2})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :worker) == "Urza.Workers.Calculator"
      assert Ecto.Changeset.get_change(changeset, :args) == %{"op" => "add", "a" => 1, "b" => 2}
    end

    test "includes meta in changeset" do
      changeset = Tool.new_job(Calculator, %{"op" => "add"}, %{"id" => "agent123"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :meta) == %{"id" => "agent123"}
    end

    test "creates valid changeset" do
      changeset = Tool.new_job(Calculator, %{})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :worker) == "Urza.Workers.Calculator"
      # Queue is set by Oban.Worker configuration, not in changeset changes
    end
  end

  describe "behaviour contract" do
    test "calculator implements all required callbacks" do
      required = [
        {:name, 0},
        {:run, 1},
        {:input_schema, 0},
        {:output_schema, 0},
        {:queue, 0}
      ]

      for {func, arity} <- required do
        assert function_exported?(Calculator, func, arity),
               "Calculator should implement #{func}/#{arity}"
      end
    end

    test "description is optional" do
      # Description is marked as optional callback
      # Calculator implements it, but it's not required
      assert function_exported?(Calculator, :description, 0)
    end
  end

  describe "tool signatures" do
    test "name returns string" do
      assert is_binary(Calculator.name())
      assert Calculator.name() == "calculator"
    end

    test "queue returns atom" do
      assert is_atom(Calculator.queue())
    end

    test "input_schema returns keyword list" do
      schema = Calculator.input_schema()
      assert is_list(schema)

      # Each key should have a keyword list as value
      for {key, spec} <- schema do
        assert is_atom(key)
        assert is_list(spec)
        assert Keyword.has_key?(spec, :type)
      end
    end

    test "output_schema returns keyword list" do
      schema = Calculator.output_schema()
      assert is_list(schema)
      assert Keyword.has_key?(schema, :type)
    end

    test "run returns ok/error tuple" do
      result = Calculator.run(%{"op" => "add", "a" => 1, "b" => 2})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
