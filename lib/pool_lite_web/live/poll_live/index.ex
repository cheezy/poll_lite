defmodule PoolLiteWeb.PollLive.Index do
  use PoolLiteWeb, :live_view

  alias PoolLite.Polls
  alias PoolLite.Polls.PubSub

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Enhanced PubSub subscriptions for comprehensive poll updates
    PubSub.subscribe_to_polls()

    # Subscribe to vote activity across all polls for live indicators
    Phoenix.PubSub.subscribe(PoolLite.PubSub, "polls:activity")

    # Start with loading state
    send(self(), :load_polls)

    {:ok,
     socket
     |> assign(:page_title, "Live Polls & Voting")
     |> assign(:polls_empty?, false)
     |> assign(:loading?, true)
     |> assign(:error_loading?, false)
     |> assign(:total_polls, 0)
     |> assign(:live_activity, [])
     |> assign(:activity_count, 0)
     |> assign(:search_query, "")
     |> assign(:current_filter, "all")
     |> assign(:current_sort, "newest")
     |> assign(:show_sort_menu, false)
     |> assign(:filtered_polls, [])
     |> assign(:filter_counts, %{all: 0, active: 0, expired: 0, recent: 0})
     |> assign(:selected_category, "")
     |> assign(:selected_tag, "")
     |> assign(:available_categories, [])
     |> assign(:available_tags, [])
     |> stream(:polls, [])}
  end

  @impl true
  def handle_event("retry_loading", _params, socket) do
    send(self(), :load_polls)

    {:noreply,
     socket
     |> assign(:loading?, true)
     |> assign(:error_loading?, false)
     |> put_flash(:info, "🔄 Retrying to load polls...")}
  end

  @impl true
  def handle_event("share-poll", params, socket) do
    %{"id" => id, "title" => title, "description" => description} = params

    # Generate the poll URL (use environment-specific URL building)
    base_url = PoolLiteWeb.Endpoint.url()
    poll_url = "#{base_url}/polls/#{id}"

    # Create sharing content
    sharing_content = %{
      title: title,
      description: description,
      url: poll_url
    }

    # Send sharing data to JavaScript for native sharing API if available
    {:noreply, push_event(socket, "share-content", sharing_content)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # Handle both string and integer id values
    poll_id =
      case id do
        id when is_binary(id) -> String.to_integer(id)
        id when is_integer(id) -> id
      end

    # Add loading state for the specific poll being deleted
    poll = Polls.get_poll!(poll_id)

    # Show loading state
    socket = assign(socket, :deleting_poll_id, poll_id)

    case Polls.delete_poll(poll) do
      {:ok, _} ->
        polls = list_polls()

        {:noreply,
         socket
         |> assign(:deleting_poll_id, nil)
         |> assign(:polls_empty?, polls == [])
         |> assign(:total_polls, length(polls))
         |> stream_delete(:polls, poll)
         |> put_flash(:info, "✅ Poll deleted successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:deleting_poll_id, nil)
         |> put_flash(:error, "❌ Failed to delete poll. Please try again.")}
    end
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:current_filter, filter)
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:current_sort, sort)
     |> assign(:show_sort_menu, false)
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_event("toggle-sort-menu", _params, socket) do
    {:noreply, assign(socket, :show_sort_menu, not socket.assigns.show_sort_menu)}
  end

  @impl true
  def handle_event("clear-filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:current_filter, "all")
     |> assign(:current_sort, "newest")
     |> assign(:show_sort_menu, false)
     |> assign(:selected_category, "")
     |> assign(:selected_tag, "")
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, category)
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    {:noreply,
     socket
     |> assign(:selected_tag, tag)
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> apply_filters_and_search()}
  end

  @impl true
  def handle_info(:load_polls, socket) do
    try do
      polls = list_polls()

      # Load category and tag data
      available_categories = Polls.get_used_categories()
      available_tags = Polls.get_popular_tags(15)

      {:noreply,
       socket
       |> assign(:loading?, false)
       |> assign(:error_loading?, false)
       |> assign(:total_polls, length(polls))
       |> assign(:available_categories, available_categories)
       |> assign(:available_tags, available_tags)
       |> apply_filters_and_search()}
    rescue
      _error ->
        {:noreply,
         socket
         |> assign(:loading?, false)
         |> assign(:error_loading?, true)
         |> put_flash(:error, "❌ Failed to load polls. Please try again.")}
    end
  end

  # Enhanced PubSub event handlers for comprehensive real-time updates

  @impl true
  def handle_info({:poll_created, poll}, socket) do
    # Real-time addition of new polls to the index
    {:noreply,
     socket
     |> assign(:polls_empty?, false)
     |> update(:total_polls, &(&1 + 1))
     |> stream_insert(:polls, poll, at: 0)
     |> put_flash(:info, "✨ A new poll '#{poll.title}' was just created!")}
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    # Real-time update of existing polls in the index
    {:noreply,
     socket
     |> stream_insert(:polls, poll)
     |> put_flash(:info, "📝 Poll '#{poll.title}' was updated")}
  end

  @impl true
  def handle_info({:poll_deleted, poll}, socket) do
    # Real-time removal of deleted polls from the index
    polls_count = socket.assigns.total_polls - 1

    {:noreply,
     socket
     |> assign(:polls_empty?, polls_count == 0)
     |> assign(:total_polls, polls_count)
     |> stream_delete(:polls, poll)
     |> put_flash(:info, "🗑️ Poll '#{poll.title}' was deleted")}
  end

  @impl true
  def handle_info({:poll_vote_activity, poll_id, vote_data}, socket) do
    # Real-time vote activity indicators with success flash
    activity = %{
      poll_id: poll_id,
      timestamp: vote_data.timestamp,
      option_id: vote_data.option_id
    }

    new_activity =
      [activity | socket.assigns.live_activity]
      # Keep only last 10 activities
      |> Enum.take(10)

    # Auto-clear activity after 5 seconds
    Process.send_after(self(), {:clear_activity, activity}, 5000)

    {:noreply,
     socket
     |> assign(:live_activity, new_activity)
     |> update(:activity_count, &(&1 + 1))
     |> push_event("poll-activity-flash", %{poll_id: poll_id})
     |> put_flash(:info, "🎉 New vote cast! Live polling in action.")}
  end

  @impl true
  def handle_info({:clear_activity, activity_to_clear}, socket) do
    # Remove old activity indicators
    updated_activity = Enum.reject(socket.assigns.live_activity, &(&1 == activity_to_clear))

    {:noreply, assign(socket, :live_activity, updated_activity)}
  end

  # Catch-all for any unhandled PubSub messages
  @impl true
  def handle_info(msg, socket) do
    # Log unhandled messages in development
    Logger.debug("Unhandled PubSub message in Index LiveView: #{inspect(msg)}")

    {:noreply, socket}
  end

  defp list_polls do
    Polls.list_polls_with_stats()
  end

  # Helper function to check if a poll has recent activity
  defp poll_has_recent_activity?(live_activity, poll_id) do
    Enum.any?(live_activity, &(&1.poll_id == poll_id))
  end

  # Apply current filters, search, and sorting to polls
  defp apply_filters_and_search(socket) do
    all_polls = get_all_polls()

    filtered_polls =
      all_polls
      |> apply_search_filter(socket.assigns.search_query)
      |> apply_category_filter(socket.assigns.selected_category)
      |> apply_tag_filter(socket.assigns.selected_tag)
      |> apply_status_filter(socket.assigns.current_filter)
      |> apply_sorting(socket.assigns.current_sort)

    socket
    |> assign(:filtered_polls, filtered_polls)
    |> assign(:filter_counts, calculate_filter_counts(all_polls))
    |> assign(:polls_empty?, filtered_polls == [])
    |> stream(:polls, filtered_polls, reset: true)
  end

  defp apply_search_filter(polls, ""), do: polls

  defp apply_search_filter(polls, search_query) do
    query = String.downcase(search_query)

    Enum.filter(polls, fn poll ->
      matches_search_query?(poll, query)
    end)
  end

  defp matches_search_query?(poll, query) do
    String.contains?(String.downcase(poll.title), query) or
      String.contains?(String.downcase(poll.description || ""), query) or
      poll_tags_match?(poll.tags, query)
  end

  defp poll_tags_match?(nil, _query), do: false

  defp poll_tags_match?(tags, query) do
    Enum.any?(tags, &String.contains?(String.downcase(&1), query))
  end

  defp apply_category_filter(polls, ""), do: polls

  defp apply_category_filter(polls, category) do
    Enum.filter(polls, fn poll -> poll.category == category end)
  end

  defp apply_tag_filter(polls, ""), do: polls

  defp apply_tag_filter(polls, selected_tag) do
    Enum.filter(polls, fn poll ->
      poll.tags && selected_tag in poll.tags
    end)
  end

  defp apply_status_filter(polls, filter) do
    case filter do
      "active" -> Enum.filter(polls, &poll_is_active?/1)
      "expired" -> Enum.filter(polls, &poll_is_expired?/1)
      "recent" -> Enum.filter(polls, &poll_is_recent?/1)
      _ -> polls
    end
  end

  defp apply_sorting(polls, sort_type) do
    case sort_type do
      "newest" -> Enum.sort_by(polls, & &1.inserted_at, {:desc, DateTime})
      "oldest" -> Enum.sort_by(polls, & &1.inserted_at, {:asc, DateTime})
      "most_votes" -> Enum.sort_by(polls, &get_poll_vote_count/1, :desc)
      "least_votes" -> Enum.sort_by(polls, &get_poll_vote_count/1, :asc)
      "alphabetical" -> Enum.sort_by(polls, & &1.title)
      _ -> polls
    end
  end

  defp calculate_filter_counts(polls) do
    %{
      all: length(polls),
      active: count_by_filter(polls, &poll_is_active?/1),
      expired: count_by_filter(polls, &poll_is_expired?/1),
      recent: count_by_filter(polls, &poll_is_recent?/1)
    }
  end

  defp count_by_filter(polls, filter_fn) do
    polls |> Enum.filter(filter_fn) |> length()
  end

  # Get all polls (cached or fresh)
  defp get_all_polls do
    try do
      Polls.list_polls_with_stats()
    rescue
      _ -> []
    end
  end

  # Check if poll is active (not expired)
  defp poll_is_active?(poll) do
    poll.expires_at == nil or DateTime.compare(DateTime.utc_now(), poll.expires_at) == :lt
  end

  # Check if poll is expired
  defp poll_is_expired?(poll) do
    poll.expires_at != nil and DateTime.compare(DateTime.utc_now(), poll.expires_at) != :lt
  end

  # Check if poll was created in the last 7 days
  defp poll_is_recent?(poll) do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
    DateTime.compare(poll.inserted_at, seven_days_ago) == :gt
  end

  # Get vote count for a poll
  defp get_poll_vote_count(poll) do
    # Vote count is now preloaded in the poll struct
    Map.get(poll, :total_votes, 0)
  end

  # Format sort option for display
  defp format_sort("newest"), do: "Newest First"
  defp format_sort("oldest"), do: "Oldest First"
  defp format_sort("most_votes"), do: "Most Votes"
  defp format_sort("least_votes"), do: "Least Votes"
  defp format_sort("alphabetical"), do: "A to Z"
  defp format_sort(sort), do: String.capitalize(sort)
end
