defmodule PoolLite.Polls.PollTest do
  use PoolLite.DataCase, async: true

  alias PoolLite.Polls.Poll

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{title: "Test Poll", description: "A test poll description"}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :title) == "Test Poll"
      assert get_change(changeset, :description) == "A test poll description"
    end

    test "valid changeset with all fields" do
      future_date = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
      attrs = %{
        title: "Test Poll",
        description: "A test poll description",
        expires_at: future_date,
        category: "Technology",
        tags: ["test", "poll"]
      }
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :title) == "Test Poll"
      assert get_change(changeset, :description) == "A test poll description"
      assert get_change(changeset, :expires_at) == future_date
      assert get_change(changeset, :category) == "Technology"
      assert get_change(changeset, :tags) == ["test", "poll"]
    end

    test "invalid changeset without required fields" do
      changeset = Poll.changeset(%Poll{}, %{})

      refute changeset.valid?
      assert %{title: ["can't be blank"], description: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset with title too short" do
      attrs = %{title: "AB", description: "Description"}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end

    test "invalid changeset with title too long" do
      long_title = String.duplicate("a", 201)
      attrs = %{title: long_title, description: "Description"}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at most 200 character(s)"]} = errors_on(changeset)
    end

    test "invalid changeset with description too long" do
      long_description = String.duplicate("a", 1001)
      attrs = %{title: "Test Poll", description: long_description}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{description: ["should be at most 1000 character(s)"]} = errors_on(changeset)
    end

    test "valid changeset with title at min and max boundaries" do
      min_title = "ABC"
      max_title = String.duplicate("a", 200)

      changeset_min = Poll.changeset(%Poll{}, %{title: min_title, description: "Desc"})
      changeset_max = Poll.changeset(%Poll{}, %{title: max_title, description: "Desc"})

      assert changeset_min.valid?
      assert changeset_max.valid?
    end

    test "valid changeset without optional fields" do
      attrs = %{title: "Test Poll", description: "Description"}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      refute get_change(changeset, :expires_at)
      refute get_change(changeset, :category)
      refute get_change(changeset, :tags)
    end
  end

  describe "expiration date validation" do
    test "valid changeset with future expiration date" do
      future_date = DateTime.utc_now() |> DateTime.add(1, :hour)
      attrs = %{title: "Test Poll", description: "Desc", expires_at: future_date}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset with past expiration date" do
      past_date = DateTime.utc_now() |> DateTime.add(-1, :hour)
      attrs = %{title: "Test Poll", description: "Desc", expires_at: past_date}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{expires_at: ["must be in the future"]} = errors_on(changeset)
    end

    test "invalid changeset with current time as expiration date" do
      now = DateTime.utc_now()
      attrs = %{title: "Test Poll", description: "Desc", expires_at: now}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{expires_at: ["must be in the future"]} = errors_on(changeset)
    end

    test "valid changeset without expiration date" do
      attrs = %{title: "Test Poll", description: "Desc"}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
    end
  end

  describe "category validation" do
    test "valid changeset with valid category" do
      for category <- Poll.available_categories() do
        attrs = %{title: "Test Poll", description: "Desc", category: category}
        changeset = Poll.changeset(%Poll{}, attrs)
        assert changeset.valid?, "Category #{category} should be valid"
      end
    end

    test "invalid changeset with invalid category" do
      attrs = %{title: "Test Poll", description: "Desc", category: "InvalidCategory"}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{category: ["is not a valid category"]} = errors_on(changeset)
    end

    test "invalid changeset with non-string category" do
      attrs = %{title: "Test Poll", description: "Desc", category: 123}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{category: ["is invalid"]} = errors_on(changeset)
    end

    test "valid changeset without category" do
      attrs = %{title: "Test Poll", description: "Desc"}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
    end
  end

  describe "tags validation" do
    test "valid changeset with valid tags" do
      attrs = %{title: "Test Poll", description: "Desc", tags: ["tag1", "tag2", "tag3"]}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :tags) == ["tag1", "tag2", "tag3"]
    end

    test "tags are cleaned and normalized" do
      attrs = %{title: "Test Poll", description: "Desc", tags: ["  Tag1  ", "TAG2", "tag3"]}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :tags) == ["tag1", "tag2", "tag3"]
    end

    test "duplicate tags are removed" do
      attrs = %{title: "Test Poll", description: "Desc", tags: ["tag1", "Tag1", "TAG1", "tag2"]}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :tags) == ["tag1", "tag2"]
    end

    test "invalid changeset with more than 10 tags" do
      tags = Enum.map(1..11, &"tag#{&1}")
      attrs = %{title: "Test Poll", description: "Desc", tags: tags}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{tags: ["cannot have more than 10 tags"]} = errors_on(changeset)
    end

    test "invalid changeset with non-string tags" do
      attrs = %{title: "Test Poll", description: "Desc", tags: ["tag1", 123, "tag3"]}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{tags: ["is invalid"]} = errors_on(changeset)
    end

    test "invalid changeset with tags longer than 50 characters" do
      long_tag = String.duplicate("a", 51)
      attrs = %{title: "Test Poll", description: "Desc", tags: ["tag1", long_tag]}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{tags: ["tags cannot be longer than 50 characters"]} = errors_on(changeset)
    end

    test "empty tags are filtered out during normalization" do
      attrs = %{title: "Test Poll", description: "Desc", tags: ["tag1", "", "  ", "tag3"]}
      changeset = Poll.changeset(%Poll{}, attrs)

      # Empty/whitespace tags are removed during normalization
      assert changeset.valid?
      assert get_change(changeset, :tags) == ["tag1", "tag3"]
    end

    test "invalid changeset with non-list tags" do
      attrs = %{title: "Test Poll", description: "Desc", tags: "not a list"}
      changeset = Poll.changeset(%Poll{}, attrs)

      refute changeset.valid?
      assert %{tags: ["is invalid"]} = errors_on(changeset)
    end

    test "valid changeset with exactly 10 tags" do
      tags = Enum.map(1..10, &"tag#{&1}")
      attrs = %{title: "Test Poll", description: "Desc", tags: tags}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with tag at max length" do
      max_tag = String.duplicate("a", 50)
      attrs = %{title: "Test Poll", description: "Desc", tags: [max_tag]}
      changeset = Poll.changeset(%Poll{}, attrs)

      assert changeset.valid?
    end
  end

  describe "expired?/1" do
    test "returns false for poll without expiration" do
      poll = %Poll{expires_at: nil}
      refute Poll.expired?(poll)
    end

    test "returns false for poll with future expiration" do
      future = DateTime.utc_now() |> DateTime.add(1, :hour)
      poll = %Poll{expires_at: future}
      refute Poll.expired?(poll)
    end

    test "returns true for poll with past expiration" do
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)
      poll = %Poll{expires_at: past}
      assert Poll.expired?(poll)
    end

    test "returns true for poll expiring now" do
      now = DateTime.utc_now()
      poll = %Poll{expires_at: now}
      assert Poll.expired?(poll)
    end
  end

  describe "active?/1" do
    test "returns true for poll without expiration" do
      poll = %Poll{expires_at: nil}
      assert Poll.active?(poll)
    end

    test "returns true for poll with future expiration" do
      future = DateTime.utc_now() |> DateTime.add(1, :hour)
      poll = %Poll{expires_at: future}
      assert Poll.active?(poll)
    end

    test "returns false for poll with past expiration" do
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)
      poll = %Poll{expires_at: past}
      refute Poll.active?(poll)
    end
  end

  describe "time_remaining/1" do
    test "returns nil for poll without expiration" do
      poll = %Poll{expires_at: nil}
      assert Poll.time_remaining(poll) == nil
    end

    test "returns positive seconds for future expiration" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second)
      poll = %Poll{expires_at: future}
      remaining = Poll.time_remaining(poll)

      assert remaining > 3595
      assert remaining <= 3600
    end

    test "returns 0 for past expiration" do
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)
      poll = %Poll{expires_at: past}
      assert Poll.time_remaining(poll) == 0
    end

    test "returns 0 for current time expiration" do
      now = DateTime.utc_now()
      poll = %Poll{expires_at: now}
      assert Poll.time_remaining(poll) == 0
    end
  end

  describe "expiration_status/1" do
    test "returns :no_expiration for poll without expiration" do
      poll = %Poll{expires_at: nil}
      assert Poll.expiration_status(poll) == :no_expiration
    end

    test "returns :expired for expired poll" do
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)
      poll = %Poll{expires_at: past}
      assert Poll.expiration_status(poll) == :expired
    end

    test "returns :expiring_soon for poll expiring within an hour" do
      soon = DateTime.utc_now() |> DateTime.add(30, :minute)
      poll = %Poll{expires_at: soon}
      assert Poll.expiration_status(poll) == :expiring_soon
    end

    test "returns :active for poll expiring after an hour" do
      future = DateTime.utc_now() |> DateTime.add(2, :hour)
      poll = %Poll{expires_at: future}
      assert Poll.expiration_status(poll) == :active
    end
  end

  describe "available_categories/0" do
    test "returns list of categories" do
      categories = Poll.available_categories()

      assert is_list(categories)
      assert "General" in categories
      assert "Technology" in categories
      assert "Sports" in categories
      assert length(categories) == 20
    end
  end

  describe "category_display/1" do
    test "returns general icon for nil category" do
      poll = %Poll{category: nil}
      assert Poll.category_display(poll) == {"📝", "General"}
    end

    test "returns correct icon and name for known categories" do
      poll = %Poll{category: "Technology"}
      assert Poll.category_display(poll) == {"💻", "Technology"}

      poll = %Poll{category: "Sports"}
      assert Poll.category_display(poll) == {"⚽", "Sports"}
    end

    test "returns default icon for unknown category" do
      poll = %Poll{category: "Unknown"}
      assert Poll.category_display(poll) == {"📝", "Unknown"}
    end
  end

  describe "formatted_tags/1" do
    test "returns empty list for nil tags" do
      poll = %Poll{tags: nil}
      assert Poll.formatted_tags(poll) == []
    end

    test "returns tags list when tags is a list" do
      tags = ["tag1", "tag2", "tag3"]
      poll = %Poll{tags: tags}
      assert Poll.formatted_tags(poll) == tags
    end

    test "returns empty list for non-list tags" do
      poll = %Poll{tags: "not a list"}
      assert Poll.formatted_tags(poll) == []
    end
  end

  describe "has_tag?/2" do
    test "returns true when tag exists (case insensitive)" do
      poll = %Poll{tags: ["tag1", "TAG2", "Tag3"]}
      assert Poll.has_tag?(poll, "tag1")
      assert Poll.has_tag?(poll, "TAG1")
      assert Poll.has_tag?(poll, "Tag2")
    end

    test "returns false when tag doesn't exist" do
      poll = %Poll{tags: ["tag1", "tag2"]}
      refute Poll.has_tag?(poll, "tag3")
    end

    test "returns false when tags is not a list" do
      poll = %Poll{tags: nil}
      refute Poll.has_tag?(poll, "tag1")

      poll = %Poll{tags: "not a list"}
      refute Poll.has_tag?(poll, "tag1")
    end
  end

  describe "in_category?/2" do
    test "returns true for matching category (case insensitive)" do
      poll = %Poll{category: "Technology"}
      assert Poll.in_category?(poll, "technology")
      assert Poll.in_category?(poll, "TECHNOLOGY")
      assert Poll.in_category?(poll, "Technology")
    end

    test "returns false for non-matching category" do
      poll = %Poll{category: "Technology"}
      refute Poll.in_category?(poll, "Sports")
    end

    test "treats nil category as 'general'" do
      poll = %Poll{category: nil}
      assert Poll.in_category?(poll, "general")
      assert Poll.in_category?(poll, "General")
    end
  end

  describe "suggested_tags/0" do
    test "returns list of suggested tags" do
      tags = Poll.suggested_tags()

      assert is_list(tags)
      assert "urgent" in tags
      assert "fun" in tags
      assert "important" in tags
    end
  end

  describe "schema" do
    test "has correct fields" do
      poll = %Poll{}

      assert Map.has_key?(poll, :title)
      assert Map.has_key?(poll, :description)
      assert Map.has_key?(poll, :expires_at)
      assert Map.has_key?(poll, :category)
      assert Map.has_key?(poll, :tags)
      assert Map.has_key?(poll, :inserted_at)
      assert Map.has_key?(poll, :updated_at)
    end

    test "has correct default values" do
      poll = %Poll{}

      assert poll.tags == []
      assert poll.title == nil
      assert poll.description == nil
      assert poll.expires_at == nil
      assert poll.category == nil
    end

    test "associations are defined" do
      assert %Ecto.Association.Has{} = Poll.__schema__(:association, :options)
      assert %Ecto.Association.Has{} = Poll.__schema__(:association, :votes)
    end

    test "associations have delete_all on_delete" do
      options_assoc = Poll.__schema__(:association, :options)
      votes_assoc = Poll.__schema__(:association, :votes)

      assert options_assoc.on_delete == :delete_all
      assert votes_assoc.on_delete == :delete_all
    end
  end
end
