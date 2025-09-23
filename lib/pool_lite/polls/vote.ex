defmodule PoolLite.Polls.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  alias PoolLite.Polls.{Poll, Option}

  @moduledoc false

  schema "votes" do
    field :user_identifier, :string
    field :voted_at, :naive_datetime

    belongs_to :poll, Poll
    belongs_to :option, Option

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:user_identifier, :voted_at, :poll_id, :option_id])
    |> validate_required([:user_identifier, :poll_id, :option_id])
    |> put_voted_at()
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:option_id)
    |> unique_constraint([:poll_id, :user_identifier], name: :votes_poll_id_user_identifier_index)
  end

  defp put_voted_at(changeset) do
    case get_field(changeset, :voted_at) do
      nil ->
        put_change(
          changeset,
          :voted_at,
          NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )

      _ ->
        changeset
    end
  end
end
