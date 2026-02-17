defmodule Urza.Repo.Migrations.CreateAgentThreads do
  use Ecto.Migration

  def change do
    create table(:agent_threads) do
      add(:name, :string, null: false)
      add(:input, :text, null: false)
      add(:status, :string, default: "running")
      add(:result, :map)
      add(:error_message, :text)

      timestamps()
    end

    create(index(:agent_threads, [:name]))
    create(index(:agent_threads, [:status]))
  end
end
