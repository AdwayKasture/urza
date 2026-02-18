defmodule Urza.Workers.EchoTest do
  use ExUnit.Case, async: true

  alias Urza.Workers.Echo
  import ExUnit.CaptureIO

  describe "tool callbacks" do
    test "name returns echo" do
      assert Echo.name() == "echo"
    end

    test "description returns string" do
      assert is_binary(Echo.description())
      assert String.contains?(Echo.description(), "Prints")
    end

    test "input_schema returns keyword list with message" do
      schema = Echo.input_schema()
      assert is_list(schema)
      assert Keyword.has_key?(schema, :message)

      message_spec = Keyword.get(schema, :message)
      assert Keyword.get(message_spec, :type) == :string
      assert Keyword.get(message_spec, :required) == true
    end

    test "output_schema returns keyword list" do
      schema = Echo.output_schema()
      assert is_list(schema)
      assert Keyword.get(schema, :type) == :string
    end

    test "queue returns :default" do
      assert Echo.queue() == :default
    end
  end

  describe "run/1" do
    test "prints message to stdout" do
      output =
        capture_io(fn ->
          assert {:ok, "Hello World"} = Echo.run(%{"message" => "Hello World"})
        end)

      assert String.contains?(output, "[Echo] Hello World")
    end

    test "returns the message" do
      assert {:ok, "Test Message"} = Echo.run(%{"message" => "Test Message"})
    end

    test "handles empty string message" do
      output =
        capture_io(fn ->
          assert {:ok, ""} = Echo.run(%{"message" => ""})
        end)

      assert String.contains?(output, "[Echo] ")
    end

    test "handles multi-line messages" do
      message = "Line 1\nLine 2\nLine 3"

      output =
        capture_io(fn ->
          assert {:ok, ^message} = Echo.run(%{"message" => message})
        end)

      assert String.contains?(output, "[Echo] #{message}")
    end

    test "returns error for missing message" do
      assert {:error, "Invalid arguments. Requires 'message' parameter."} =
               Echo.run(%{})
    end

    test "handles nil message by printing empty string" do
      # nil is a valid value that gets converted to empty string when interpolated
      output =
        capture_io(fn ->
          assert {:ok, nil} = Echo.run(%{"message" => nil})
        end)

      assert String.contains?(output, "[Echo] ")
    end
  end

  describe "Oban.Worker" do
    test "is an Oban worker" do
      # Verify it's an Oban worker by checking it has new/2 function
      assert function_exported?(Echo, :new, 2)
      assert function_exported?(Echo, :new, 1)
      assert function_exported?(Echo, :perform, 1)
    end

    test "creates valid Oban job changeset" do
      changeset = Echo.new(%{"message" => "Test"}, meta: %{"id" => "agent123"})

      assert changeset.valid?
      assert get_change(changeset, :worker) == "Urza.Workers.Echo"
      assert get_change(changeset, :args) == %{"message" => "Test"}
      assert get_change(changeset, :meta) == %{"id" => "agent123"}
      # Queue is set by Oban.Worker and validated, but not stored in changeset changes
    end

    test "perform sends result to agent" do
      agent_name = "test_echo_agent_#{System.unique_integer()}"

      # Start agent (simplified test - just verify the call pattern)
      # In real scenario, perform would call Agent.send_tool_result
      job = %Oban.Job{
        args: %{"message" => "Test Message"},
        meta: %{"id" => agent_name}
      }

      # The perform function should complete successfully
      assert :ok = Echo.perform(job)
    end
  end

  describe "integration" do
    test "implements Urza.Tool behaviour" do
      # Verify all required callbacks are implemented
      required_callbacks = [
        {:name, 0},
        {:run, 1},
        {:input_schema, 0},
        {:output_schema, 0},
        {:queue, 0}
      ]

      for {callback, arity} <- required_callbacks do
        assert function_exported?(Echo, callback, arity),
               "Expected #{inspect(Echo)} to implement #{callback}/#{arity}"
      end
    end
  end

  defp get_change(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end
end
