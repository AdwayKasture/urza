defmodule Urza.Toolset do
  @moduledoc """
  Registry for AI agent tools using PersistentTerm for O(1) lookups.

  Tools are registered at compile-time or application startup and stored in
  PersistentTerm for efficient runtime access.

  ## Usage

  Register tools during application startup:

      Urza.Toolset.register_tools([
        Urza.Workers.Calculator,
        Urza.Workers.Web,
        MyApp.Tools.CustomTool
      ])

  Then retrieve tools by name:

      Urza.Toolset.get("calculator")
      # => Urza.Workers.Calculator

  """

  @persistent_term_key :urza_tool_registry

  @doc """
  Registers multiple tools at once. Should be called during application startup.

  ## Examples

      Urza.Toolset.register_tools([
        Urza.Workers.Calculator,
        MyApp.Tools.CustomSearch
      ])
  """
  @spec register_tools(list(module())) :: :ok
  def register_tools(modules) when is_list(modules) do
    registry =
      modules
      |> Enum.map(fn mod ->
        # Defer validation - just try to call name/0
        # This allows registration during test setup before modules are fully loaded
        name =
          try do
            mod.name()
          rescue
            _ -> raise ArgumentError, "Module #{inspect(mod)} must implement name/0"
          end

        {name, mod}
      end)
      |> Enum.into(%{})

    :persistent_term.put(@persistent_term_key, registry)
    :ok
  end

  @doc """
  Registers a single tool. Can be called multiple times to add tools incrementally.

  ## Examples

      Urza.Toolset.register_tool(MyApp.Tools.CustomSearch)
  """
  @spec register_tool(module()) :: :ok
  def register_tool(module) do
    name =
      try do
        module.name()
      rescue
        _ -> raise ArgumentError, "Module #{inspect(module)} must implement name/0"
      end

    registry = get_registry()
    updated_registry = Map.put(registry, name, module)
    :persistent_term.put(@persistent_term_key, updated_registry)
    :ok
  end

  @doc """
  Returns the worker module for a given tool name.

  ## Examples

      Urza.Toolset.get("calculator")
      # => Urza.Workers.Calculator
      
      Urza.Toolset.get("unknown")
      # => nil
  """
  @spec get(String.t()) :: module() | nil
  def get(name) when is_binary(name) do
    registry = get_registry()
    Map.get(registry, name)
  end

  @doc """
  Returns all registered tool names.

  ## Examples

      Urza.Toolset.all_names()
      # => ["calculator", "web"]
  """
  @spec all_names() :: list(String.t())
  def all_names() do
    registry = get_registry()
    Map.keys(registry)
  end

  @doc """
  Returns all registered tool modules.

  ## Examples

      Urza.Toolset.all_tools()
      # => [Urza.Workers.Calculator, Urza.Workers.Web]
  """
  @spec all_tools() :: list(module())
  def all_tools() do
    registry = get_registry()
    Map.values(registry)
  end

  @doc """
  Checks if a tool with the given name is registered.

  ## Examples

      Urza.Toolset.registered?("calculator")
      # => true
      
      Urza.Toolset.registered?("unknown")
      # => false
  """
  @spec registered?(String.t()) :: boolean()
  def registered?(name) when is_binary(name) do
    registry = get_registry()
    Map.has_key?(registry, name)
  end

  @doc """
  Clears all registered tools. Useful for testing.
  """
  @spec clear() :: :ok
  def clear() do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  @doc """
  Formats a tool module for inclusion in LLM system prompts.
  """
  @spec format_tool(module()) :: String.t()
  def format_tool(module) do
    alias ReqLLM.Schema

    schema =
      module.input_schema()
      |> Schema.to_json()
      |> JSON.encode!()

    description =
      if function_exported?(module, :description, 0) do
        module.description()
      else
        "No description available"
      end

    """
    name: #{module.name()},
    description: #{description},
    input_schema: #{schema}
    """
  end

  # Private functions

  defp get_registry() do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        # Initialize empty registry on first access
        :persistent_term.put(@persistent_term_key, %{})
        %{}

      registry ->
        registry
    end
  end
end
