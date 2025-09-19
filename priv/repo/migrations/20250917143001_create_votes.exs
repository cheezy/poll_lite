defmodule PoolLite.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :user_identifier, :string, null: false
      add :voted_at, :naive_datetime, null: false
      add :poll_id, references(:polls, on_delete: :delete_all), null: false
      add :option_id, references(:options, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:votes, [:poll_id])
    create index(:votes, [:option_id])

    create unique_index(:votes, [:poll_id, :user_identifier],
             name: :votes_poll_id_user_identifier_index
           )
  end
end
