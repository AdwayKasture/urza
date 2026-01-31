defmodule Urza.Tools.Wait do
  @moduledoc """
  A tool that waits for a random duration between 1-2 seconds.
  Useful for testing workflow orchestration.
  """

  use Urza.Tools.Base, queue: :default, max_attempts: 1

  @impl Urza.Tool
  def run(_) do
    1000..2000
    |> Enum.random()
    |> Process.sleep()

    {:ok, "sleeep!"}
  end

  @impl Urza.Tool
  def name(), do: "sleep"

  @impl Urza.Tool
  def description(), do: "Used to sleep a random duration"

  @impl Urza.Tool
  def return_schema(), do: []

  @impl Urza.Tool
  def parameter_schema(), do: []
end
