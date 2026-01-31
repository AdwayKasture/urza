defmodule Urza.Tools.Lua do
  @moduledoc """
  A tool for executing Lua scripts.

  Allows AI agents to run custom Lua code with provided input variables.
  Uses the `lua` hex package for Lua execution.
  """

  use Urza.Tools.Base, queue: :script, max_attempts: 1

  @impl Urza.Tool
  def name, do: "lua"

  @impl Urza.Tool
  def description, do: "Executes Lua scripts with custom input variables"

  @impl Urza.Tool
  def run(%{"script" => script} = args) do
    input = Map.get(args, "input", %{})

    # Prepend variable declarations to the script
    full_script = inject_input_vars(script, input)

    # Create a new Lua state
    state = Lua.new()

    try do
      # Execute the script - eval! returns {results, state}
      {results, _new_state} = Lua.eval!(state, full_script)
      {:ok, format_results(results)}
    catch
      kind, reason ->
        {:error, "Lua script crashed: #{kind} - #{inspect(reason)}"}
    end
  end

  def run(_), do: {:error, "Missing required parameter: script"}

  @impl Urza.Tool
  def parameter_schema do
    [
      script: [
        type: :string,
        required: true,
        doc: "The Lua script code to execute"
      ],
      input: [
        type: :map,
        required: false,
        doc: "Input variables to pass to the Lua script (accessible as global variables)"
      ]
    ]
  end

  @impl Urza.Tool
  def return_schema do
    [
      type: :any,
      required: true,
      doc: "The result returned by the Lua script"
    ]
  end

  defp inject_input_vars(script, input) when is_map(input) do
    var_declarations =
      input
      |> Enum.map(fn {key, value} ->
        key_str = to_string(key)
        lua_value = elixir_to_lua(value)
        "#{key_str} = #{lua_value}"
      end)
      |> Enum.join("\n")

    if var_declarations == "" do
      script
    else
      var_declarations <> "\n" <> script
    end
  end

  defp inject_input_vars(script, _), do: script

  defp elixir_to_lua(value) when is_binary(value), do: "#{inspect(value)}"
  defp elixir_to_lua(value) when is_number(value), do: to_string(value)
  defp elixir_to_lua(value) when is_boolean(value) and value == true, do: "true"
  defp elixir_to_lua(value) when is_boolean(value) and value == false, do: "false"

  defp elixir_to_lua(value) when is_list(value),
    do: "{" <> Enum.map_join(value, ", ", &elixir_to_lua/1) <> "}"

  defp elixir_to_lua(nil), do: "nil"
  defp elixir_to_lua(value), do: inspect(to_string(value))

  defp format_results([single_result]), do: format_value(single_result)
  defp format_results(results) when is_list(results), do: Enum.map(results, &format_value/1)
  defp format_results(result), do: format_value(result)

  defp format_value(value) when is_list(value), do: to_string(value)
  defp format_value(value) when is_tuple(value), do: Tuple.to_list(value)
  defp format_value(value), do: value
end
