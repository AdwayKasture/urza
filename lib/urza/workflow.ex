defmodule Urza.Workflow do
  alias Urza.Tools.{HumanCheckpoint, Calculator, Echo, Wait, Branch}
  alias Urza.Workflow
  alias Urza.AiAgent
  alias Oban.Job
  alias Phoenix.PubSub
  use GenServer
  alias Registry

  @heartbeat_interval 1000

  defstruct id: nil,
            work: [],
            acc: %{},
            # map with (job_id => ref)
            executing_jobs: %{},
            # list of agent refs 
            executing_agents: [],
            completed_refs: MapSet.new()

  def start_link({id, work, acc}) do
    # Use the :via tuple to register the process using the Registry
    name = {:via, Registry, {Urza.WorkflowRegistry, id}}

    GenServer.start_link(Workflow, %{id: id, work: work, acc: acc}, name: name)
  end

  def add_job(workflow_id, job_def) do
    GenServer.cast({:via, Registry, {Urza.WorkflowRegistry, workflow_id}}, {:add_job, job_def})
  end

  @impl GenServer
  def init(opts) do
    id = opts[:id]
    work = opts[:work]
    initial_acc = Map.get(opts, :acc, %{})

    PubSub.subscribe(Urza.PubSub, id)
    send(self(), :start)

    {:ok,
     %Workflow{
       id: id,
       work: work,
       acc: initial_acc,
       executing_jobs: %{},
       executing_agents: [],
       completed_refs: MapSet.new()
     }}
  end

  @impl GenServer
  def handle_cast({:add_job, job}, ctx) do
    work = ctx.work ++ [job]
    ctx = %{ctx | work: work}
    ctx = queue_ready_jobs(ctx)
    {:noreply, ctx}
  end

  # For Agent work completetion
  @impl GenServer
  def handle_cast({:agent_done, ref, ret}, ctx) do
    IO.puts("Agent #{ref} has completed task !!!")

    case Enum.member?(ctx.executing_agents, ref) do
      false ->
        # Agent not tracked, ignore.
        {:noreply, ctx}

      true ->
        acc = Map.merge(%{ref => ret}, ctx.acc)

        completed_refs = if ref, do: MapSet.put(ctx.completed_refs, ref), else: ctx.completed_refs
        executing_agents = Enum.reject(ctx.executing_agents, fn v -> v == ref end)

        ctx = %{
          ctx
          | acc: acc,
            executing_agents: executing_agents,
            completed_refs: completed_refs
        }

        if Enum.empty?(ctx.executing_jobs) and Enum.empty?(ctx.executing_agents) and
             Enum.empty?(ctx.work) do
          IO.inspect("completed execution !!!")
          {:noreply, ctx}
        else
          ctx = queue_ready_jobs(ctx)
          {:noreply, ctx}
        end
    end
  end

  @impl GenServer
  def handle_info(:start, ctx) do
    schedule_heartbeat()
    ctx = queue_ready_jobs(ctx)
    {:noreply, ctx}
  end

  @impl GenServer
  def handle_info(:heartbeat, ctx) do
    # detect_dead_graph(ctx)
    schedule_heartbeat()
    {:noreply, ctx}
  end

  @impl GenServer
  def handle_info({:branch, job_id, refs}, ctx) when is_integer(job_id) do
    case Map.fetch(ctx.executing_jobs, job_id) do
      :error ->
        # Job not tracked, ignore.
        {:noreply, ctx}

      {:ok, _job} ->
        # 2. Update the completed references set.
        completed_refs =
          Enum.reduce(refs, ctx.completed_refs, fn ref, acc -> MapSet.put(acc, ref) end)

        # 3. Clean up the executing jobs map.
        executing_jobs = Map.delete(ctx.executing_jobs, job_id)

        # 4. Update the context (note: no 'acc' update, as this is a flow control job)
        ctx = %{ctx | executing_jobs: executing_jobs, completed_refs: completed_refs}

        # 5. Check for new runnable jobs and continue the workflow.
        if Enum.empty?(ctx.executing_jobs) and Enum.empty?(ctx.executing_agents) and
             Enum.empty?(ctx.work) do
          IO.inspect("completed execution !!!")
          {:noreply, ctx}
        else
          ctx = queue_ready_jobs(ctx)
          {:noreply, ctx}
        end
    end
  end

  # For Tool work completetion
  @impl GenServer
  def handle_info({job_id, ret}, ctx) when is_integer(job_id) do
    case Map.fetch(ctx.executing_jobs, job_id) do
      :error ->
        # Job not tracked, ignore.
        {:noreply, ctx}

      {:ok, ref} ->
        acc = Map.merge(ret, ctx.acc)

        completed_refs = if ref, do: MapSet.put(ctx.completed_refs, ref), else: ctx.completed_refs
        executing_jobs = Map.delete(ctx.executing_jobs, job_id)
        ctx = %{ctx | acc: acc, executing_jobs: executing_jobs, completed_refs: completed_refs}

        if Enum.empty?(ctx.executing_jobs) and Enum.empty?(ctx.work) do
          IO.inspect("completed execution !!!")
          {:noreply, ctx}
        else
          ctx = queue_ready_jobs(ctx)
          {:noreply, ctx}
        end
    end
  end

  defp queue_ready_jobs(ctx) do
    # identify which jobs/agents can be fired
    {runnable, waiting} =
      Enum.split_with(ctx.work, fn job ->
        dependencies_met?(job.deps, ctx.completed_refs)
      end)

    {runnable_agents, runnable_jobs} =
      Enum.split_with(runnable, fn
        %{agent: _, goal: _, tools: _, ref: _} -> true
        %{tool: _} -> false
      end)

    new_executing_jobs =
      runnable_jobs
      |> Enum.map(fn job ->
        {:ok, %Job{id: job_id}} = queue_one_job(job, ctx.id, ctx.acc)
        {job_id, job.ref}
      end)
      |> Map.new()

    new_executing_agents =
      Enum.map(runnable_agents, fn agent -> queue_one_agent(agent, ctx.id, ctx.acc) end)

    %{
      ctx
      | work: waiting,
        executing_jobs: Map.merge(ctx.executing_jobs, new_executing_jobs),
        executing_agents: ctx.executing_agents ++ new_executing_agents
    }
  end

  defp dependencies_met?(deps, completed_refs) do
    Enum.all?(deps, &MapSet.member?(completed_refs, &1))
  end

  defp queue_one_agent(agent, workflow_id, _acc) do
    opts = [
      name: {:via, Registry, {Urza.WorkflowRegistry, agent.ref}},
      workflow_id: workflow_id,
      goal: agent.goal,
      available_tools: agent.tools,
      ref: agent.ref
    ]

    # reusing the same supervisor for our agents
    {:ok, _pid} = DynamicSupervisor.start_child(Urza.WorkflowSupervisor, {AiAgent, opts})
    agent.ref
  end

  defp queue_one_job(job, workflow_id, acc) do
    meta = %{workflow_id: workflow_id, ref: job.ref}

    deref_args = decode_args(job.args, acc)

    job.tool.new(deref_args, meta: meta)
    |> Oban.insert()
  end

  defp decode_args(args, acc) when is_map(args) do
    args
    |> Map.to_list()
    |> Enum.map(fn
      {k, {:const, v}} -> {k, v}
      {k, {:dyn, ref}} -> {k, acc[ref]}
    end)
    |> Map.new()
  end

  defp schedule_heartbeat(), do: Process.send_after(self(), :heartbeat, @heartbeat_interval)

  def detect_dead_graph(ctx) when is_struct(ctx, Workflow) do
    runnable =
      Enum.any?(ctx.work, fn job -> dependencies_met?(job.deps, ctx.completed_refs) end)

    if !runnable and map_size(ctx.executing_jobs) == 0 and map_size(ctx.executing_agents) == 0 and
         ctx.work != [] do
      IO.puts("🚨 Dead graph detected! Remaining waiting jobs cannot run: #{inspect(ctx.work)}")
      exit("Illegal state handle")
    end
  end

  @moduledoc """
  handle ai agent

  """

  def test_missing_deps() do
    %{
      id: "main-workflow",
      work: [
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 2}, "op" => {:const, "add"}},
          ref: "$1",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"l" => {:const, 1}, "r" => {:const, 2}, "op" => {:const, "add"}},
          ref: "$2",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{
            "l" => {:dyn, "$1"},
            "r" => {:dyn, "$2"},
            "op" => {:const, "multiply"}
          },
          ref: "$3",
          deps: ["$1", "$2"]
        },
        %{
          tool: Echo,
          args: %{"content" => {:dyn, "$3"}},
          ref: nil,
          deps: ["$3"]
        }
      ]
    }
  end

  def test_fan() do
    %{
      id: "test_fan",
      work: [
        %{
          tool: Wait,
          args: %{},
          ref: "$1",
          deps: []
        },
        %{
          tool: Wait,
          args: %{},
          ref: "$2",
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:const, "done!!"}},
          ref: "$3",
          deps: ["$1", "$2"]
        }
      ]
    }
  end

  def test_human_checkpoint() do
    %{
      id: "human",
      work: [
        %{
          tool: HumanCheckpoint,
          args: %{"state" => {:const, "pending"}, "message" => {:const, "are you cracked dev ?"}},
          ref: "$1",
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:dyn, "$1"}},
          ref: nil,
          deps: ["$1"]
        }
      ]
    }
  end

  def test_branch(criteria) do
    %{
      id: "branchy",
      work: [
        %{
          tool: Branch,
          args: %{
            "condition" => {:const, criteria},
            "true" => {:const, "$1"},
            "false" => {:const, "$2"}
          },
          ref: nil,
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:const, "true case !!"}},
          ref: nil,
          deps: ["$1"]
        },
        %{
          tool: Echo,
          args: %{"content" => {:const, "false case !!"}},
          ref: nil,
          deps: ["$2"]
        }
      ]
    }
  end

  # TODO
  def test_agent() do
    %{
      id: "agent",
      work: [
        %{
          agent: "007",
          tools: ["calculator", "echo"],
          goal: "add 33,27 and then divide by then, then print it",
          ref: "$agent_007",
          deps: []
        },
        %{
          tool: Echo,
          args: %{"content" => {:dyn, "$agent_007"}},
          ref: nil,
          deps: ["$agent_007"]
        }
      ]
    }
  end
end
