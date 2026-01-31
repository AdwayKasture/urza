defmodule Urza.Tools.LuaTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Urza.Repo

  alias Urza.Tools.Lua

  setup tags do
    Urza.DataCase.setup_sandbox(tags)
    :ok
  end

  describe "run/1" do
    test "returns error when script is missing" do
      assert {:error, "Missing required parameter: script"} = Lua.run(%{})
    end

    test "executes simple Lua script" do
      result = Lua.run(%{"script" => "return 42"})
      assert {:ok, 42} = result
    end

    test "executes Lua script with return value" do
      result = Lua.run(%{"script" => "return 'hello world'"})
      assert {:ok, "hello world"} = result
    end

    test "executes Lua script with input variables" do
      script = """
      return x + y
      """

      result = Lua.run(%{"script" => script, "input" => %{"x" => 10, "y" => 20}})
      assert {:ok, 30} = result
    end

    test "executes Lua script with string input" do
      script = """
      return "Hello, " .. name .. "!"
      """

      result = Lua.run(%{"script" => script, "input" => %{"name" => "Alice"}})
      assert {:ok, "Hello, Alice!"} = result
    end

    test "executes Lua script with table operations" do
      script = """
      local sum = 0
      for i = 1, #numbers do
        sum = sum + numbers[i]
      end
      return sum
      """

      result = Lua.run(%{"script" => script, "input" => %{"numbers" => [1, 2, 3, 4, 5]}})
      assert {:ok, 15} = result
    end

    test "returns error for invalid Lua syntax" do
      result = Lua.run(%{"script" => "if then return end"})
      assert {:error, _} = result
    end

    test "returns error for Lua runtime error" do
      result = Lua.run(%{"script" => "return undefined_variable + 1"})
      assert {:error, _} = result
    end

    test "parameter_schema returns expected structure" do
      schema = Lua.parameter_schema()

      assert Keyword.has_key?(schema, :script)
      assert Keyword.has_key?(schema, :input)

      assert schema[:script][:type] == :string
      assert schema[:script][:required] == true
      assert schema[:input][:type] == :map
      assert schema[:input][:required] == false
    end

    test "return_schema returns expected structure" do
      schema = Lua.return_schema()
      assert schema[:type] == :any
      assert schema[:required] == true
    end

    test "name returns 'lua'" do
      assert Lua.name() == "lua"
    end

    test "description returns expected string" do
      assert Lua.description() == "Executes Lua scripts with custom input variables"
    end
  end

  describe "Oban Worker" do
    test "enqueues job with correct queue" do
      changeset =
        Lua.new(%{"script" => "return 1"}, meta: %{"ref" => "test", "workflow_id" => "wf1"})

      job = Ecto.Changeset.apply_changes(changeset)

      assert job.queue == "script"
      assert job.max_attempts == 1
      assert job.args == %{"script" => "return 1"}
    end
  end
end
