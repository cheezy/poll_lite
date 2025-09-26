defmodule PoolLiteWeb.UserSessionTest do
  use PoolLiteWeb.ConnCase

  alias PoolLite.Polls
  alias PoolLite.PollsFixtures
  alias PoolLiteWeb.UserSession

  describe "generate_user_id/0" do
    test "generates a unique user identifier" do
      id1 = UserSession.generate_user_id()
      id2 = UserSession.generate_user_id()

      assert id1 != id2
      assert String.starts_with?(id1, "user_")
      assert String.starts_with?(id2, "user_")
    end

    test "generates identifier with correct format" do
      user_id = UserSession.generate_user_id()

      # Format: user_<timestamp>_<random>
      assert Regex.match?(~r/^user_\d+_[\w\-]+$/, user_id)
    end

    test "generates identifier with sufficient length" do
      user_id = UserSession.generate_user_id()

      assert String.length(user_id) > 20
    end
  end

  describe "get_or_create_user_id/1" do
    test "creates new identifier when session is empty" do
      session = %{}
      user_id = UserSession.get_or_create_user_id(session)

      assert String.starts_with?(user_id, "user_")
      assert String.length(user_id) > 10
    end

    test "returns existing identifier from session" do
      existing_id = "user_123456_abc123"
      session = %{"user_identifier" => existing_id}

      user_id = UserSession.get_or_create_user_id(session)

      assert user_id == existing_id
    end

    test "creates new identifier when existing one is invalid" do
      session = %{"user_identifier" => ""}
      user_id = UserSession.get_or_create_user_id(session)

      assert String.starts_with?(user_id, "user_")
      assert user_id != ""
    end

    test "creates new identifier when existing one is not a string" do
      session = %{"user_identifier" => 123}
      user_id = UserSession.get_or_create_user_id(session)

      assert String.starts_with?(user_id, "user_")
      assert is_binary(user_id)
    end
  end

  describe "store_user_id/2" do
    test "stores user identifier in session", %{conn: conn} do
      user_id = "user_test_123"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserSession.store_user_id(user_id)

      assert Plug.Conn.get_session(conn, "user_identifier") == user_id
    end

    test "overwrites existing user identifier in session", %{conn: conn} do
      old_id = "user_old_123"
      new_id = "user_new_456"

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_identifier" => old_id})
        |> UserSession.store_user_id(new_id)

      assert Plug.Conn.get_session(conn, "user_identifier") == new_id
    end
  end

  describe "get_user_id/1" do
    test "retrieves user identifier from session", %{conn: conn} do
      user_id = "user_test_123"

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_identifier" => user_id})

      assert UserSession.get_user_id(conn) == user_id
    end

    test "returns nil when no identifier in session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})

      assert UserSession.get_user_id(conn) == nil
    end
  end

  describe "ensure_user_id/1" do
    test "creates and stores new identifier when none exists", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserSession.ensure_user_id()

      user_id = Plug.Conn.get_session(conn, "user_identifier")

      assert user_id != nil
      assert String.starts_with?(user_id, "user_")
    end

    test "preserves existing identifier", %{conn: conn} do
      existing_id = "user_existing_123"

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_identifier" => existing_id})
        |> UserSession.ensure_user_id()

      assert Plug.Conn.get_session(conn, "user_identifier") == existing_id
    end
  end

  describe "valid_user_id?/1" do
    test "returns true for valid user identifiers" do
      assert UserSession.valid_user_id?("user_1234567890_abc123") == true
      assert UserSession.valid_user_id?("user_9999999999_xyz789") == true
      assert UserSession.valid_user_id?(UserSession.generate_user_id()) == true
    end

    test "returns false for invalid user identifiers" do
      assert UserSession.valid_user_id?("invalid") == false
      assert UserSession.valid_user_id?("user_") == false
      assert UserSession.valid_user_id?("user_123") == false
      assert UserSession.valid_user_id?("") == false
      assert UserSession.valid_user_id?(nil) == false
      assert UserSession.valid_user_id?(123) == false
      assert UserSession.valid_user_id?(%{}) == false
    end

    test "requires minimum length" do
      # Exactly 10 characters
      short_id = "user_12345"
      # 11 characters
      long_id = "user_123456"

      assert UserSession.valid_user_id?(short_id) == false
      assert UserSession.valid_user_id?(long_id) == true
    end
  end

  describe "get_user_stats/1" do
    setup do
      # Clean up any existing polls and votes
      for poll <- Polls.list_polls(), do: Polls.delete_poll(poll)
      :ok
    end

    test "returns empty stats for user with no votes" do
      user_id = "user_no_votes_123"

      stats = UserSession.get_user_stats(user_id)

      assert stats.votes_cast == 0
      assert stats.polls_voted == 0
      assert stats.last_vote_at == nil
    end

    test "returns correct stats for user with votes" do
      user_id = "user_with_votes_123"

      # Create polls and vote
      poll1 = PollsFixtures.poll_fixture(%{title: "Poll 1"})
      poll2 = PollsFixtures.poll_fixture(%{title: "Poll 2"})

      # Vote in first poll
      option1 = List.first(poll1.options)
      {:ok, _vote1} = Polls.vote_for_option(poll1.id, option1.id, user_id)

      # Vote in second poll
      option2 = List.first(poll2.options)
      {:ok, _vote2} = Polls.vote_for_option(poll2.id, option2.id, user_id)

      stats = UserSession.get_user_stats(user_id)

      assert stats.votes_cast == 2
      assert stats.polls_voted == 2
      assert stats.last_vote_at != nil

      # Verify last_vote_at is recent (within last minute)
      time_diff = DateTime.diff(DateTime.utc_now(), stats.last_vote_at)
      assert time_diff < 60
    end

    test "counts distinct polls when user votes multiple times in same poll" do
      user_id = "user_multiple_votes_123"

      # Create poll with multiple options
      poll =
        PollsFixtures.poll_fixture(%{
          title: "Multi-option Poll",
          options: ["Option A", "Option B", "Option C"]
        })

      # Vote for first option
      option1 = Enum.at(poll.options, 0)
      {:ok, _} = Polls.vote_for_option(poll.id, option1.id, user_id)

      # Try to vote for second option (returns error as already voted)
      option2 = Enum.at(poll.options, 1)
      result = Polls.vote_for_option(poll.id, option2.id, user_id)

      # The system prevents multiple votes in the same poll
      assert {:error, :already_voted} = result

      stats = UserSession.get_user_stats(user_id)

      # Should only count as 1 poll voted (second vote was rejected)
      assert stats.polls_voted == 1
      assert stats.votes_cast == 1
    end
  end

  describe "similarity_score/2" do
    test "returns high score for identifiers created within 1 minute" do
      # Generate timestamps within 30 seconds
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      id1 = "user_#{timestamp}_abc123"
      id2 = "user_#{timestamp + 30}_def456"

      score = UserSession.similarity_score(id1, id2)

      assert score == 0.9
    end

    test "returns medium-high score for identifiers created within 5 minutes" do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      id1 = "user_#{timestamp}_abc123"
      # 3 minutes later
      id2 = "user_#{timestamp + 180}_def456"

      score = UserSession.similarity_score(id1, id2)

      assert score == 0.7
    end

    test "returns medium score for identifiers created within 1 hour" do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      id1 = "user_#{timestamp}_abc123"
      # 30 minutes later
      id2 = "user_#{timestamp + 1800}_def456"

      score = UserSession.similarity_score(id1, id2)

      assert score == 0.5
    end

    test "returns low score for identifiers created far apart" do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      id1 = "user_#{timestamp}_abc123"
      # 2 hours later
      id2 = "user_#{timestamp + 7200}_def456"

      score = UserSession.similarity_score(id1, id2)

      assert score == 0.1
    end

    test "returns 0.0 for invalid identifiers" do
      assert UserSession.similarity_score("invalid1", "invalid2") == 0.0
      assert UserSession.similarity_score("user_abc_123", "user_def_456") == 0.0
      assert UserSession.similarity_score("", "") == 0.0
    end

    test "handles identifiers with same timestamp" do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      id1 = "user_#{timestamp}_abc123"
      id2 = "user_#{timestamp}_def456"

      score = UserSession.similarity_score(id1, id2)

      # Same timestamp = within 1 minute
      assert score == 0.9
    end
  end

  describe "integration with Phoenix conn" do
    test "full flow: ensure, store, and retrieve user ID", %{conn: conn} do
      # Start with no session
      conn = Plug.Test.init_test_session(conn, %{})

      # Ensure user ID (should create new one)
      conn = UserSession.ensure_user_id(conn)
      user_id1 = UserSession.get_user_id(conn)

      assert user_id1 != nil
      assert UserSession.valid_user_id?(user_id1)

      # Ensure again (should keep existing)
      conn = UserSession.ensure_user_id(conn)
      user_id2 = UserSession.get_user_id(conn)

      assert user_id2 == user_id1

      # Manually store a new ID
      new_id = UserSession.generate_user_id()
      conn = UserSession.store_user_id(conn, new_id)
      user_id3 = UserSession.get_user_id(conn)

      assert user_id3 == new_id
      assert user_id3 != user_id1
    end

    test "session persists across requests", %{conn: conn} do
      # First request - create user ID
      conn1 =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserSession.ensure_user_id()

      user_id = UserSession.get_user_id(conn1)
      session = Plug.Conn.get_session(conn1)

      # Second request - simulate new conn with same session
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(session)

      assert UserSession.get_user_id(conn2) == user_id
    end
  end

  describe "timestamp extraction" do
    test "correctly identifies similar sessions based on timing" do
      # Create two IDs 2 seconds apart
      id1 = UserSession.generate_user_id()
      Process.sleep(2000)
      id2 = UserSession.generate_user_id()

      score = UserSession.similarity_score(id1, id2)

      # Should be within 1 minute, so score should be 0.9
      assert score == 0.9
    end
  end
end
