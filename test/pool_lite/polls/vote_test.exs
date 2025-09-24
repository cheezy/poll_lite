defmodule PoolLite.Polls.VoteTest do
  use PoolLite.DataCase, async: true

  alias PoolLite.Polls.Vote

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == "user123"
      assert get_change(changeset, :poll_id) == 1
      assert get_change(changeset, :option_id) == 1
    end

    test "valid changeset with all fields" do
      voted_at = ~N[2024-01-01 12:00:00]
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        voted_at: voted_at
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == "user123"
      assert get_change(changeset, :poll_id) == 1
      assert get_change(changeset, :option_id) == 1
      assert get_change(changeset, :voted_at) == voted_at
    end

    test "automatically sets voted_at when not provided" do
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :voted_at) != nil

      voted_at = get_change(changeset, :voted_at)
      assert %NaiveDateTime{} = voted_at

      # Check it's close to current time (within 2 seconds)
      now = NaiveDateTime.utc_now()
      diff = NaiveDateTime.diff(now, voted_at)
      assert abs(diff) <= 2
    end

    test "preserves provided voted_at" do
      custom_time = ~N[2023-06-15 10:30:00]
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        voted_at: custom_time
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :voted_at) == custom_time
    end

    test "does not override existing voted_at when updating" do
      existing_time = ~N[2023-06-15 10:30:00]
      existing_vote = %Vote{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        voted_at: existing_time
      }

      attrs = %{user_identifier: "user456"}
      changeset = Vote.changeset(existing_vote, attrs)

      assert changeset.valid?
      # voted_at should not be in changes since it already exists
      refute get_change(changeset, :voted_at)
      assert get_field(changeset, :voted_at) == existing_time
    end

    test "invalid changeset without user_identifier" do
      attrs = %{poll_id: 1, option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{user_identifier: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset without poll_id" do
      attrs = %{user_identifier: "user123", option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{poll_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset without option_id" do
      attrs = %{user_identifier: "user123", poll_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{option_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset without any required fields" do
      changeset = Vote.changeset(%Vote{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:user_identifier] == ["can't be blank"]
      assert errors[:poll_id] == ["can't be blank"]
      assert errors[:option_id] == ["can't be blank"]
    end

    test "changeset with empty string user_identifier is invalid" do
      attrs = %{user_identifier: "", poll_id: 1, option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{user_identifier: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with nil values is invalid" do
      attrs = %{user_identifier: nil, poll_id: nil, option_id: nil}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:user_identifier] == ["can't be blank"]
      assert errors[:poll_id] == ["can't be blank"]
      assert errors[:option_id] == ["can't be blank"]
    end

    test "changeset with non-integer poll_id is invalid" do
      attrs = %{user_identifier: "user123", poll_id: "not_an_id", option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{poll_id: ["is invalid"]} = errors_on(changeset)
    end

    test "changeset with non-integer option_id is invalid" do
      attrs = %{user_identifier: "user123", poll_id: 1, option_id: "not_an_id"}
      changeset = Vote.changeset(%Vote{}, attrs)

      refute changeset.valid?
      assert %{option_id: ["is invalid"]} = errors_on(changeset)
    end

    test "changeset ignores unknown fields" do
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        unknown_field: "value"
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      refute get_change(changeset, :unknown_field)
    end

    test "changeset with special characters in user_identifier" do
      attrs = %{
        user_identifier: "user@example.com",
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == "user@example.com"
    end

    test "changeset with UUID as user_identifier" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      attrs = %{
        user_identifier: uuid,
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == uuid
    end

    test "changeset with IP address as user_identifier" do
      attrs = %{
        user_identifier: "192.168.1.1",
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == "192.168.1.1"
    end

    test "changeset with session ID as user_identifier" do
      session_id = "sess_" <> Base.encode64(:crypto.strong_rand_bytes(32))
      attrs = %{
        user_identifier: session_id,
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == session_id
    end

    test "update existing vote changeset" do
      existing_vote = %Vote{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        voted_at: ~N[2023-01-01 12:00:00]
      }

      attrs = %{option_id: 2}
      changeset = Vote.changeset(existing_vote, attrs)

      assert changeset.valid?
      assert get_change(changeset, :option_id) == 2
      refute get_change(changeset, :voted_at)  # Should not change existing voted_at
    end

    test "partial update changeset preserves unchanged fields" do
      existing_vote = %Vote{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1
      }

      attrs = %{user_identifier: "user456"}
      changeset = Vote.changeset(existing_vote, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_identifier) == "user456"
      assert get_field(changeset, :poll_id) == 1
      assert get_field(changeset, :option_id) == 1
    end
  end

  describe "constraints" do
    test "changeset includes foreign key constraint for poll_id" do
      attrs = %{user_identifier: "user123", poll_id: 999999, option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      # The changeset should be valid before database constraints
      assert changeset.valid?

      # Check that the constraint is defined
      assert Enum.any?(changeset.constraints, fn c ->
        c.field == :poll_id and c.type == :foreign_key
      end)
    end

    test "changeset includes foreign key constraint for option_id" do
      attrs = %{user_identifier: "user123", poll_id: 1, option_id: 999999}
      changeset = Vote.changeset(%Vote{}, attrs)

      # The changeset should be valid before database constraints
      assert changeset.valid?

      # Check that the constraint is defined
      assert Enum.any?(changeset.constraints, fn c ->
        c.field == :option_id and c.type == :foreign_key
      end)
    end

    test "changeset includes unique constraint for poll_id and user_identifier" do
      attrs = %{user_identifier: "user123", poll_id: 1, option_id: 1}
      changeset = Vote.changeset(%Vote{}, attrs)

      # The changeset should be valid before database constraints
      assert changeset.valid?

      # Check that the unique constraint is defined (field is poll_id for composite constraint)
      assert Enum.any?(changeset.constraints, fn c ->
        c.field == :poll_id and c.type == :unique and
        c.constraint == "votes_poll_id_user_identifier_index"
      end)
    end
  end

  describe "schema" do
    test "has correct fields" do
      vote = %Vote{}

      assert Map.has_key?(vote, :user_identifier)
      assert Map.has_key?(vote, :voted_at)
      assert Map.has_key?(vote, :poll_id)
      assert Map.has_key?(vote, :option_id)
      assert Map.has_key?(vote, :inserted_at)
      assert Map.has_key?(vote, :updated_at)
    end

    test "has correct default values" do
      vote = %Vote{}

      assert vote.user_identifier == nil
      assert vote.voted_at == nil
      assert vote.poll_id == nil
      assert vote.option_id == nil
    end

    test "associations are defined" do
      assert %Ecto.Association.BelongsTo{} = Vote.__schema__(:association, :poll)
      assert %Ecto.Association.BelongsTo{} = Vote.__schema__(:association, :option)
    end
  end

  describe "voted_at timestamp" do
    test "truncates voted_at to seconds" do
      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      voted_at = get_change(changeset, :voted_at)
      assert voted_at.microsecond == {0, 0}
    end

    test "preserves custom voted_at without modification" do
      custom_time = NaiveDateTime.utc_now()
        |> NaiveDateTime.add(1000, :microsecond)
        |> NaiveDateTime.truncate(:second)

      attrs = %{
        user_identifier: "user123",
        poll_id: 1,
        option_id: 1,
        voted_at: custom_time
      }
      changeset = Vote.changeset(%Vote{}, attrs)

      assert get_change(changeset, :voted_at) == custom_time
    end
  end
end