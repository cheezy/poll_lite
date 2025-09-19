defmodule PoolLiteWeb.PollLive.Show do
  use PoolLiteWeb, :live_view

  alias PoolLite.Polls
  alias PoolLite.Polls.PubSub
  alias PoolLiteWeb.UserSession
  alias PoolLiteWeb.Components.ShareComponents

  @impl true
  def mount(%{"id" => id}, session, socket) do
    poll = Polls.get_poll!(id)
    user_identifier = get_user_identifier(session)

    # Comprehensive PubSub subscriptions for complete real-time updates
    PubSub.subscribe_to_poll(poll.id)
    PubSub.subscribe_to_poll_stats(poll.id)

    # Subscribe to general polls updates for poll management notifications
    Phoenix.PubSub.subscribe(PoolLite.PubSub, "polls:all")

    # Subscribe to activity updates for this specific poll
    Phoenix.PubSub.subscribe(PoolLite.PubSub, "polls:activity")

    # Track viewer (simplified version)
    Polls.track_viewer(poll.id, user_identifier)

    # Get initial poll stats and user vote status
    poll_stats = Polls.get_poll_stats(poll.id)
    user_vote = Polls.get_user_vote(poll.id, user_identifier)
    user_voted? = user_vote != nil
    user_stats = UserSession.get_user_stats(user_identifier)

    # Get current URL for sharing
    current_url = get_current_url(poll.id)

    {:ok,
     socket
     |> assign(:page_title, poll.title)
     |> assign(:poll, poll)
     |> assign(:poll_stats, poll_stats)
     |> assign(:user_identifier, user_identifier)
     |> assign(:user_vote, user_vote)
     |> assign(:user_voted?, user_voted?)
     |> assign(:user_stats, user_stats)
     |> assign(:viewer_count, 1)
     |> assign(:live_updates_count, 0)
     |> assign(:current_url, current_url)
     |> assign(:show_share_widget, false)}
  end

  @impl true
  def handle_event("vote", %{"option-id" => option_id}, socket) do
    %{poll: poll, user_identifier: user_identifier} = socket.assigns

    case Polls.vote_for_option(poll.id, String.to_integer(option_id), user_identifier) do
      {:ok, vote} ->
        # Update local state
        poll_stats = Polls.get_poll_stats(poll.id)

        {:noreply,
         socket
         |> assign(:poll_stats, poll_stats)
         |> assign(:user_vote, vote)
         |> assign(:user_voted?, true)
         |> put_flash(:info, "Vote cast successfully!")}

      {:error, :poll_expired} ->
        {:noreply,
         put_flash(socket, :error, "This poll has expired and is no longer accepting votes.")}

      {:error, :already_voted} ->
        {:noreply, put_flash(socket, :error, "You have already voted in this poll.")}

      {:error, :suspicious_activity} ->
        {:noreply,
         put_flash(socket, :error, "Suspicious voting activity detected. Please try again later.")}

      {:error, changeset} ->
        error_message =
          case changeset.errors do
            [{:poll_id, {"has already been taken", _}}] -> "You have already voted in this poll."
            _ -> "Unable to cast vote. Please try again."
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  @impl true
  def handle_event("toggle-share", _params, socket) do
    {:noreply, assign(socket, :show_share_widget, not socket.assigns.show_share_widget)}
  end

  @impl true
  def handle_event("close-share", _params, socket) do
    {:noreply, assign(socket, :show_share_widget, false)}
  end

  @impl true
  def handle_event("share-email", params, socket) do
    %{"url" => url, "title" => title, "description" => description} = params

    # Create email content
    subject = "Check out this poll: #{title}"
    body = "#{description}\n\nVote here: #{url}"

    # Create mailto URL
    mailto_url = "mailto:?subject=#{URI.encode(subject)}&body=#{URI.encode(body)}"

    # Send JavaScript command to open email client
    {:noreply, push_event(socket, "open-url", %{url: mailto_url})}
  end

  @impl true
  def handle_info({:vote_cast, vote_data}, socket) do
    # Enhanced real-time vote processing
    poll_stats = Polls.get_poll_stats(socket.assigns.poll.id)
    updates_count = socket.assigns.live_updates_count + 1

    # Add visual feedback for the specific option that was voted for
    voted_option_id = vote_data.option_id

    socket =
      socket
      |> assign(:poll_stats, poll_stats)
      |> assign(:live_updates_count, updates_count)
      |> assign(:last_voted_option_id, voted_option_id)
      |> push_event("vote-animation", %{
        option_id: voted_option_id,
        new_percentage: get_option_percentage(poll_stats, voted_option_id),
        timestamp: vote_data.timestamp
      })

    # Show temporary flash for live update
    Process.send_after(self(), :clear_live_update, 3000)

    {:noreply, put_flash(socket, :info, "Someone just voted! 🎉")}
  end

  @impl true
  def handle_info({:poll_stats, stats}, socket) do
    # Handle direct poll statistics updates
    {:noreply, assign(socket, :poll_stats, stats)}
  end

  @impl true
  def handle_info({:poll_stats_updated, _poll_id}, socket) do
    # Refresh stats when notified of updates
    poll_stats = Polls.get_poll_stats(socket.assigns.poll.id)
    {:noreply, assign(socket, :poll_stats, poll_stats)}
  end

  @impl true
  def handle_info({:viewer_count_updated, count}, socket) do
    {:noreply, assign(socket, :viewer_count, count)}
  end

  @impl true
  def handle_info({:poll_updated, updated_poll}, socket) do
    # Handle poll updates (title, description, options changed)
    poll_stats = Polls.get_poll_stats(updated_poll.id)
    user_vote = Polls.get_user_vote(updated_poll.id, socket.assigns.user_identifier)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:poll_stats, poll_stats)
     |> assign(:user_vote, user_vote)
     |> assign(:user_voted?, user_vote != nil)
     |> put_flash(:info, "This poll has been updated by the creator.")}
  end

  @impl true
  def handle_info({:poll_deleted, _poll}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "This poll has been deleted.")
     |> push_navigate(to: ~p"/polls")}
  end

  @impl true
  def handle_info(:clear_live_update, socket) do
    {:noreply, clear_flash(socket, :info)}
  end

  # Catch-all for any unhandled PubSub messages
  @impl true
  def handle_info(msg, socket) do
    # Log unhandled messages in development
    if Application.get_env(:pool_lite, :environment) == :dev do
      IO.inspect(msg, label: "Unhandled PubSub message in Show LiveView")
    end

    {:noreply, socket}
  end

  # Handle cleanup when the LiveView process terminates
  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:poll] && socket.assigns[:user_identifier] do
      Polls.untrack_viewer(socket.assigns.poll.id, socket.assigns.user_identifier)
    end
  end

  # Helper function to get percentage for a specific option
  defp get_option_percentage(poll_stats, option_id) do
    case Enum.find(poll_stats.options, &(&1.id == option_id)) do
      %{percentage: percentage} -> percentage
      nil -> 0.0
    end
  end

  # Generate a user identifier from session using the UserSession module
  defp get_user_identifier(session) do
    UserSession.get_or_create_user_id(session)
  end

  # Get the current URL for sharing purposes
  defp get_current_url(poll_id) do
    "http://localhost:4000/polls/#{poll_id}"
  end
end
