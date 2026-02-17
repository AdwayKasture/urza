defmodule Urza.Workflow do
  @moduledoc """
  A GenServer that manages a directed acyclic graph (DAG) of work items.

  Work items can be either:
  - Tool jobs (executed via Oban)
  - Agent jobs (spawned as child processes)

  The workflow tracks dependencies and executes items when their dependencies are met.
  """

  alias Urza.Workers.Calculator
  alias Urza.Workers.Echo
  alias Oban.Job
  alias Registry
  use GenServer
  require Logger

  @heartbeat_interval 1000

  defstruct id: nil,
            work: [],
            acc: %{},
            # map with (job_id => ref)
            executing_jobs: %{},
            # list of agent refs
            executing_agents: [],
            completed_refs: MapSet.new()

  @doc """
  Starts a new workflow process.

  ## Options

  * `:id` - Required. Unique identifier for the workflow.
  * `:work` - Required. List of work items defining the DAG.
  * `:acc` - Optional. Initial accumulator map (default: %{}).
  """
  def start_link(opts) do
    id = opts[:id] || raise "id is required"
    work = opts[:work] || []
    acc = opts[:acc] || %{}

    name = {:via, Registry, {Urza.WorkflowRegistry, id}}
    GenServer.start_link(__MODULE__, %{id: id, work: work, acc: acc}, name: name)
  end

  @doc """
  Adds a new job to an existing workflow.
  """
  def add_job(workflow_id, job_def) do
    GenServer.cast({:via, Registry, {Urza.WorkflowRegistry, workflow_id}}, {:add_job, job_def})
  end

  @impl GenServer
  def init(opts) do
    id = opts[:id]
    work = opts[:work]
    initial_acc = Map.get(opts, :acc, %{})

    send(self(), :start)

    state = %__MODULE__{
      id: id,
      work: work,
      acc: initial_acc,
      executing_jobs: %{},
      executing_agents: [],
      completed_refs: MapSet.new()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add_job, job}, ctx) do
    work = ctx.work ++ [job]
    ctx = %{ctx | work: work}
    ctx = queue_ready_jobs(ctx)
    {:noreply, ctx}
  end

  @impl GenServer
  def handle_cast({:agent_done, ref, ret}, ctx) do
    Logger.info("Agent #{ref} has completed task")

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
          Logger.info("Workflow #{ctx.id} completed execution")
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
        completed_refs =
          Enum.reduce(refs, ctx.completed_refs, fn ref, acc -> MapSet.put(acc, ref) end)

        executing_jobs = Map.delete(ctx.executing_jobs, job_id)
        ctx = %{ctx | executing_jobs: executing_jobs, completed_refs: completed_refs}

        if Enum.empty?(ctx.executing_jobs) and Enum.empty?(ctx.executing_agents) and
             Enum.empty?(ctx.work) do
          Logger.info("Workflow #{ctx.id} completed execution")
          {:noreply, ctx}
        else
          ctx = queue_ready_jobs(ctx)
          {:noreply, ctx}
        end
    end
  end

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

        if Enum.empty?(ctx.executing_jobs) and Enum.empty?(ctx.executing_agents) and
             Enum.empty?(ctx.work) do
          Logger.info("Workflow #{ctx.id} completed execution")
          {:noreply, ctx}
        else
          ctx = queue_ready_jobs(ctx)
          {:noreply, ctx}
        end
    end
  end

  defp queue_ready_jobs(ctx) do
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
      name: agent.agent,
      workflow_id: workflow_id,
      goal: agent.goal,
      tools: agent.tools,
      ref: agent.ref
    ]

    {:ok, _pid} = Urza.AgentSupervisor.start_agent(opts)
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

  # Example workflow definitions for testing

  @doc """
  Example workflow demonstrating tool chaining.
  Calculates: ((5 + 3) * 2) - 4 = 12 and echoes the result
  """
  def example_chaining() do
    %{
      id: "chain-workflow",
      work: [
        # Step 1: 5 + 3 = 8
        %{
          tool: Calculator,
          args: %{"a" => {:const, 5}, "b" => {:const, 3}, "op" => {:const, "add"}},
          ref: "$step1",
          deps: []
        },
        # Step 2: $step1 * 2 = 16
        %{
          tool: Calculator,
          args: %{"a" => {:dyn, "$step1"}, "b" => {:const, 2}, "op" => {:const, "multiply"}},
          ref: "$step2",
          deps: ["$step1"]
        },
        # Step 3: $step2 - 4 = 12
        %{
          tool: Calculator,
          args: %{"a" => {:dyn, "$step2"}, "b" => {:const, 4}, "op" => {:const, "subtract"}},
          ref: "$step3",
          deps: ["$step2"]
        },
        # Step 4: Echo the final result
        %{
          tool: Echo,
          args: %{"message" => {:dyn, "$step3"}},
          ref: nil,
          deps: ["$step3"]
        }
      ]
    }
  end

  @doc """
  Example workflow demonstrating fan-out/fan-in pattern.
  Calculates: (10 + 20) + (30 + 40) = 100 and echoes the result
  """
  def example_fan() do
    %{
      id: "fan-workflow",
      work: [
        # Fan-out: Two parallel additions
        %{
          tool: Calculator,
          args: %{"a" => {:const, 10}, "b" => {:const, 20}, "op" => {:const, "add"}},
          ref: "$branch1",
          deps: []
        },
        %{
          tool: Calculator,
          args: %{"a" => {:const, 30}, "b" => {:const, 40}, "op" => {:const, "add"}},
          ref: "$branch2",
          deps: []
        },
        # Fan-in: Combine both results
        %{
          tool: Calculator,
          args: %{"a" => {:dyn, "$branch1"}, "b" => {:dyn, "$branch2"}, "op" => {:const, "add"}},
          ref: "$combined",
          deps: ["$branch1", "$branch2"]
        },
        # Echo the final result
        %{
          tool: Echo,
          args: %{"message" => {:dyn, "$combined"}},
          ref: nil,
          deps: ["$combined"]
        }
      ]
    }
  end

  @doc """
  Example workflow demonstrating agent integration with calculator and echo.
  Agent performs: (33 + 45 + 90 + 2) / 10 and prints the result
  """
  def example_agent() do
    %{
      id: "agent-workflow",
      work: [
        %{
          agent: "math-agent",
          tools: ["calculator", "echo"],
          goal:
            "Calculate (33 + 45 + 90 + 2) / 10 step by step. First add 33 and 45, then add 90 to that result, then add 2, and finally divide by 10. After getting the final result, use the echo tool to print 'The final result is: <result>'",
          ref: "$agent_result",
          deps: []
        }
      ]
    }
  end
end
