defmodule Urza.ToolsetTest do
  use ExUnit.Case, async: false

  alias Urza.Toolset
  alias Urza.Workers.{Calculator, Web, Echo}

  # Create a test tool module
  defmodule TestTool do
    use Oban.Worker, queue: :test
    @behaviour Urza.Tool

    @impl Urza.Tool
    def name(), do: "test_tool"

    @impl Urza.Tool
    def description(), do: "A test tool"

    @impl Urza.Tool
    def run(args), do: {:ok, args}

    @impl Urza.Tool
    def input_schema(), do: [value: [type: :string, required: true]]

    @impl Urza.Tool
    def output_schema(), do: [type: :map]

    @impl Urza.Tool
    def queue(), do: :test

    @impl Oban.Worker
    def perform(%Oban.Job{}), do: :ok
  end

  setup do
    # Clear and re-register tools for each test
    Toolset.clear()
    :ok
  end

  describe "register_tools/1" do
    test "registers multiple tools at once" do
      assert :ok = Toolset.register_tools([Calculator, Web, Echo])
      assert Toolset.registered?("calculator")
      assert Toolset.registered?("web")
      assert Toolset.registered?("echo")
    end

    test "overwrites existing registry" do
      Toolset.register_tools([Calculator])
      assert Toolset.registered?("calculator")
      refute Toolset.registered?("web")

      Toolset.register_tools([Web])
      refute Toolset.registered?("calculator")
      assert Toolset.registered?("web")
    end

    test "raises on module without name/0" do
      assert_raise ArgumentError, ~r/must implement name\/0/, fn ->
        Toolset.register_tools([String])
      end
    end
  end

  describe "register_tool/1" do
    test "registers a single tool" do
      assert :ok = Toolset.register_tool(Calculator)
      assert Toolset.registered?("calculator")
    end

    test "adds tool incrementally" do
      Toolset.register_tool(Calculator)
      Toolset.register_tool(Web)

      assert Toolset.registered?("calculator")
      assert Toolset.registered?("web")
    end

    test "updates existing tool" do
      Toolset.register_tool(TestTool)
      assert Toolset.get("test_tool") == TestTool

      # Re-register with same name (simulating a different module with same name)
      # In practice, this would be a new version of the tool
      Toolset.register_tool(TestTool)
      assert Toolset.get("test_tool") == TestTool
    end
  end

  describe "get/1" do
    setup do
      Toolset.register_tools([Calculator, Web])
      :ok
    end

    test "returns tool module for registered tool" do
      assert Calculator = Toolset.get("calculator")
      assert Web = Toolset.get("web")
    end

    test "returns nil for unregistered tool" do
      assert nil == Toolset.get("unknown_tool")
      assert nil == Toolset.get("")
    end

    test "returns nil for non-existent tool" do
      Toolset.clear()
      assert nil == Toolset.get("calculator")
    end
  end

  describe "registered?/1" do
    setup do
      Toolset.register_tool(Calculator)
      :ok
    end

    test "returns true for registered tool" do
      assert Toolset.registered?("calculator")
    end

    test "returns false for unregistered tool" do
      refute Toolset.registered?("web")
      refute Toolset.registered?("unknown")
    end
  end

  describe "all_names/0" do
    test "returns empty list when no tools registered" do
      assert [] = Toolset.all_names()
    end

    test "returns all registered tool names" do
      Toolset.register_tools([Calculator, Web, Echo])
      names = Toolset.all_names()

      assert length(names) == 3
      assert "calculator" in names
      assert "web" in names
      assert "echo" in names
    end
  end

  describe "all_tools/0" do
    test "returns empty list when no tools registered" do
      assert [] = Toolset.all_tools()
    end

    test "returns all registered tool modules" do
      Toolset.register_tools([Calculator, Web])
      tools = Toolset.all_tools()

      assert length(tools) == 2
      assert Calculator in tools
      assert Web in tools
    end
  end

  describe "clear/0" do
    test "removes all registered tools" do
      Toolset.register_tools([Calculator, Web, Echo])
      assert length(Toolset.all_tools()) == 3

      assert :ok = Toolset.clear()
      assert [] = Toolset.all_tools()
      assert [] = Toolset.all_names()
      refute Toolset.registered?("calculator")
    end
  end

  describe "format_tool/1" do
    test "formats tool for LLM prompt" do
      formatted = Toolset.format_tool(Calculator)

      assert is_binary(formatted)
      assert String.contains?(formatted, "name: calculator")
      assert String.contains?(formatted, "description:")
      assert String.contains?(formatted, "input_schema:")
    end

    test "handles tool without description callback" do
      # Create a minimal test tool without description
      defmodule MinimalTool do
        use Oban.Worker, queue: :test
        @behaviour Urza.Tool

        @impl Urza.Tool
        def name(), do: "minimal"

        @impl Urza.Tool
        def run(_), do: {:ok, nil}

        @impl Urza.Tool
        def input_schema(), do: []

        @impl Urza.Tool
        def output_schema(), do: []

        @impl Urza.Tool
        def queue(), do: :test

        @impl Oban.Worker
        def perform(%Oban.Job{}), do: :ok
      end

      formatted = Toolset.format_tool(MinimalTool)
      assert String.contains?(formatted, "No description available")
    end
  end

  describe "PersistentTerm storage" do
    test "uses PersistentTerm for storage" do
      Toolset.register_tool(Calculator)

      # Verify it's in PersistentTerm
      registry = :persistent_term.get(:urza_tool_registry)
      assert is_map(registry)
      assert Map.has_key?(registry, "calculator")
    end

    test "survives process restarts" do
      Toolset.register_tool(Calculator)

      # Simulate getting registry in new process
      registry = :persistent_term.get(:urza_tool_registry)
      assert Map.get(registry, "calculator") == Calculator
    end
  end
end
