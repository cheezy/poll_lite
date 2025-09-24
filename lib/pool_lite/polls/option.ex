defmodule PoolLite.Polls.Option do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias PoolLite.Polls.{Poll, Vote}

  schema "options" do
    field :text, :string
    field :votes_count, :integer, default: 0

    belongs_to :poll, Poll
    has_many :votes, Vote, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes_count])
    |> validate_required([:text])
    |> validate_length(:text, min: 1, max: 200)
    |> validate_number(:votes_count, greater_than_or_equal_to: 0)
  end
end
