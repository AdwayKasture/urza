defmodule Urza.Persistence.Schemas.Message do
  @moduledoc """
  Ecto schema for messages within agent threads.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field(:role, :string)
    field(:content, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:agent_thread, Urza.Persistence.Schemas.AgentThread)

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :agent_thread_id])
    |> validate_required([:role, :content, :agent_thread_id])
  end

  
end
