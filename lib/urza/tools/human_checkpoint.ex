defmodule Urza.Tools.HumanCheckpoint do
  use Oban.Worker, max_attempts: 5
  @behaviour Urza.Tool
  alias Phoenix.PubSub
  @duration 100

  @impl Oban.Worker
  def perform(%Job{
        args: %{"state" => state, "message" => msg},
        id: id,
        meta: %{"workflow_id" => wf, "ref" => ref}
      }) do
    case state do
      "pending" ->
        run(%{"user_id" => wf, "job_id" => id, "message" => msg})
        {:snooze, @duration}

      "accepted" ->
        PubSub.broadcast(Urza.PubSub, wf, {id, %{ref => "accepted"}})
        :ok

      "rejected" ->
        PubSub.broadcast(Urza.PubSub, wf, {id, %{ref => "rejected"}})
        :ok
    end
  end

  @impl Urza.Tool
  def run(%{"user_id" => user_id, "job_id" => job_id, "message" => msg}) do
    IO.inspect({"requiring workflow update for #{user_id} for #{msg}", job_id})

    PubSub.broadcast(
      Urza.PubSub,
      "notification",
      {"requiring workflow update for #{user_id} for #{msg}", job_id}
    )

    {:ok, nil}
  end

  @impl Urza.Tool
  def name(), do: "human approval"

  @impl Urza.Tool
  def description(), do: "Used to wait for human approval"

  @impl Urza.Tool
  def return_schema(), do: []

  @impl Urza.Tool
  def parameter_schema(), do: []

  def approve(job_id) do
    {:ok, job} =
      Oban.update_job(job_id, fn job ->
        args =
          job.args
          |> Map.put("state", "accepted")

        %{args: args}
      end)

    Oban.retry_job(job)
  end

  def deny(job_id) do
    {:ok, job} =
      Oban.update_job(job_id, fn job ->
        args =
          job.args
          |> Map.put("state", "rejected")

        %{args: args}
      end)

    Oban.retry_job(job)
  end
end
