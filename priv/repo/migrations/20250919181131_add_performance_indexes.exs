defmodule PoolLite.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for searching polls by title (partial index for performance)
    create index(:polls, [:title])

    # Composite index for votes table to speed up vote counting queries
    # This helps with GROUP BY queries in list_polls_with_stats
    create index(:votes, [:poll_id, :option_id])

    # Index for user voting history queries
    create index(:votes, [:user_identifier])

    # Index for sorting options within a poll
    create index(:options, [:poll_id, :inserted_at])
  end
end
