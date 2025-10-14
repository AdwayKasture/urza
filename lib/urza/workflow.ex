defmodule Urza.Workflow do
  alias Urza.Tools.HumanCheckpoint
  alias Urza.Tools.Wait
  alias Urza.Workflow
  alias Urza.Tools.Calculator
  alias Urza.Tools.Echo
  alias Oban.Job
  alias Phoenix.PubSub
  use GenServer

  @heartbeat_interval 1000

  defstruct id: nil,
            work: [],
            acc: %{},
            executing_jobs: %{},
            completed_refs: MapSet.new()

  def start_link(opts) do
    GenServer.start_link(Workflow, opts)
  end

  @impl GenServer
  def init(opts) do
    id = opts[:id]
    work = opts[:work]
    initial_acc = Map.get(opts, :acc, %{})

    PubSub.subscribe(Urza.PubSub, id)
    send(self(), :start)
    {:ok, %Workflow{id: id, work: work, acc: initial_acc, executing_jobs: %{}, completed_refs: MapSet.new()}}
  end

  @impl GenServer
  def handle_info(:start, ctx) do
    schedule_heartbeat()
    ctx = queue_ready_jobs(ctx)
    {:noreply, ctx}
  end

  @impl GenServer
  def handle_info(:heartbeat, ctx) do
    detect_dead_graph(ctx)
    schedule_heartbeat()
    {:noreply,ctx}
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
        IO.inspect(acc)

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
    {runnable_jobs, waiting_jobs} =
      Enum.split_with(ctx.work, fn job ->
        dependencies_met?(job.deps, ctx.completed_refs)
      end)

    new_executing_jobs =
      runnable_jobs
      |> Enum.map(fn job ->
        {:ok, %Job{id: job_id}} = queue_one_job(job, ctx.id, ctx.acc)
        {job_id, job.ref}
      end)
      |> Map.new()

    %{ctx | work: waiting_jobs, executing_jobs: Map.merge(ctx.executing_jobs, new_executing_jobs)}
  end

  defp dependencies_met?(deps, completed_refs) do
    Enum.all?(deps, &MapSet.member?(completed_refs, &1))
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

  defp schedule_heartbeat(),do: Process.send_after(self(),:heartbeat,@heartbeat_interval)
   
  defp detect_dead_graph(ctx) when is_struct(ctx,Workflow) do
    runnable =
    Enum.any?(ctx.work, fn job -> dependencies_met?(job.deps, ctx.completed_refs) end)
    if !runnable and map_size(ctx.executing_jobs) == 0 and ctx.work != [] do
      IO.puts("🚨 Dead graph detected! Remaining waiting jobs cannot run: #{inspect(ctx.work)}")
      exit("Illegal state handle")
    end
  end

  @moduledoc """
  handle loops (on hold for now) 
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
          deps: ["$1","$2"]
        },
        %{
          tool: Echo,
          args: %{"content" => {:dyn,"$3"}},
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
          args: %{"content" => {:const,"done!!"}},
          ref: "$3",
          deps: ["$1","$2"]
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
          args: %{"state" => {:const,"pending"},"message" => {:const,"are you cracked dev ?"}},
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

end
