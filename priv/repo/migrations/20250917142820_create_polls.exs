defmodule PoolLite.Repo.Migrations.CreatePolls do
  use Ecto.Migration

  def change do
    create table(:polls) do
      add :title, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create index(:polls, [:inserted_at])
  end
end
