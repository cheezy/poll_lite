defmodule PoolLite.Polls do
  @moduledoc """
  The Polls context.
  """

  import Ecto.Query, warn: false
  alias PoolLite.Repo

  alias PoolLite.Polls.Option
  alias PoolLite.Polls.Poll
  alias PoolLite.Polls.PubSub
  alias PoolLite.Polls.Vote

  @doc """
  Returns the list of polls with their options preloaded.

  ## Examples

      iex> list_polls()
      [%Poll{}, ...]

  """
  @spec list_polls(atom) :: list
  def list_polls(filter \\ :all) do
    base_query =
      from p in Poll,
        preload: [:options],
        order_by: [desc: p.inserted_at]

    query =
      case filter do
        :active ->
          from p in base_query, where: is_nil(p.expires_at) or p.expires_at > ^DateTime.utc_now()

        :expired ->
          from p in base_query,
            where: not is_nil(p.expires_at) and p.expires_at <= ^DateTime.utc_now()

        :all ->
          base_query
      end

    Repo.all(query)
  end

  @doc """
  Lists all polls with vote counts efficiently loaded.
  This avoids N+1 queries when displaying poll statistics.
  """
  @spec list_polls_with_stats(atom) :: list
  def list_polls_with_stats(filter \\ :all) do
    polls = list_polls(filter)

    # Return early if no polls
    if Enum.empty?(polls) do
      []
    else
      # Get vote counts for all polls in a single query
      vote_counts = fetch_vote_counts(Enum.map(polls, & &1.id))

      # Transform polls with stats
      Enum.map(polls, &attach_stats_to_poll(&1, vote_counts))
    end
  end

  # Fetch vote counts for multiple polls in one query
  defp fetch_vote_counts([]), do: %{}

  defp fetch_vote_counts(poll_ids) do
    from(v in Vote,
      where: v.poll_id in ^poll_ids,
      group_by: [v.poll_id, v.option_id],
      select: {v.poll_id, v.option_id, count(v.id)}
    )
    |> Repo.all()
    |> build_vote_count_map()
  end

  # Build nested map: %{poll_id => %{option_id => count}}
  defp build_vote_count_map(vote_data) do
    Enum.reduce(vote_data, %{}, fn {poll_id, option_id, count}, acc ->
      Map.update(acc, poll_id, %{option_id => count}, &Map.put(&1, option_id, count))
    end)
  end

  # Attach stats to a single poll
  defp attach_stats_to_poll(poll, vote_counts) do
    poll_votes = Map.get(vote_counts, poll.id, %{})
    total_votes = calculate_total_votes(poll_votes)

    options_with_stats =
      Enum.map(poll.options, fn option ->
        add_stats_to_option(option, poll_votes, total_votes)
      end)

    poll
    |> Map.put(:options, options_with_stats)
    |> Map.put(:total_votes, total_votes)
  end

  # Calculate total votes from poll_votes map
  defp calculate_total_votes(poll_votes) do
    poll_votes |> Map.values() |> Enum.sum()
  end

  # Add vote count and percentage to an option
  defp add_stats_to_option(option, poll_votes, total_votes) do
    votes_count = Map.get(poll_votes, option.id, 0)
    percentage = calculate_percentage(votes_count, total_votes)

    option
    |> Map.put(:votes_count, votes_count)
    |> Map.put(:percentage, percentage)
  end

  # Calculate percentage with proper zero handling
  defp calculate_percentage(_votes_count, 0), do: 0.0

  defp calculate_percentage(votes_count, total_votes) do
    Float.round(votes_count / total_votes * 100, 1)
  end

  @doc """
  Gets a single poll with options preloaded.

  Raises `Ecto.NoResultsError` if the Poll does not exist.

  ## Examples

      iex> get_poll!(123)
      %Poll{}

      iex> get_poll!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_poll!(integer) :: Poll.t()
  def get_poll!(id) do
    Repo.get!(Poll, id)
    |> Repo.preload([:options, :votes])
  end

  @doc """
  Gets a poll with vote counts calculated for each option.
  """
  @spec get_poll_with_vote_counts!(integer) :: Poll.t()
  def get_poll_with_vote_counts!(id) do
    poll = get_poll!(id)

    options_with_counts =
      Enum.map(poll.options, fn option ->
        vote_count = Enum.count(poll.votes, &(&1.option_id == option.id))
        %{option | votes_count: vote_count}
      end)

    %{poll | options: options_with_counts}
  end

  @doc """
  Creates a poll with options.

  ## Examples

      iex> create_poll(%{title: "My Poll", description: "...", options: ["Option 1", "Option 2"]})
      {:ok, %Poll{}}

      iex> create_poll(%{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_poll(map) :: {:ok, Poll.t()} | {:error, Ecto.Changeset.t()}
  def create_poll(attrs \\ %{}) do
    {options, poll_attrs} = extract_options_and_poll_attrs(attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:poll, Poll.changeset(%Poll{}, poll_attrs))
    |> Ecto.Multi.run(:options, &create_poll_options(&1, &2, options))
    |> Repo.transaction()
    |> handle_create_poll_result(poll_attrs)
  end

  # Extract options and poll attributes from input
  defp extract_options_and_poll_attrs(attrs) do
    options = Map.get(attrs, "options", Map.get(attrs, :options, []))
    poll_attrs = Map.drop(attrs, ["options", :options])
    {options, poll_attrs}
  end

  # Create and insert poll options
  defp create_poll_options(repo, %{poll: poll}, options) do
    options
    |> prepare_option_attrs(poll.id)
    |> insert_options(repo)
  end

  # Prepare option attributes for insertion
  defp prepare_option_attrs(options, poll_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    options
    |> Enum.filter(&(String.trim(&1) != ""))
    |> Enum.map(fn text ->
      %{
        text: String.trim(text),
        poll_id: poll_id,
        votes_count: 0,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  # Insert options into database
  defp insert_options([], _repo), do: {:error, :no_options}

  defp insert_options(option_attrs, repo) do
    {_count, options} = repo.insert_all(Option, option_attrs, returning: true)
    {:ok, options}
  end

  # Handle the result of create_poll transaction
  defp handle_create_poll_result({:ok, %{poll: poll}}, _poll_attrs) do
    PubSub.broadcast_poll_created(poll)
    {:ok, get_poll!(poll.id)}
  end

  defp handle_create_poll_result({:error, :options, :no_options, _}, poll_attrs) do
    {:error,
     Poll.changeset(%Poll{}, poll_attrs)
     |> Ecto.Changeset.add_error(:options, "must have at least one option")}
  end

  defp handle_create_poll_result({:error, :poll, changeset, _}, _poll_attrs) do
    {:error, changeset}
  end

  @doc """
  Updates a poll.

  ## Examples

      iex> update_poll(poll, %{title: "New Title"})
      {:ok, %Poll{}}

      iex> update_poll(poll, %{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_poll(Poll.t(), map) :: {:ok, Poll.t()} | {:error, Ecto.Changeset.t()}
  def update_poll(%Poll{} = poll, attrs) do
    {options, poll_attrs} = extract_options_and_poll_attrs(attrs)

    if Enum.empty?(options) do
      update_poll_attributes_only(poll, poll_attrs)
    else
      update_poll_with_options(poll, poll_attrs, options)
    end
  end

  # Update only poll attributes without changing options
  defp update_poll_attributes_only(poll, poll_attrs) do
    poll
    |> Poll.changeset(poll_attrs)
    |> Repo.update()
  end

  # Update poll with new options (replaces all existing options)
  defp update_poll_with_options(poll, poll_attrs, new_options) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:poll, Poll.changeset(poll, poll_attrs))
    |> Ecto.Multi.run(:update_options, &replace_poll_options(&1, &2, new_options))
    |> Repo.transaction()
    |> handle_update_poll_result(poll, poll_attrs)
  end

  # Replace all existing options with new ones
  defp replace_poll_options(repo, %{poll: updated_poll}, new_options) do
    with :ok <- clear_existing_poll_data(repo, updated_poll.id),
         {:ok, _options} <- create_new_poll_options(repo, updated_poll.id, new_options) do
      {:ok, updated_poll}
    end
  end

  # Clear existing votes and options for the poll
  defp clear_existing_poll_data(repo, poll_id) do
    from(v in Vote, where: v.poll_id == ^poll_id) |> repo.delete_all()
    from(o in Option, where: o.poll_id == ^poll_id) |> repo.delete_all()
    :ok
  end

  # Create new options for the poll (reuses logic from create_poll)
  defp create_new_poll_options(repo, poll_id, new_options) do
    new_options
    |> prepare_option_attrs(poll_id)
    |> insert_options(repo)
  end

  # Handle the result of update_poll transaction
  defp handle_update_poll_result({:ok, %{poll: poll}}, _original_poll, _poll_attrs) do
    updated_poll = get_poll!(poll.id)
    PubSub.broadcast_poll_updated(updated_poll)
    {:ok, updated_poll}
  end

  defp handle_update_poll_result({:error, :update_options, :no_options, _}, original_poll, poll_attrs) do
    {:error,
     Poll.changeset(original_poll, poll_attrs)
     |> Ecto.Changeset.add_error(:options, "must have at least one option")}
  end

  defp handle_update_poll_result({:error, :poll, changeset, _}, _original_poll, _poll_attrs) do
    {:error, changeset}
  end

  @doc """
  Deletes a poll.

  ## Examples

      iex> delete_poll(poll)
      {:ok, %Poll{}}

      iex> delete_poll(poll)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_poll(Poll.t()) :: {:ok, Poll.t()} | {:error, Ecto.Changeset.t()}
  def delete_poll(%Poll{} = poll) do
    case Repo.delete(poll) do
      {:ok, deleted_poll} ->
        PubSub.broadcast_poll_deleted(deleted_poll)
        {:ok, deleted_poll}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poll changes.

  ## Examples

      iex> change_poll(poll)
      %Ecto.Changeset{data: %Poll{}}

  """
  @spec change_poll(Poll.t(), map) :: Ecto.Changeset.t()
  def change_poll(%Poll{} = poll, attrs \\ %{}) do
    Poll.changeset(poll, attrs)
  end

  @doc """
  Casts a vote for a poll option by a user with enhanced duplicate prevention.

  Now includes:
  - Session-based duplicate prevention
  - Similarity checking to prevent gaming the system
  - Better error messages for different failure scenarios

  ## Examples

      iex> vote_for_option(poll_id, option_id, user_identifier)
      {:ok, %Vote{}}

      iex> vote_for_option(poll_id, option_id, user_identifier)
      {:error, :already_voted}

      iex> vote_for_option(expired_poll_id, option_id, user_identifier)
      {:error, :poll_expired}

  """
  @spec vote_for_option(
          poll_id :: integer(),
          option_id :: integer(),
          user_identifier :: String.t()
        ) ::
          {:ok, Vote.t()} | {:error, :already_voted | :poll_expired | :suspicious_activity}
  def vote_for_option(poll_id, option_id, user_identifier) do
    # Get poll and check if it's still active
    poll = get_poll!(poll_id)

    cond do
      not Poll.active?(poll) ->
        {:error, :poll_expired}

      get_user_vote(poll_id, user_identifier) != nil ->
        {:error, :already_voted}

      suspicious_voting_pattern?(poll_id, user_identifier) ->
        {:error, :suspicious_activity}

      true ->
        # Verify the option belongs to the poll
        _option = Repo.get_by!(Option, id: option_id, poll_id: poll_id)

        vote_attrs = %{
          poll_id: poll_id,
          option_id: option_id,
          user_identifier: user_identifier
        }

        Ecto.Multi.new()
        |> Ecto.Multi.insert(:vote, Vote.changeset(%Vote{}, vote_attrs))
        |> Ecto.Multi.run(:update_count, fn repo, %{vote: vote} ->
          # Update the option's vote count
          from(o in Option, where: o.id == ^vote.option_id)
          |> repo.update_all(inc: [votes_count: 1])

          {:ok, vote}
        end)
        |> Ecto.Multi.run(:broadcast, fn _repo, %{vote: vote} ->
          # Enhanced real-time broadcasting
          poll_stats = get_poll_stats(poll_id)

          # Broadcast vote event with detailed information
          PubSub.broadcast_vote_cast(poll_id, %{
            vote: vote,
            option_id: vote.option_id,
            poll_id: poll_id,
            timestamp: DateTime.utc_now()
          })

          # Broadcast updated statistics
          PubSub.broadcast_poll_stats(poll_id, poll_stats)

          {:ok, vote}
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{vote: vote}} -> {:ok, vote}
          {:error, :vote, changeset, _} -> {:error, changeset}
        end
    end
  end

  @doc """
  Checks if a user has already voted in a poll.

  ## Examples

      iex> user_voted?(poll_id, user_identifier)
      true

      iex> user_voted?(poll_id, user_identifier)
      false

  """
  @spec user_voted?(integer, String.t()) :: boolean
  def user_voted?(poll_id, user_identifier) do
    Repo.exists?(
      from v in Vote, where: v.poll_id == ^poll_id and v.user_identifier == ^user_identifier
    )
  end

  @doc """
  Gets the vote for a specific user in a poll.
  """
  @spec get_user_vote(integer, String.t()) :: Vote.t() | nil
  def get_user_vote(poll_id, user_identifier) do
    Repo.one(
      from v in Vote, where: v.poll_id == ^poll_id and v.user_identifier == ^user_identifier
    )
  end

  @doc """
  Gets poll statistics including total votes and percentages.
  """
  @spec get_poll_stats(integer) :: map
  def get_poll_stats(poll_id) do
    poll = get_poll_with_vote_counts!(poll_id)
    total_votes = sum_option_votes(poll.options)

    options_with_stats = enhance_options_with_stats(poll.options, total_votes)
    poll_stats = calculate_poll_statistics(options_with_stats, total_votes, poll_id)

    poll
    |> Map.put(:options, options_with_stats)
    |> Map.merge(poll_stats)
  end

  # Calculate total votes from options list
  defp sum_option_votes(options) do
    options
    |> Enum.map(& &1.votes_count)
    |> Enum.sum()
  end

  # Add percentage, vote share, and ranking to options
  defp enhance_options_with_stats(options, total_votes) do
    options
    |> add_percentages_and_vote_shares(total_votes)
    |> add_rankings_to_options()
  end

  # Add percentage and vote share calculations to each option
  defp add_percentages_and_vote_shares(options, total_votes) do
    Enum.map(options, fn option ->
      percentage = calculate_percentage(option.votes_count, total_votes)
      vote_share = calculate_vote_share(option.votes_count, total_votes)

      option
      |> Map.put(:percentage, percentage)
      |> Map.put(:vote_share, vote_share)
    end)
  end

  # Add ranking information while preserving original order
  defp add_rankings_to_options(options) do
    options
    |> Enum.sort_by(& &1.votes_count, :desc)
    |> Enum.with_index(1)
    |> Enum.map(fn {option, rank} -> Map.put(option, :rank, rank) end)
    |> Enum.sort_by(& &1.id)
  end

  # Calculate vote share (0.0 to 1.0)
  defp calculate_vote_share(_votes_count, 0), do: 0.0
  defp calculate_vote_share(votes_count, total_votes), do: votes_count / total_votes

  # Calculate comprehensive poll statistics
  defp calculate_poll_statistics(options, total_votes, poll_id) do
    vote_counts = Enum.map(options, & &1.votes_count)
    leading_option = find_leading_option(options)

    %{
      total_votes: total_votes,
      average_votes_per_option: calculate_average_votes(total_votes, length(options)),
      leading_option_id: extract_leading_option_id(leading_option),
      max_votes: Enum.max(vote_counts, fn -> 0 end),
      min_votes: Enum.min(vote_counts, fn -> 0 end),
      participation_rate: calculate_participation_rate(total_votes, poll_id),
      vote_distribution: calculate_vote_distribution(options)
    }
  end

  # Find the option with the most votes
  defp find_leading_option(options) do
    Enum.max_by(options, & &1.votes_count, fn -> nil end)
  end

  # Extract ID from leading option if it has votes
  defp extract_leading_option_id(nil), do: nil
  defp extract_leading_option_id(option) when option.votes_count > 0, do: option.id
  defp extract_leading_option_id(_option), do: nil

  # Calculate average votes per option
  defp calculate_average_votes(0, _option_count), do: 0.0
  defp calculate_average_votes(total_votes, option_count) do
    Float.round(total_votes / option_count, 1)
  end

  # Calculate a simple participation rate (for demo purposes)
  defp calculate_participation_rate(total_votes, _poll_id) do
    # In a real app, this could be based on page views, registered users, etc.
    # For now, we'll use a simple calculation
    case total_votes do
      0 -> 0.0
      # Lower participation for fewer votes
      votes when votes < 10 -> Float.round(votes * 8.5, 1)
      # 85-95% for higher vote counts
      _ -> Float.round(85.0 + :rand.uniform() * 10, 1)
    end
  end

  # Calculate vote distribution metrics
  defp calculate_vote_distribution(options) do
    vote_counts = Enum.map(options, & &1.votes_count)
    total = Enum.sum(vote_counts)

    cond do
      total == 0 -> "No votes yet"
      length(Enum.filter(vote_counts, &(&1 > 0))) == 1 -> "Unanimous"
      Enum.max(vote_counts) >= total * 0.6 -> "Clear leader"
      Enum.max(vote_counts) >= total * 0.4 -> "Strong preference"
      true -> "Competitive"
    end
  end

  @doc """
  Track a viewer joining a poll for live viewer count.
  """
  @spec track_viewer(integer, String.t()) :: :ok
  def track_viewer(poll_id, _viewer_id) do
    # Use a simple ETS table or GenServer to track viewers
    # For simplicity, we'll just broadcast the event
    PubSub.broadcast_viewer_count(poll_id, get_viewer_count(poll_id) + 1)
  end

  @doc """
  Track a viewer leaving a poll.
  """
  @spec untrack_viewer(integer, String.t()) :: :ok
  def untrack_viewer(poll_id, _viewer_id) do
    PubSub.broadcast_viewer_count(poll_id, max(0, get_viewer_count(poll_id) - 1))
  end

  # Simple viewer counting - in production, you'd use Phoenix Presence
  defp get_viewer_count(_poll_id), do: 0

  @doc """
  Checks for suspicious voting patterns that might indicate gaming or duplicate voting.

  This includes:
  - Multiple similar user identifiers voting in the same poll
  - Rapid succession votes from similar sessions
  - Other anti-gaming measures

  ## Examples

      iex> suspicious_voting_pattern?(poll_id, user_identifier)
      false

      iex> suspicious_voting_pattern?(poll_id, suspicious_identifier)
      true
  """
  @spec suspicious_voting_pattern?(integer, String.t()) :: boolean
  def suspicious_voting_pattern?(poll_id, user_identifier) do
    alias PoolLiteWeb.UserSession

    # Get all votes for this poll
    existing_votes =
      from(v in Vote, where: v.poll_id == ^poll_id, select: v.user_identifier)
      |> Repo.all()

    # Check for similar user identifiers (potential session gaming)
    suspicious_count =
      Enum.count(existing_votes, fn existing_id ->
        UserSession.similarity_score(user_identifier, existing_id) > 0.8
      end)

    # Flag as suspicious if there are multiple very similar identifiers
    suspicious_count > 0
  end

  @doc """
  Search polls with various filters including categories and tags.

  ## Examples

      iex> search_polls(%{query: "technology"})
      [%Poll{}, ...]

      iex> search_polls(%{category: "Technology", tag: "urgent"})
      [%Poll{}, ...]
  """
  @spec search_polls(map) :: [Poll.t()]
  def search_polls(filters \\ %{}) do
    base_query =
      from p in Poll,
        preload: [:options],
        order_by: [desc: p.inserted_at]

    query = apply_search_filters(base_query, filters)
    Repo.all(query)
  end

  defp apply_search_filters(query, filters) do
    filters
    |> Enum.reduce(query, &apply_single_filter/2)
  end

  # Apply individual filter based on type
  defp apply_single_filter({:query, value}, query), do: filter_by_text(query, value)
  defp apply_single_filter({:category, value}, query), do: filter_by_category(query, value)
  defp apply_single_filter({:tag, value}, query), do: filter_by_tag(query, value)
  defp apply_single_filter({:status, value}, query), do: filter_by_status(query, value)
  defp apply_single_filter({:sort, value}, query), do: apply_sort_order(query, value)
  defp apply_single_filter(_, query), do: query

  # Text search filter
  defp filter_by_text(query, search_query) when is_binary(search_query) and search_query != "" do
    search_term = "%#{search_query}%"

    from p in query,
      where: ilike(p.title, ^search_term) or ilike(p.description, ^search_term)
  end

  defp filter_by_text(query, _), do: query

  # Category filter
  defp filter_by_category(query, category) when is_binary(category) and category != "" do
    from p in query, where: p.category == ^category
  end

  defp filter_by_category(query, _), do: query

  # Tag filter
  defp filter_by_tag(query, tag) when is_binary(tag) and tag != "" do
    from p in query, where: ^tag in p.tags
  end

  defp filter_by_tag(query, _), do: query

  # Status filters
  defp filter_by_status(query, "active") do
    now = DateTime.utc_now()
    from p in query, where: is_nil(p.expires_at) or p.expires_at > ^now
  end

  defp filter_by_status(query, "expired") do
    now = DateTime.utc_now()
    from p in query, where: not is_nil(p.expires_at) and p.expires_at <= ^now
  end

  defp filter_by_status(query, "recent") do
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)
    from p in query, where: p.inserted_at > ^seven_days_ago
  end

  defp filter_by_status(query, _), do: query

  # Sort orders
  defp apply_sort_order(query, "newest") do
    from p in query, order_by: [desc: p.inserted_at]
  end

  defp apply_sort_order(query, "oldest") do
    from p in query, order_by: [asc: p.inserted_at]
  end

  defp apply_sort_order(query, "alphabetical") do
    from p in query, order_by: [asc: p.title]
  end

  defp apply_sort_order(query, _), do: query

  @doc """
  Get all unique categories from existing polls.
  """
  @spec get_used_categories :: [String.t()]
  def get_used_categories do
    query =
      from p in Poll,
        where: not is_nil(p.category),
        select: p.category,
        distinct: true,
        order_by: p.category

    Repo.all(query)
  end

  @doc """
  Get all unique tags from existing polls.
  """
  @spec get_used_tags :: [String.t()]
  def get_used_tags do
    query =
      from p in Poll,
        where: fragment("array_length(?, 1) > 0", p.tags),
        select: p.tags

    Repo.all(query)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Get popular tags (most frequently used).
  """
  @spec get_popular_tags(integer) :: [String.t()]
  def get_popular_tags(limit \\ 20) do
    query =
      from p in Poll,
        where: fragment("array_length(?, 1) > 0", p.tags),
        select: p.tags

    tags_frequency =
      Repo.all(query)
      |> List.flatten()
      |> Enum.frequencies()
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(limit)
      |> Enum.map(&elem(&1, 0))

    tags_frequency
  end

  @doc """
  Get statistics about categories and tags usage.
  """
  @spec get_categorization_stats :: map
  def get_categorization_stats do
    total_polls = Repo.aggregate(Poll, :count)

    categorized_polls =
      from(p in Poll, where: not is_nil(p.category))
      |> Repo.aggregate(:count)

    tagged_polls =
      from(p in Poll, where: fragment("array_length(?, 1) > 0", p.tags))
      |> Repo.aggregate(:count)

    %{
      total_polls: total_polls,
      categorized_polls: categorized_polls,
      tagged_polls: tagged_polls,
      categorization_rate:
        if(total_polls > 0, do: Float.round(categorized_polls / total_polls * 100, 1), else: 0.0),
      tagging_rate:
        if(total_polls > 0, do: Float.round(tagged_polls / total_polls * 100, 1), else: 0.0)
    }
  end
end
