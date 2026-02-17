defmodule Urza.Persistence.Schemas.AgentThread do
  @moduledoc """
  Ecto schema for agent threads/conversations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_threads" do
    field(:name, :string)
    field(:input, :string)
    field(:status, :string, default: "running")
    field(:result, :map)
    field(:error_message, :string)

    has_many(:messages, Urza.Persistence.Schemas.Message)

    timestamps()
  end

  @doc false
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:name, :input, :status, :result, :error_message])
    |> validate_required([:name, :input])
  end

  
end
