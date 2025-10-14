defmodule Urza.AiAgent do
  use GenServer
  alias ReqLLM.Response
  alias Urza.Workflow
  alias Urza.Toolset

  @model "gemini"

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


  @impl true
  def handle_info({:exec, job}, state) do

    :ok = Workflow.add_job(state.workflow_id, job)
    {:noreply, state}
  end

  def call_ai(state) do

    tool_specs = build_tool_specs(state.available_tools)
    messages = build_messages(state.goal, state.history,tool_specs)
    schema = [tool_name: [type: :string,required: true],args: [type: :map,required: true,doc: "refer to schema mentioned for tool"]]

    {:ok,%Response{object: tool}} = ReqLLM.generate_object("gemini",messages,schema)
    state = schedule_tool(tool,state)
    
    {:noreply, state}
  end

  def schedule_tool(%{tool_name: name,args: args}, state)do

    tool_ref = "agent_#{state.ref}_tool_#{System.unique_integer([:monotonic])}"

    encode_args = args
    |> Map.to_list()
    |> Enum.map(fn {k,v} -> {k,{:const,v}} end)
    |> Map.new()


    job_def = %{
      tool: Toolset.get(name),
      args: encode_args,
      ref: tool_ref,
      deps: []
    }

    history = state.history ++ [ReqLLM.Context.assistant("executing #{name}")]
    send(self(),{:exec,job_def})

    state = state
    |> Map.put(:current_tool_ref,tool_ref)
    |> Map.put(:history,history)

    state
  end

  def build_messages(goal, history,tools) do
    [
      ReqLLM.Context.system(system_prompt()),
      ReqLLM.Context.user(goal),
      ReqLLM.Context.user("You have access to the following set of tools",
      ReqLLM.Context.user(tools)
      )
    ] ++ history
  end

  def build_tool_specs(tool_names) do
    tool_names
    |> Enum.map(&Toolset.get/1)
    |> Enum.map(&Toolset.format_tool/1)
    |> Enum.reduce("",fn l,r -> l <> r end)
  end

  def system_prompt() do
    """
    You are an AI assistant. Your goal is to help the user by calling tools.
    You can call one tool at a time. When you have the final answer, respond with the answer directly.
    """
  end

end
