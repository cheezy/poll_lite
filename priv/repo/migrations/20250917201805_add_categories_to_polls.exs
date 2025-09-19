defmodule PoolLite.Repo.Migrations.AddCategoriesToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      add :category, :string
      add :tags, {:array, :string}, default: []
    end

    create index(:polls, [:category])
    create index(:polls, [:tags], using: :gin)
  end
end
