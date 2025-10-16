defmodule Urza.AiAgent do
  use GenServer
  alias Mint.HTTP1.Response
  alias ReqLLM.Response
  alias Urza.Toolset
  alias Phoenix.PubSub

  @model "google:gemini-2.0-flash"

  defstruct goal: nil,
            available_tools: [],
            history: [],
            workflow_id: nil,
            ref: nil,
            current_tool_ref: nil,
            seq: 0

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

    state =
      %__MODULE__{
        workflow_id: workflow_id,
        goal: goal,
        available_tools: available_tools,
        ref: ref,
        history: [],
        seq: 0
      }

    # TODO: Persist the initial agent state here.
    # This could be done by saving the `state` struct to a database.
    {:ok, state}
  end

  @impl true
  def handle_info(:start, state) do
    call_ai(state)
  end

  @impl GenServer
  def handle_info({_job_id, res}, state) do
    val = res[state.current_tool_ref]
    IO.inspect("Tool returned: #{val}")
    history = state.history ++ [ReqLLM.Context.user("tool returned: #{val}")]
    state = %{state | history: history}
    # TODO: Persist the updated agent state here after a tool returns.
    call_ai(state)
  end

  def call_ai(state) do
    messages = build_messages(state.goal, state.history, state.available_tools)
    {:ok, resp} = ReqLLM.generate_text(@model, messages)
    text = Response.text(resp)
    IO.inspect("LLM response: #{text}")

    state =
      text
      |> String.trim()
      |> String.trim_leading("```json\n")
      |> String.trim_trailing("\n```")
      |> JSON.decode!()
      |> schedule_tool(state)

    # TODO: Persist the updated agent state here after calling the AI.
    {:noreply, state}
  end

  def schedule_tool(%{"answer" => answer}, state) do
    # Agent has finished, notify the main workflow
    IO.inspect("Agent is returning : #{answer}")

    GenServer.cast(
      {:via, Registry, {Urza.WorkflowRegistry, state.workflow_id}},
      {:agent_done, state.ref, answer}
    )

    state
  end

  def schedule_tool(%{"tool" => name, "args" => args}, state) do
    seq = state.seq + 1
    tool_ref = "agent_#{state.ref}_tool_#{seq}"

    queue_tool_job(name, args, tool_ref, state.ref)

    history = state.history ++ [ReqLLM.Context.user("executing #{name}")]

    state
    |> Map.put(:current_tool_ref, tool_ref)
    |> Map.put(:history, history)
    |> Map.put(:seq, seq)
  end

  defp queue_tool_job(tool_name, args, tool_ref, agent_ref) do
    meta = %{workflow_id: agent_ref, ref: tool_ref}

    Toolset.get(tool_name).new(args, meta: meta)
    |> Oban.insert()
  end

  def build_messages(goal, history, tools) do
    [
      ReqLLM.Context.system(system_prompt(tools)),
      ReqLLM.Context.user(goal),
      ReqLLM.Context.user(
        "You have access to the following set of tools",
        ReqLLM.Context.user(tools)
      )
    ] ++ history
  end

  def system_prompt(tools) do
    specs =
      tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.map(&Toolset.format_tool/1)
      |> Enum.reduce("", fn l, r -> l <> r end)

    """
    You are an AI assistant. Your goal is to help the user by calling tools.
    You can call one tool at a time.
    to call a tool you must give a JSON format such as
    ```json
    {"tool": "tool_name","args": {"tool_arg_a": "data_a","tool_arg_b": "data_b"...}}
    ```
    When you have the final answer, you must respond with a JSON format such as
    ```json
    {"answer": "your answer"}

    You have access to the following tools
    #{specs}
    ```
    """
  end
end
