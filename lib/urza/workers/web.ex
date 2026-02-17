defmodule Urza.Workers.Web do
  @moduledoc """
  Tool worker for making HTTP requests.
  """
  @behaviour Urza.Tool
  alias Urza.AI.Agent
  alias Req
  require Logger

  use Oban.Worker, queue: :web

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, meta: %{"id" => id}}) do
    case run(args) do
      {:ok, ret} ->
        %{body: body} = ret
        Agent.send_tool_result(id, body)
        :ok

      {:error, reason} ->
        Logger.error("WebWorker failed for job #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Urza.Tool
  def name(), do: "web"

  @impl Urza.Tool
  def description() do
    "This tool performs a simple HTTP GET request to a specified URL and returns the response body."
  end

  @impl Urza.Tool
  def run(%{"url" => url}) do
    case Req.get(url) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status}} ->
        {:error, "HTTP Error: Received status #{status} from #{url}"}

      {:error, reason} ->
        {:error, "Connection Failed: #{inspect(reason)}"}
    end
  end

  def run(_) do
    {:error, "Missing required argument 'url'."}
  end

  @impl Urza.Tool
  def input_schema() do
    [
      url: [
        type: :string,
        required: true,
        doc: "The full URL to send the HTTP GET request to."
      ]
    ]
  end

  @impl Urza.Tool
  def output_schema() do
    [type: :map, required: true]
  end
end
