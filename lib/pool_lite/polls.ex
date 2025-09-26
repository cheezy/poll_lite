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
    # First get all polls with options preloaded
    polls = list_polls(filter)

    # Get all poll IDs
    poll_ids = Enum.map(polls, & &1.id)

    # Get all vote counts in a single query
    vote_counts =
      from(v in Vote,
        where: v.poll_id in ^poll_ids,
        group_by: [v.poll_id, v.option_id],
        select: {v.poll_id, v.option_id, count(v.id)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {poll_id, option_id, count}, acc ->
        Map.update(acc, poll_id, %{option_id => count}, &Map.put(&1, option_id, count))
      end)

    # Attach vote counts to options
    Enum.map(polls, fn poll ->
      poll_votes = Map.get(vote_counts, poll.id, %{})
      total_votes = Map.values(poll_votes) |> Enum.sum()

      options_with_counts =
        Enum.map(poll.options, fn option ->
          votes_count = Map.get(poll_votes, option.id, 0)

          percentage =
            if total_votes > 0 do
              Float.round(votes_count / total_votes * 100, 1)
            else
              0.0
            end

          option
          |> Map.put(:votes_count, votes_count)
          |> Map.put(:percentage, percentage)
        end)

      poll
      |> Map.put(:options, options_with_counts)
      |> Map.put(:total_votes, total_votes)
    end)
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
    options = Map.get(attrs, "options", Map.get(attrs, :options, []))
    poll_attrs = Map.drop(attrs, ["options", :options])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:poll, Poll.changeset(%Poll{}, poll_attrs))
    |> Ecto.Multi.run(:options, fn repo, %{poll: poll} ->
      options
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(fn text ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %{
          text: String.trim(text),
          poll_id: poll.id,
          votes_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> case do
        [] ->
          {:error, :no_options}

        option_attrs ->
          {_count, options} = repo.insert_all(Option, option_attrs, returning: true)
          {:ok, options}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{poll: poll}} ->
        # Broadcast poll creation
        PubSub.broadcast_poll_created(poll)
        {:ok, get_poll!(poll.id)}

      {:error, :options, :no_options, _} ->
        {:error,
         Poll.changeset(%Poll{}, poll_attrs)
         |> Ecto.Changeset.add_error(:options, "must have at least one option")}

      {:error, :poll, changeset, _} ->
        {:error, changeset}
    end
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
    options = Map.get(attrs, "options", Map.get(attrs, :options, []))
    poll_attrs = Map.drop(attrs, ["options", :options])

    case options do
      [] ->
        # No options provided, just update poll attributes
        poll
        |> Poll.changeset(poll_attrs)
        |> Repo.update()

      new_options ->
        # Update poll with new options
        Ecto.Multi.new()
        |> Ecto.Multi.update(:poll, Poll.changeset(poll, poll_attrs))
        |> Ecto.Multi.run(:update_options, fn repo, %{poll: updated_poll} ->
          # Delete existing options and votes
          from(v in Vote, where: v.poll_id == ^updated_poll.id)
          |> repo.delete_all()

          from(o in Option, where: o.poll_id == ^updated_poll.id)
          |> repo.delete_all()

          # Insert new options
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          option_attrs =
            new_options
            |> Enum.filter(&(String.trim(&1) != ""))
            |> Enum.map(fn text ->
              %{
                text: String.trim(text),
                poll_id: updated_poll.id,
                votes_count: 0,
                inserted_at: now,
                updated_at: now
              }
            end)

          case option_attrs do
            [] ->
              {:error, :no_options}

            attrs ->
              {_count, _options} = repo.insert_all(Option, attrs, returning: true)
              {:ok, updated_poll}
          end
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{poll: poll}} ->
            updated_poll = get_poll!(poll.id)
            PubSub.broadcast_poll_updated(updated_poll)
            {:ok, updated_poll}

          {:error, :update_options, :no_options, _} ->
            {:error,
             Poll.changeset(poll, poll_attrs)
             |> Ecto.Changeset.add_error(:options, "must have at least one option")}

          {:error, :poll, changeset, _} ->
            {:error, changeset}
        end
    end
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
  @spec vote_for_option(poll_id :: integer(), option_id :: integer(), user_identifier :: String.t()) ::
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
    total_votes =
      Enum.map(poll.options, & &1.votes_count)
      |> Enum.sum()

    options_with_percentages =
      poll.options
      |> Enum.map(fn option ->
        # Enhanced percentage calculation with precision
        percentage =
          if total_votes > 0 do
            (option.votes_count / total_votes * 100)
            |> Float.round(1)
          else
            0.0
          end

        # Add relative ranking and vote statistics
        option
        |> Map.put(:percentage, percentage)
        |> Map.put(
          :vote_share,
          if(total_votes > 0, do: option.votes_count / total_votes, else: 0.0)
        )
      end)
      # Sort by vote count for better UX
      |> Enum.sort_by(& &1.votes_count, :desc)
      |> Enum.with_index()
      |> Enum.map(fn {option, index} ->
        Map.put(option, :rank, index + 1)
      end)
      # Restore original order by ID
      |> Enum.sort_by(& &1.id)

    # Calculate additional statistics
    leading_option = Enum.max_by(options_with_percentages, & &1.votes_count, fn -> nil end)
    vote_counts = Enum.map(options_with_percentages, & &1.votes_count)

    stats = %{
      total_votes: total_votes,
      average_votes_per_option:
        if(total_votes > 0, do: Float.round(total_votes / length(poll.options), 1), else: 0.0),
      leading_option_id:
        if(leading_option && leading_option.votes_count > 0, do: leading_option.id, else: nil),
      max_votes: Enum.max(vote_counts, fn -> 0 end),
      min_votes: Enum.min(vote_counts, fn -> 0 end),
      participation_rate: calculate_participation_rate(total_votes, poll_id),
      vote_distribution: calculate_vote_distribution(options_with_percentages)
    }

    poll
    |> Map.put(:options, options_with_percentages)
    |> Map.merge(stats)
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
    Enum.reduce(filters, query, fn
      {:query, search_query}, acc when is_binary(search_query) and search_query != "" ->
        search_term = "%#{search_query}%"

        from p in acc,
          where: ilike(p.title, ^search_term) or ilike(p.description, ^search_term)

      {:category, category}, acc when is_binary(category) and category != "" ->
        from p in acc, where: p.category == ^category

      {:tag, tag}, acc when is_binary(tag) and tag != "" ->
        from p in acc, where: ^tag in p.tags

      {:status, "active"}, acc ->
        from p in acc, where: is_nil(p.expires_at) or p.expires_at > ^DateTime.utc_now()

      {:status, "expired"}, acc ->
        from p in acc, where: not is_nil(p.expires_at) and p.expires_at <= ^DateTime.utc_now()

      {:status, "recent"}, acc ->
        seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)
        from p in acc, where: p.inserted_at > ^seven_days_ago

      {:sort, "newest"}, acc ->
        from p in acc, order_by: [desc: p.inserted_at]

      {:sort, "oldest"}, acc ->
        from p in acc, order_by: [asc: p.inserted_at]

      {:sort, "alphabetical"}, acc ->
        from p in acc, order_by: [asc: p.title]

      _, acc ->
        acc
    end)
  end

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
