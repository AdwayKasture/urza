defmodule Urza.AI.Agent do
  @moduledoc """
  Generic AI Agent that takes tools, goals, and args.
  Implements a ReAct pattern with configurable adapters for persistence and communication.
  """
  use GenServer, restart: :temporary
  alias Urza.Toolset
  alias Urza.AI.LLMAdapter
  alias Urza.PersistenceAdapter
  alias Urza.NotificationAdapter
  alias ReqLLM.Context
  require Logger

  defstruct available_tools: [],
            history: [],
            name: nil,
            input: nil,
            seq: 0,
            goal: nil,
            model: nil,
            completion_schema: nil,
            thread_id: nil,
            workflow_id: nil,
            ref: nil

  @type t :: %__MODULE__{
          available_tools: list(String.t()),
          history: list(),
          name: String.t(),
          input: String.t(),
          seq: non_neg_integer(),
          goal: String.t(),
          model: String.t(),
          completion_schema: keyword(),
          thread_id: any(),
          workflow_id: String.t() | nil,
          ref: String.t() | nil
        }

  @default_model "google:gemini-2.5-flash"

  def start_link(opts) do
    name = opts[:name] || raise "name is required"
    _goal = opts[:goal] || raise "goal is required"
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Urza.AgentRegistry, name}})
  end

  @impl GenServer
  def init(opts) do
    send(self(), :start)
    state = new(opts)

    case PersistenceAdapter.create_thread(state) do
      {:ok, thread_id} ->
        state = %{state | thread_id: thread_id}
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to persist initial thread: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def send_tool_result(name, result) do
    GenServer.cast(
      {:via, Registry, {Urza.AgentRegistry, name}},
      {:tool_result, result}
    )
  end

  @impl GenServer
  def handle_info(:start, state) do
    call_ai(state)
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:tool_result, result}, state) do
    NotificationAdapter.notify(state.name, {:tool_completed, state.name, result})

    message_content = "tool returned: #{result}"
    history = state.history ++ [Context.user(message_content)]
    state = %{state | history: history}

    PersistenceAdapter.persist_state(state.thread_id, %{
      name: state.name,
      input: state.input,
      status: "running",
      seq: state.seq,
      history: state.history,
      result: nil,
      error_message: nil
    })

    call_ai(state)
  end

  defp call_ai(state) do
    messages = build_messages(state.history, state.available_tools, state.input, state.goal)

    NotificationAdapter.notify(state.name, {:ai_thinking, state.name})

    case LLMAdapter.generate_text(state.model, messages) do
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
            NotificationAdapter.notify(state.name, {:error, state.name, error_msg})
            PersistenceAdapter.persist_error(state.thread_id, error_msg)
            {:stop, :parse_error, state}
        end

      {:error, reason} ->
        error_msg = "LLM API call failed: #{inspect(reason)}"
        NotificationAdapter.notify(state.name, {:error, state.name, error_msg})
        PersistenceAdapter.persist_error(state.thread_id, error_msg)
        {:stop, :llm_error, state}
    end
  end

  def schedule_tool(%{"completion" => completion} = result, state) when is_map(completion) do
    Logger.info("Agent #{state.name} completed with result: #{inspect(completion)}")

    PersistenceAdapter.persist_result(state.thread_id, result)

    NotificationAdapter.notify(state.name, {:agent_completed, state.name, result})

    # Notify parent workflow of completion if part of a workflow
    if state.workflow_id && state.ref do
      GenServer.cast(
        {:via, Registry, {Urza.WorkflowRegistry, state.workflow_id}},
        {:agent_done, state.ref, result}
      )
    end

    {:stop, :normal, state}
  end

  def schedule_tool(%{"tool" => tool_name, "args" => args}, state) when is_map(args) do
    seq = state.seq + 1

    NotificationAdapter.notify(state.name, {:tool_started, state.name, tool_name, args})

    case queue_tool_job(tool_name, args, state.name) do
      :ok ->
        message_content = "executing #{tool_name}"
        history = state.history ++ [Context.user(message_content)]

        PersistenceAdapter.persist_state(state.thread_id, %{
          name: state.name,
          input: state.input,
          status: "running",
          seq: state.seq,
          history: state.history,
          result: nil,
          error_message: nil
        })

        state
        |> Map.put(:history, history)
        |> Map.put(:seq, seq)

      {:error, reason} ->
        error_msg = "Failed to queue tool job: #{inspect(reason)}"
        NotificationAdapter.notify(state.name, {:error, state.name, error_msg})
        PersistenceAdapter.persist_error(state.thread_id, error_msg)
        {:stop, :tool_queue_error, state}
    end
  end

  def schedule_tool(%{"tool" => tool_name, "args" => args}, state) do
    error_msg = "Invalid tool args for #{tool_name}: expected map, got #{inspect(args)}"
    NotificationAdapter.notify(state.name, {:error, state.name, error_msg})
    PersistenceAdapter.persist_error(state.thread_id, error_msg)
    {:stop, :invalid_args, state}
  end

  def schedule_tool(invalid_response, state) do
    error_msg = "Invalid AI response format: #{inspect(invalid_response)}"
    NotificationAdapter.notify(state.name, {:error, state.name, error_msg})
    PersistenceAdapter.persist_error(state.thread_id, error_msg)
    {:stop, :invalid_response, state}
  end

  defp queue_tool_job(tool_name, args, id) do
    meta = %{id: id}

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

  def build_messages(history, tools, input, goal) do
    base_prompt = """
    The input to process is given below:
    #{input}
    """

    [
      Context.system(system_prompt(tools, goal)),
      Context.user(base_prompt)
    ] ++ history
  end

  def system_prompt(tools, goal) do
    specs =
      tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.map(&Toolset.format_tool/1)
      |> Enum.reduce("", fn l, r -> l <> r end)

    """
    #{goal}

    You can call one tool at a time.
    To call a tool you must give a JSON format such as mentioned below.
    DO NOT explain reasoning just return the structured output.

    ```json
    {"tool": "tool_name","args": {"tool_arg_a": "data_a","tool_arg_b": "data_b"...}}
    ```

    When you have completed your task, respond with a completion in JSON format:

    ```json
    {"completion": {"result": "your final result here", "details": "any additional details"}}
    ```

    You have access to the following tools:
    #{specs}
    """
  end

  defp new(opts) do
    %__MODULE__{
      name: opts[:name],
      available_tools: opts[:tools] || [],
      input: opts[:input],
      goal: opts[:goal],
      model: opts[:model] || @default_model,
      completion_schema: opts[:completion_schema] || [type: :map, required: true],
      history: [],
      seq: 0,
      thread_id: nil,
      workflow_id: opts[:workflow_id],
      ref: opts[:ref]
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
    if state.thread_id do
      error_msg =
        case reason do
          :shutdown -> "Agent was shut down"
          {:shutdown, _} -> "Agent was shut down"
          :normal -> "Agent completed normally"
          _ -> "GenServer crashed: #{inspect(reason)}"
        end

      if reason !== :normal do
        PersistenceAdapter.persist_error(state.thread_id, error_msg)
        Logger.error("Agent #{state.name} terminated: #{error_msg}")
      else
        Logger.info("Agent #{state.name} terminated: #{error_msg}")
      end
    end

    :ok
  end
end
