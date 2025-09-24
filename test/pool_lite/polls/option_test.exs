defmodule PoolLite.Polls.OptionTest do
  use PoolLite.DataCase, async: true

  alias PoolLite.Polls.Option

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{text: "Option 1"}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Option 1"
    end

    test "valid changeset with all fields" do
      attrs = %{text: "Option 1", votes_count: 5}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Option 1"
      assert get_change(changeset, :votes_count) == 5
    end

    test "invalid changeset without required text field" do
      attrs = %{votes_count: 5}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset with empty text" do
      attrs = %{text: ""}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset with text too short" do
      attrs = %{text: ""}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset with text too long" do
      long_text = String.duplicate("a", 201)
      attrs = %{text: long_text}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{text: ["should be at most 200 character(s)"]} = errors_on(changeset)
    end

    test "valid changeset with text exactly at max length" do
      max_text = String.duplicate("a", 200)
      attrs = %{text: max_text}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == max_text
    end

    test "valid changeset with text at min length" do
      attrs = %{text: "a"}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "a"
    end

    test "invalid changeset with negative votes_count" do
      attrs = %{text: "Option 1", votes_count: -1}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{votes_count: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "valid changeset with zero votes_count" do
      attrs = %{text: "Option 1", votes_count: 0}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      # votes_count of 0 is same as default, so no change is recorded
      assert changeset.changes == %{text: "Option 1"}
    end

    test "valid changeset with large votes_count" do
      attrs = %{text: "Option 1", votes_count: 999999}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :votes_count) == 999999
    end

    test "changeset ignores unknown fields" do
      attrs = %{text: "Option 1", unknown_field: "value"}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Option 1"
      refute get_change(changeset, :unknown_field)
    end

    test "changeset with nil text is invalid" do
      attrs = %{text: nil}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with non-integer votes_count is invalid" do
      attrs = %{text: "Option 1", votes_count: "not a number"}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{votes_count: ["is invalid"]} = errors_on(changeset)
    end

    test "changeset with float votes_count is invalid" do
      attrs = %{text: "Option 1", votes_count: 3.5}
      changeset = Option.changeset(%Option{}, attrs)

      refute changeset.valid?
      assert %{votes_count: ["is invalid"]} = errors_on(changeset)
    end

    test "update existing option changeset" do
      existing_option = %Option{text: "Old Text", votes_count: 10}
      attrs = %{text: "New Text", votes_count: 20}
      changeset = Option.changeset(existing_option, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "New Text"
      assert get_change(changeset, :votes_count) == 20
    end

    test "partial update changeset" do
      existing_option = %Option{text: "Old Text", votes_count: 10}
      attrs = %{text: "New Text"}
      changeset = Option.changeset(existing_option, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "New Text"
      refute get_change(changeset, :votes_count)
    end

    test "changeset with special characters in text" do
      attrs = %{text: "Option with émojis 🎉 and symbols !@#$%^&*()"}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Option with émojis 🎉 and symbols !@#$%^&*()"
    end

    test "changeset with multiline text" do
      attrs = %{text: "Line 1\nLine 2\nLine 3"}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "Line 1\nLine 2\nLine 3"
    end

    test "changeset with whitespace text" do
      attrs = %{text: "   Option with spaces   "}
      changeset = Option.changeset(%Option{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :text) == "   Option with spaces   "
    end

    test "changeset with only whitespace is invalid" do
      attrs = %{text: "   "}
      changeset = Option.changeset(%Option{}, attrs)

      # Whitespace-only text is treated as blank by validate_required
      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "empty changeset is invalid" do
      changeset = Option.changeset(%Option{}, %{})

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "schema" do
    test "has correct fields" do
      option = %Option{}

      assert Map.has_key?(option, :text)
      assert Map.has_key?(option, :votes_count)
      assert Map.has_key?(option, :poll_id)
      assert Map.has_key?(option, :inserted_at)
      assert Map.has_key?(option, :updated_at)
    end

    test "default values" do
      option = %Option{}

      assert option.votes_count == 0
      assert option.text == nil
      assert option.poll_id == nil
    end

    test "associations are defined" do
      assert %Ecto.Association.BelongsTo{} = Option.__schema__(:association, :poll)
      assert %Ecto.Association.Has{} = Option.__schema__(:association, :votes)
    end

    test "votes association has delete_all on_delete" do
      votes_assoc = Option.__schema__(:association, :votes)
      assert votes_assoc.on_delete == :delete_all
    end
  end
end