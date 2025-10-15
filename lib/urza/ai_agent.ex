defmodule Urza.AiAgent do
  use GenServer
  alias ReqLLM.Response
  alias Urza.Workflow
  alias Urza.Toolset
  alias Oban.Job
  alias Phoenix.PubSub

  @model "google:gemini-2.0-flash"

  defstruct goal: nil,
            available_tools: [],
            history: [],
            workflow_id: nil,
            ref: nil,
            current_tool_ref: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    workflow_id = opts[:workflow_id]
    goal = opts[:goal]
    available_tools = opts[:available_tools]
    ref = opts[:ref]

    PubSub.subscribe(Urza.PubSub, ref)
    send(self(), :start)

    {:ok,
     %__MODULE__{
       workflow_id: workflow_id,
       goal: goal,
       available_tools: available_tools,
       ref: ref,
       history: []
     }}
  end

  @impl true
  def handle_info(:start, state) do
    call_ai(state)
  end

  @impl GenServer
  def handle_info({_job_id, result}, state) do
    history = state.history ++ [ReqLLM.Context.user(result)]
    state = %{state | history: history}
    call_ai(state)
  end

  def call_ai(state) do
    tool_specs = build_tool_specs(state.available_tools)
    messages = build_messages(state.goal, state.history, tool_specs)
    {:ok, resp} = ReqLLM.generate_text(@model, messages)

    state = resp
    |> Response.text()
    |> String.trim()
    |> String.trim_leading("```json")
    |> String.trim_trailing("```")
    |> IO.inspect()
    |> JSON.decode!()
    |> schedule_tool(state)

    {:noreply, state}
  end

  def schedule_tool(%{"answer" => answer}, state) do
    # Agent has finished, notify the main workflow
    GenServer.cast({:via, Registry, {Urza.WorkflowRegistry, state.workflow_id}}, {:agent_done, state.ref, answer})
    state
  end

  def schedule_tool(%{"tool" => name, "args" => args}, state) do
    tool_ref = "agent_#{state.ref}_tool_#{System.unique_integer([:monotonic])}"

    queue_tool_job(name, args, tool_ref, state.ref)

    history = state.history ++ [ReqLLM.Context.user("executing #{name}")]

    state
    |> Map.put(:current_tool_ref, tool_ref)
    |> Map.put(:history, history)
  end

  defp queue_tool_job(tool_name, args, tool_ref, agent_ref) do
    meta = %{workflow_id: agent_ref, ref: tool_ref}

    # In an agent context all args are constants
    encode_args =
      args
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> {k, {:const, v}} end)
      |> Map.new()

    Toolset.get(tool_name).new(encode_args, meta: meta)
    |> Oban.insert()
  end

  def build_messages(goal, history, tools) do
    [
      ReqLLM.Context.system(system_prompt()),
      ReqLLM.Context.user(goal),
      ReqLLM.Context.user(
        "You have access to the following set of tools",
        ReqLLM.Context.user(tools)
      )
    ] ++ history
  end

  def build_tool_specs(tool_names) do
    tool_names
    |> Enum.map(&Toolset.get/1)
    |> Enum.map(&Toolset.format_tool/1)
    |> Enum.reduce("", fn l, r -> l <> r end)
  end

  def system_prompt() do
    """
    You are an AI assistant. Your goal is to help the user by calling tools.
    You can call one tool at a time.
    to call a tool you must give a JSON format such as
    ```json
    {"tool": "calculator","args": {"o": "add","l": 3,"r": 5}}
    ```
    When you have the final answer, you must respond with a JSON format such as
    ```json
    {"answer": "your answer"}
    ```
    """
  end
end
