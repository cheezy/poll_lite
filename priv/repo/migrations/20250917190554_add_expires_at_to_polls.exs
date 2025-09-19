defmodule PoolLite.Repo.Migrations.AddExpiresAtToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      add :expires_at, :utc_datetime
    end

    # Add index for efficient querying of expired polls
    create index(:polls, [:expires_at])
  end
end
