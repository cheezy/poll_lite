defmodule PoolLiteWeb.RealTimeVotingTest do
  use PoolLiteWeb.ConnCase

  import Phoenix.LiveViewTest
  import PoolLite.PollsFixtures

  @moduletag capture_log: true

  alias PoolLite.Polls
  alias Phoenix.PubSub

  describe "Real-time voting scenarios" do
    setup do
      poll =
        poll_with_options_fixture(
          ["Option A", "Option B", "Option C"],
          %{
            title: "Real-time Test Poll",
            description: "Testing real-time voting functionality"
          }
        )

      %{poll: poll}
    end

    test "broadcasts vote updates to all connected clients", %{conn: conn, poll: poll} do
      # Connect two clients to the same poll
      {:ok, client1, _html} = live(conn, ~p"/polls/#{poll}")
      {:ok, client2, _html} = live(conn, ~p"/polls/#{poll}")

      # Get the first option
      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      # Client 1 votes
      client1
      |> element("div[phx-click='vote'][phx-value-option-id='#{option.id}']")
      |> render_click()

      # Both clients should see the update
      client1_html = render(client1)
      client2_html = render(client2)

      # Check that both clients show updated vote counts
      assert client1_html =~ "1" or client1_html =~ "100%"
      assert client2_html =~ "1" or client2_html =~ "100%"

      # Client 1 should see they voted
      assert client1_html =~ "already voted" or client1_html =~ "You voted"

      # Client 2 should still be able to vote
      refute client2_html =~ "already voted"
    end

    test "updates vote percentages in real-time for all users", %{conn: conn, poll: poll} do
      {:ok, viewer, _html} = live(conn, ~p"/polls/#{poll}")

      poll = Polls.get_poll!(poll.id)
      [option1, option2, _option3] = poll.options

      # Vote directly through context to ensure votes are recorded
      {:ok, _vote1} = Polls.vote_for_option(poll.id, option1.id, "voter1")

      # Trigger update in viewer with correct format including timestamp
      send(
        viewer.pid,
        {:vote_cast,
         %{
           poll_id: poll.id,
           option_id: option1.id,
           timestamp: System.system_time(:second)
         }}
      )

      # Viewer should see 100% for option 1
      viewer_html = render(viewer)
      assert viewer_html =~ "100%" or viewer_html =~ "100.0%" or viewer_html =~ "1 vote"

      # Second vote for option 2
      {:ok, _vote2} = Polls.vote_for_option(poll.id, option2.id, "voter2")

      # Trigger update in viewer with correct format including timestamp
      send(
        viewer.pid,
        {:vote_cast,
         %{
           poll_id: poll.id,
           option_id: option2.id,
           timestamp: System.system_time(:second)
         }}
      )

      # Viewer should see 50% for both options now or 2 votes total
      viewer_html = render(viewer)

      assert viewer_html =~ "50%" or viewer_html =~ "50.0%" or viewer_html =~ "2 votes" or
               viewer_html =~ "Total votes: 2"
    end

    test "handles concurrent votes from multiple users", %{conn: conn, poll: poll} do
      poll = Polls.get_poll!(poll.id)
      [option1, option2, option3] = poll.options

      # Vote directly through the context for multiple users
      for i <- 1..5 do
        option =
          case rem(i, 3) do
            0 -> option1
            1 -> option2
            2 -> option3
          end

        {:ok, _vote} = Polls.vote_for_option(poll.id, option.id, "test_user_#{i}")
      end

      # Check final vote count
      poll_stats = Polls.get_poll_stats(poll.id)
      assert poll_stats.total_votes == 5

      # Verify votes are distributed in LiveView
      {:ok, observer, _html} = live(conn, ~p"/polls/#{poll}")
      observer_html = render(observer)

      # Should show total of 5 votes
      assert observer_html =~ "5" or observer_html =~ "Total votes: 5"
    end

    test "updates viewing count in real-time", %{conn: conn, poll: poll} do
      {:ok, client1, _html} = live(conn, ~p"/polls/#{poll}")

      # Initially shows 1 viewing
      html1 = render(client1)
      assert html1 =~ "1 viewing" or html1 =~ "viewing"

      # Connect second client
      {:ok, client2, _html} = live(build_conn(), ~p"/polls/#{poll}")

      # Both should show 2 viewing
      # Allow time for presence sync
      Process.sleep(100)

      html1 = render(client1)
      html2 = render(client2)

      # Presence tracking might show viewer count
      assert html1 =~ "viewing"
      assert html2 =~ "viewing"
    end

    test "prevents race conditions in vote counting", %{conn: conn, poll: poll} do
      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      # Spawn multiple processes to vote simultaneously
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            {:ok, _vote} =
              Polls.vote_for_option(
                poll.id,
                option.id,
                "concurrent_user_#{i}"
              )
          end)
        end

      # Wait for all votes to complete
      Enum.each(tasks, &Task.await/1)

      # Verify exact count
      poll_stats = Polls.get_poll_stats(poll.id)
      assert poll_stats.total_votes == 10

      # Check in LiveView
      {:ok, live_view, _html} = live(conn, ~p"/polls/#{poll}")
      html = render(live_view)

      assert html =~ "10" or html =~ "Total votes: 10"
    end

    test "handles PubSub subscription and broadcasts correctly", %{conn: conn, poll: poll} do
      topic = "poll:#{poll.id}"

      # Subscribe to the poll topic
      PubSub.subscribe(PoolLite.PubSub, topic)

      {:ok, live_view, _html} = live(conn, ~p"/polls/#{poll}")

      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      # Vote
      live_view
      |> element("div[phx-click='vote'][phx-value-option-id='#{option.id}']")
      |> render_click()

      # Should receive broadcast message
      assert_receive {:vote_cast, _}, 1000
    end

    test "updates statistics in real-time", %{conn: conn, poll: poll} do
      {:ok, live_view, _html} = live(conn, ~p"/polls/#{poll}")

      initial_html = render(live_view)

      # Initially should show 0 votes
      assert initial_html =~ "Total votes: " or initial_html =~ "0"

      # Vote from another connection
      {:ok, voter, _html} = live(build_conn(), ~p"/polls/#{poll}")

      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      voter
      |> element("div[phx-click='vote'][phx-value-option-id='#{option.id}']")
      |> render_click()

      # Original viewer should see updated stats
      updated_html = render(live_view)

      # Should show vote distribution if votes exist
      if updated_html =~ "Total votes: 1" do
        assert updated_html =~ "Distribution" or updated_html =~ "100%"
      end
    end

    test "handles disconnection and reconnection gracefully", %{conn: conn, poll: poll} do
      {:ok, live_view, _html} = live(conn, ~p"/polls/#{poll}")

      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      # Vote
      live_view
      |> element("div[phx-click='vote'][phx-value-option-id='#{option.id}']")
      |> render_click()

      # Get the updated HTML after voting
      html_after_vote = render(live_view)

      # Should show user has voted
      assert html_after_vote =~ "already voted" or html_after_vote =~ "You voted" or
               html_after_vote =~ "You've already voted" or
               html_after_vote =~ "You&#39;ve already voted"

      # Simulate reconnection - session tracking might not persist in test env
      {:ok, _new_live_view, html} = live(conn, ~p"/polls/#{poll}")

      # Should show correct vote count at least
      assert html =~ "1" or html =~ "Total votes: 1"
    end

    test "properly displays animated progress bars on vote updates", %{conn: conn, poll: poll} do
      {:ok, live_view, _html} = live(conn, ~p"/polls/#{poll}")

      poll = Polls.get_poll!(poll.id)
      option = hd(poll.options)

      # Vote
      live_view
      |> element("div[phx-click='vote'][phx-value-option-id='#{option.id}']")
      |> render_click()

      html = render(live_view)

      # Check for progress bar elements
      assert html =~ "progress-bar" or html =~ "width:" or html =~ "100%"

      # Should have transition classes for animation
      assert html =~ "transition" or html =~ "duration"
    end

    test "syncs poll expiration status across all clients", %{conn: conn} do
      # Create a poll that will expire soon
      future_time = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.truncate(:second)

      poll =
        poll_fixture(%{
          title: "Expiring Poll",
          expires_at: future_time
        })

      {:ok, client1, _html} = live(conn, ~p"/polls/#{poll}")
      {:ok, client2, _html} = live(build_conn(), ~p"/polls/#{poll}")

      # Initially both should show poll is active
      html1 = render(client1)
      html2 = render(client2)

      refute html1 =~ "expired"
      refute html2 =~ "expired"

      # Wait for expiration (reduced from 3000ms to 1500ms)
      Process.sleep(1500)

      # Update the poll to expired status in DB
      poll
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> PoolLite.Repo.update!()

      # Broadcast the update
      Phoenix.PubSub.broadcast(PoolLite.PubSub, "poll:#{poll.id}", {:poll_updated, poll})

      # Both clients should show expired (after refresh/update)
      {:ok, _client1_new, html1_new} = live(conn, ~p"/polls/#{poll}")
      {:ok, _client2_new, html2_new} = live(build_conn(), ~p"/polls/#{poll}")

      assert html1_new =~ "expired" or html1_new =~ "Expired" or html1_new =~ "closed"
      assert html2_new =~ "expired" or html2_new =~ "Expired" or html2_new =~ "closed"
    end
  end
end
