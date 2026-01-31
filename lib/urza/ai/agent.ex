defmodule Urza.AI.Agent do
  @moduledoc """
  A generic AI agent that autonomously executes tools to achieve a goal.

  The agent uses an LLM to decide which tools to call and when it has
  achieved its goal. It supports both successful completion and error reporting.

  ## Return Formats

  When successful, the agent returns:
  ```json
  {"answer": "final result", "confidence": 1-10}
  ```

  When the agent cannot complete the task:
  ```json
  {"error": "unable to do task due to ..."}
  ```
  """
  use GenServer, restart: :temporary
  alias Urza.Toolset
  alias Urza.AI.Agent
  alias Urza.AI.LLMAdapter
  alias ReqLLM.Context
  alias Phoenix.PubSub
  require Logger

  @model "google:gemini-2.5-flash"

  defstruct goal: nil,
            available_tools: [],
            history: [],
            workflow_id: nil,
            current_tool_ref: nil,
            ref: nil,
            args: nil,
            seq: 0,
            thread_id: nil,
            id: nil

  @doc """
  Starts a new AI agent process.

  ## Options

  * `:id` - Required. Unique identifier for the agent (used for registry).
  * `:ref` - Required. Reference string for PubSub notifications.
  * `:goal` - Required. The goal the agent should achieve.
  * `:available_tools` - List of tool names the agent can use.
  * `:workflow_id` - ID of the parent workflow (if any).
  * `:args` - Additional arguments for the agent.
  """
  def start_link(opts) do
    id = opts[:id] || raise "id is required"
    _ref = opts[:ref] || raise "ref is required"

    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Urza.AgentRegistry, id}})
  end

  @doc """
  Sends a tool result back to the agent.

  ## Parameters

  * `id` - The agent's ID.
  * `result` - The result string from the tool execution.
  """
  def send_tool_result(id, result) do
    GenServer.cast(
      {:via, Registry, {Urza.AgentRegistry, id}},
      {:tool_result, result}
    )
  end

  @impl true
  def init(opts) do
    PubSub.subscribe(Urza.PubSub, "agent:#{opts[:id]}:logs")
    send(self(), :start)

    state = new(opts)

    # TODO: Persist the initial agent state here.
    # This could be done by saving the `state` struct to a database
    # or ETS table for crash recovery and resume capability.
    {:ok, state}
  end

  @impl true
  def handle_info(:start, state) do
    call_ai(state)
  end

  # Handle tool results from PubSub (Calculator tool broadcasts {job_id, %{ref => result}})
  @impl true
  def handle_info({_job_id, ret}, state) when is_map(ret) do
    case state.current_tool_ref do
      nil ->
        {:noreply, state}

      ref ->
        case Map.fetch(ret, ref) do
          :error ->
            {:noreply, state}

          {:ok, result} ->
            handle_cast({:tool_result, result}, state)
        end
    end
  end

  # Ignore broadcasted status events (ai_thinking, tool_started, tool_completed, etc.)
  @impl true
  def handle_info({_event, _agent_id}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({_event, _agent_id, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({_event, _agent_id, _, _}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:tool_result, result}, state) do
    broadcast_event(state.id, {:tool_completed, state.id, result})

    message_content = "tool returned: #{result}"
    history = state.history ++ [Context.user(message_content)]
    state = %{state | history: history}

    # TODO: Persist the tool result here.
    # Store the result in the agent's history for replay/resume.

    call_ai(state)
  end

  defp call_ai(state) do
    messages = build_messages(state.goal, state.history, state.available_tools)

    IO.inspect(@model, label: "LLM MODEL")
    IO.inspect(state.goal, label: "AGENT GOAL")
    IO.inspect(state.available_tools, label: "AVAILABLE TOOLS")
    IO.inspect(messages, label: "MESSAGES")

    broadcast_event(state.id, {:ai_thinking, state.id})

    case LLMAdapter.generate_text(@model, messages) do
      {:ok, resp} ->
        resp
        |> ReqLLM.Response.text()
        |> extract_json()
        |> JSON.decode()
        |> case do
          {:ok, tool} ->
            case schedule_tool(tool, state) do
              {:stop, reason, new_state} -> {:stop, reason, new_state}
              updated_state -> {:noreply, updated_state}
            end

          {:error, e} ->
            error_msg = "Failed to parse AI response: #{inspect(e)}"
            broadcast_event(state.id, {:error, state.id, error_msg})

            # TODO: Persist the error state here.
            # Record the parse error for debugging and recovery.

            {:stop, :parse_error, state}
        end

      {:error, reason} ->
        error_msg = "LLM API call failed: #{inspect(reason)}"
        IO.inspect(reason, label: "LLM ERROR")
        broadcast_event(state.id, {:error, state.id, error_msg})

        # TODO: Persist the error state here.
        # Record the LLM failure for retry logic.

        {:stop, :llm_error, state}
    end
  end

  def schedule_tool(
        %{
          "answer" => answer,
          "confidence" => confidence
        } = response,
        state
      )
      when confidence in 1..10 do
    Logger.info("Agent #{state.id} completed successfully: #{answer}")

    broadcast_event(state.id, {:agent_completed, state.id, response})

    # Notify parent workflow of completion
    if state.workflow_id do
      GenServer.cast(
        {:via, Registry, {Urza.WorkflowRegistry, state.workflow_id}},
        {:agent_done, state.ref, answer}
      )
    end

    # TODO: Persist the completion here.
    # Mark the agent as completed with the final answer.

    {:stop, :normal, state}
  end

  def schedule_tool(
        %{
          "error" => error_message
        } = _response,
        state
      ) do
    Logger.warning("Agent #{state.id} reported error: #{error_message}")

    broadcast_event(state.id, {:agent_error, state.id, error_message})

    # Notify parent workflow of error
    if state.workflow_id do
      GenServer.cast(
        {:via, Registry, {Urza.WorkflowRegistry, state.workflow_id}},
        {:agent_error, state.ref, error_message}
      )
    end

    # TODO: Persist the error state here.
    # Record the agent-reported error for analysis.

    {:stop, {:agent_error, error_message}, state}
  end

  def schedule_tool(%{"tool" => tool_name, "args" => args}, state) when is_map(args) do
    seq = state.seq + 1
    tool_ref = "#{state.id}_tool_#{seq}"

    broadcast_event(state.id, {:tool_started, state.id, tool_name, args})

    case queue_tool_job(tool_name, args, tool_ref, state.id) do
      :ok ->
        message_content = "executing #{tool_name}"
        history = state.history ++ [Context.user(message_content)]

        # TODO: Persist the tool call here.
        # Store the tool call details for replay capability.

        state
        |> Map.put(:current_tool_ref, tool_ref)
        |> Map.put(:history, history)
        |> Map.put(:seq, seq)

      {:error, reason} ->
        error_msg = "Failed to queue tool job: #{inspect(reason)}"
        broadcast_event(state.id, {:error, state.id, error_msg})

        # TODO: Persist the error state here.
        # Record the tool queue failure.

        {:stop, :tool_queue_error, state}
    end
  end

  def schedule_tool(%{"tool" => tool_name, "args" => args}, state) do
    error_msg = "Invalid tool args for #{tool_name}: expected map, got #{inspect(args)}"
    broadcast_event(state.id, {:error, state.id, error_msg})

    # TODO: Persist the error state here.
    # Record the invalid args error.

    {:stop, :invalid_args, state}
  end

  def schedule_tool(invalid_response, state) do
    error_msg = "Invalid AI response format: #{inspect(invalid_response)}"
    broadcast_event(state.id, {:error, state.id, error_msg})

    # TODO: Persist the error state here.
    # Record the invalid response format error.

    {:stop, :invalid_response, state}
  end

  defp queue_tool_job(tool_name, args, tool_ref, agent_id) do
    meta = %{id: agent_id, ref: tool_ref}

    try do
      worker = Toolset.get(tool_name)
      job = worker.new(args, meta: meta)
      Oban.insert(job)
      :ok
    rescue
      e ->
        {:error, e}
    catch
      :throw, e ->
        {:error, e}

      :exit, e ->
        {:error, e}
    end
  end

  def build_messages(goal, history, tools) do
    [
      Context.system(system_prompt(tools)),
      Context.user(goal)
    ] ++ history
  end

  def system_prompt(tools) do
    specs =
      tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.map(&Toolset.format_tool/1)
      |> Enum.reduce("", fn l, r -> l <> r end)

    """
    You are an AI assistant that helps users by calling tools.
    You can call one tool at a time.
    To call a tool you must give a JSON format such as mentioned below.
    DO NOT explain reasoning, just return the structured output.

    ```json
    {"tool": "tool_name", "args": {"tool_arg_a": "data_a", "tool_arg_b": "data_b", ...}}
    ```

    When you have the final answer, you must respond with a JSON format such as:
    ```json
    {"answer": "your final answer", "confidence": 1-10}
    ```

    If you are unable to complete the task, respond with:
    ```json
    {"error": "unable to do task due to ..."}
    ```

    You have access to the following tools:
    #{specs}
    """
  end

  defp new(opts) do
    %Agent{
      id: opts[:id],
      workflow_id: opts[:workflow_id],
      goal: opts[:goal],
      ref: opts[:ref],
      available_tools: opts[:available_tools] || [],
      args: opts[:args],
      history: [],
      seq: 0,
      thread_id: nil
    }
  end

  def extract_json(input) when is_binary(input) do
    input
    |> String.trim_trailing("\n```")
    |> String.split("```json\n")
    |> case do
      [_, expected_json] -> expected_json
      [maybe_json] -> maybe_json
    end
  end

  @impl true
  def terminate(reason, state) do
    case reason do
      :normal ->
        Logger.info("Agent #{state.id} terminated normally")

      {:agent_error, error_msg} ->
        Logger.warning("Agent #{state.id} terminated with error: #{error_msg}")

      :shutdown ->
        Logger.info("Agent #{state.id} shut down")

      {:shutdown, _} ->
        Logger.info("Agent #{state.id} shut down")

      _ ->
        error_msg = "GenServer crashed: #{inspect(reason)}"
        Logger.error("Agent #{state.id} terminated: #{error_msg}")

        # TODO: Persist the crash state here.
        # Record unexpected termination for debugging.
    end

    :ok
  end

  defp broadcast_event(id, event) do
    Phoenix.PubSub.broadcast(
      Urza.PubSub,
      "agent:#{id}:logs",
      event
    )
  end
end
