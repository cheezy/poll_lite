defmodule PoolLite.Polls.PubSub do
  @moduledoc """
  PubSub utilities for real-time poll updates.
  """

  alias Phoenix.PubSub

  @pubsub PoolLite.PubSub

  # Topic patterns

  @spec poll_topic(poll_id :: integer) :: String.t()
  def poll_topic(poll_id), do: "poll:#{poll_id}"

  @spec polls_topic() :: String.t()
  def polls_topic, do: "polls:all"

  @spec poll_stats_topic(poll_id :: integer) :: String.t()
  def poll_stats_topic(poll_id), do: "poll_stats:#{poll_id}"

  @doc """
  Subscribe to all updates for a specific poll.
  """
  @spec subscribe_to_poll(poll_id :: integer) :: :ok
  def subscribe_to_poll(poll_id) do
    PubSub.subscribe(@pubsub, poll_topic(poll_id))
  end

  @doc """
  Subscribe to general polls updates (creation, deletion, etc.).
  """
  @spec subscribe_to_polls() :: :ok
  def subscribe_to_polls do
    PubSub.subscribe(@pubsub, polls_topic())
  end

  @doc """
  Subscribe to poll statistics updates.
  """
  @spec subscribe_to_poll_stats(poll_id :: integer) :: :ok
  def subscribe_to_poll_stats(poll_id) do
    PubSub.subscribe(@pubsub, poll_stats_topic(poll_id))
  end

  @doc """
  Broadcast a vote cast event for a specific poll.
  """
  @spec broadcast_vote_cast(poll_id :: integer, vote_data :: map()) :: :ok
  def broadcast_vote_cast(poll_id, vote_data) do
    # Enhanced vote broadcast with animation triggers
    PubSub.broadcast(@pubsub, poll_topic(poll_id), {:vote_cast, vote_data})
    PubSub.broadcast(@pubsub, poll_stats_topic(poll_id), {:poll_stats_updated, poll_id})

    # Broadcast to polls index for live activity indicators
    PubSub.broadcast(@pubsub, polls_topic(), {:poll_vote_activity, poll_id, vote_data})

    # Broadcast to general activity topic
    PubSub.broadcast(@pubsub, "polls:activity", {:poll_vote_activity, poll_id, vote_data})
  end

  @doc """
  Broadcast poll creation event.
  """
  @spec broadcast_poll_created(poll :: Poll.t()) :: :ok
  def broadcast_poll_created(poll) do
    PubSub.broadcast(@pubsub, polls_topic(), {:poll_created, poll})
  end

  @doc """
  Broadcast poll updated event.
  """
  @spec broadcast_poll_updated(poll :: Poll.t()) :: :ok
  def broadcast_poll_updated(poll) do
    PubSub.broadcast(@pubsub, polls_topic(), {:poll_updated, poll})
    PubSub.broadcast(@pubsub, poll_topic(poll.id), {:poll_updated, poll})
  end

  @doc """
  Broadcast poll deleted event.
  """
  @spec broadcast_poll_deleted(poll :: Poll.t()) :: :ok
  def broadcast_poll_deleted(poll) do
    PubSub.broadcast(@pubsub, polls_topic(), {:poll_deleted, poll})
    PubSub.broadcast(@pubsub, poll_topic(poll.id), {:poll_deleted, poll})
  end

  @doc """
  Broadcast live viewer count updates.
  """
  @spec broadcast_viewer_count(poll_id :: integer, count :: integer) :: :ok
  def broadcast_viewer_count(poll_id, count) do
    PubSub.broadcast(@pubsub, poll_topic(poll_id), {:viewer_count_updated, count})
  end

  @doc """
  Broadcast real-time poll statistics.
  """
  @spec broadcast_poll_stats(poll_id :: integer, stats :: map) :: :ok
  def broadcast_poll_stats(poll_id, stats) do
    PubSub.broadcast(@pubsub, poll_stats_topic(poll_id), {:poll_stats, stats})
  end
end
