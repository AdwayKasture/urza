defmodule Urza.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add(:role, :string, null: false)
      add(:content, :text, null: false)
      add(:metadata, :map, default: %{})
      add(:agent_thread_id, references(:agent_threads, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(index(:messages, [:agent_thread_id]))
  end
end
