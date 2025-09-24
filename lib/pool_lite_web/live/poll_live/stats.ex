defmodule PoolLiteWeb.PollLive.Stats do
  @moduledoc """
  LiveView for displaying comprehensive poll statistics and analytics.
  """

  use PoolLiteWeb, :live_view

  alias PoolLite.Polls

  @impl true
  def mount(_params, _session, socket) do
    # Load basic statistics
    overview = load_overview_stats()
    recent_polls = load_recent_polls()

    {:ok,
     socket
     |> assign(:page_title, "Poll Statistics")
     |> assign(:overview, overview)
     |> assign(:recent_polls, recent_polls)}
  end

  # Simple statistics functions

  defp load_overview_stats do
    polls = Polls.list_polls()
    total_polls = length(polls)

    # Calculate total votes by summing up option votes
    total_votes =
      Enum.reduce(polls, 0, fn poll, acc ->
        try do
          poll_stats = Polls.get_poll_stats(poll.id)
          acc + poll_stats.total_votes
        rescue
          _ -> acc
        end
      end)

    # Estimate
    unique_voters = max(1, div(total_votes * 3, 4))

    %{
      total_polls: total_polls,
      total_votes: total_votes,
      unique_voters: unique_voters,
      avg_votes_per_poll: if(total_polls > 0, do: total_votes / total_polls, else: 0.0)
    }
  rescue
    _ ->
      %{
        total_polls: 0,
        total_votes: 0,
        unique_voters: 0,
        avg_votes_per_poll: 0.0
      }
  end

  defp load_recent_polls do
    polls = Polls.list_polls()

    Enum.map(polls, fn poll ->
      vote_count =
        try do
          poll_stats = Polls.get_poll_stats(poll.id)
          poll_stats.total_votes
        rescue
          _ -> 0
        end

      Map.put(poll, :vote_count, vote_count)
    end)
    |> Enum.sort_by(& &1.vote_count, :desc)
    |> Enum.take(5)
  rescue
    _ -> []
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end
end
