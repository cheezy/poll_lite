defmodule PoolLiteWeb.UserSession do
  @moduledoc """
  Manages user session identification for voting and tracking.

  This module provides functionality to:
  - Generate unique, persistent user identifiers
  - Store and retrieve user identifiers from sessions
  - Track user voting activity across sessions
  """

  @doc """
  Gets or creates a user identifier for the current session.

  The identifier is stored in the Phoenix session and persists across
  page reloads. If no identifier exists, a new one is generated.

  ## Examples

      iex> get_or_create_user_id(session)
      "user_abc123def456"
  """
  @spec get_or_create_user_id(map()) :: String.t()
  def get_or_create_user_id(session) do
    case Map.get(session, "user_identifier") do
      nil -> generate_user_id()
      identifier when is_binary(identifier) and byte_size(identifier) > 0 -> identifier
      # Fallback for invalid identifiers
      _ -> generate_user_id()
    end
  end

  @doc """
  Generates a new unique user identifier.

  The identifier includes:
  - A timestamp component for uniqueness
  - A random component for security
  - A readable prefix for debugging

  ## Examples

      iex> generate_user_id()
      "user_20240117_abc123def"
  """
  @spec generate_user_id() :: String.t()
  def generate_user_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    "user_#{timestamp}_#{random}"
  end

  @doc """
  Stores the user identifier in the session.

  ## Examples

      iex> store_user_id(conn, "user_abc123")
      %Plug.Conn{...}
  """
  @spec store_user_id(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def store_user_id(conn, user_id) do
    Plug.Conn.put_session(conn, "user_identifier", user_id)
  end

  @doc """
  Gets user identifier from connection session.

  ## Examples

      iex> get_user_id(conn)
      "user_abc123def456"
  """
  @spec get_user_id(Plug.Conn.t()) :: String.t()
  def get_user_id(conn) do
    Plug.Conn.get_session(conn, "user_identifier")
  end

  @doc """
  Ensures a user has a valid identifier, creating one if necessary.

  This is useful as a plug or in LiveView mount functions.

  ## Examples

      iex> ensure_user_id(conn)
      %Plug.Conn{...}
  """
  @spec ensure_user_id(Plug.Conn.t()) :: Plug.Conn.t()
  def ensure_user_id(conn) do
    case get_user_id(conn) do
      nil ->
        user_id = generate_user_id()
        store_user_id(conn, user_id)

      _existing ->
        conn
    end
  end

  @doc """
  Validates a user identifier format.

  ## Examples

      iex> valid_user_id?("user_1642428123_abc123")
      true

      iex> valid_user_id?("invalid")
      false
  """
  @spec valid_user_id?(String.t()) :: boolean()
  def valid_user_id?(identifier) when is_binary(identifier) do
    String.starts_with?(identifier, "user_") and String.length(identifier) > 10
  end

  @spec valid_user_id?(any()) :: boolean()
  def valid_user_id?(_), do: false

  @doc """
  Gets user voting statistics across all polls.

  Returns information about how many polls the user has voted in,
  when they last voted, etc.

  ## Examples

      iex> get_user_stats("user_abc123")
      %{votes_cast: 5, polls_voted: 3, last_vote_at: ~U[2024-01-17 10:30:00Z]}
  """
  @spec get_user_stats(user_identifier :: String.t()) ::
          %{votes_cast: integer(), polls_voted: integer(), last_vote_at: DateTime.t()}
  def get_user_stats(user_identifier) do
    alias PoolLite.Polls.Vote
    alias PoolLite.Repo
    import Ecto.Query

    stats_query =
      from v in Vote,
        where: v.user_identifier == ^user_identifier,
        select: %{
          votes_cast: count(v.id),
          polls_voted: count(v.poll_id, :distinct),
          last_vote_at: max(v.inserted_at)
        }

    case Repo.one(stats_query) do
      %{votes_cast: nil} ->
        %{votes_cast: 0, polls_voted: 0, last_vote_at: nil}

      stats ->
        stats
    end
  end

  @doc """
  Checks if a user identifier appears to be from the same browser session.

  This can help identify potential duplicate voting attempts from the same
  device/browser, even if the session was cleared.

  Returns a similarity score from 0.0 to 1.0.
  """
  @spec similarity_score(id1 :: String.t(), id2 :: String.t()) :: float()
  def similarity_score(id1, id2) when is_binary(id1) and is_binary(id2) do
    # Simple similarity based on timing (for demo purposes)
    # In production, you might use IP address, user agent fingerprinting, etc.

    case {extract_timestamp(id1), extract_timestamp(id2)} do
      {ts1, ts2} when is_integer(ts1) and is_integer(ts2) ->
        time_diff = abs(ts1 - ts2)

        cond do
          # Within 1 minute
          time_diff < 60 -> 0.9
          # Within 5 minutes
          time_diff < 300 -> 0.7
          # Within 1 hour
          time_diff < 3600 -> 0.5
          # Different sessions
          true -> 0.1
        end

      _ ->
        0.0
    end
  end

  # Extract timestamp from user identifier
  defp extract_timestamp("user_" <> rest) do
    case String.split(rest, "_", parts: 2) do
      [timestamp_str, _random] ->
        case Integer.parse(timestamp_str) do
          {timestamp, ""} -> timestamp
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_timestamp(_), do: nil
end
