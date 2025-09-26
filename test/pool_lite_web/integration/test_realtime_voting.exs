#!/usr/bin/env elixir

# Real-time voting test script
# This script simulates multiple users voting simultaneously to test real-time updates

Mix.install([:req, :jason])

defmodule RealTimeVotingTest do
  @base_url "http://localhost:4000"

  @spec run_test() :: :ok
  def run_test do
    IO.puts("🚀 Starting real-time voting simulation...")

    # Test data - poll ID and option IDs to vote for
    poll_id = 6
    # All options from poll 6
    option_ids = [17, 18, 19, 20, 21]

    # Create multiple concurrent voting sessions
    tasks =
      1..10
      |> Enum.map(fn user_id ->
        Task.async(fn ->
          simulate_user_voting(user_id, poll_id, option_ids)
        end)
      end)

    # Wait for all tasks to complete
    results = Task.await_many(tasks, 10_000)

    IO.puts("📊 Real-time voting test completed!")
    IO.puts("Results: #{inspect(results)}")
  end

  defp simulate_user_voting(user_id, poll_id, option_ids) do
    # Random delay to simulate staggered user activity
    Enum.random(100..2000)
    |> Process.sleep()

    # Select a random option to vote for
    option_id = Enum.random(option_ids)

    IO.puts("👤 User #{user_id} voting for option #{option_id}...")

    # This would normally make an HTTP request, but since we can't easily
    # simulate LiveView voting from outside, we'll use the Polls context directly
    user_identifier = "test_user_#{user_id}_#{:rand.uniform(1000)}"

    case PoolLite.Polls.vote_for_option(poll_id, option_id, user_identifier) do
      {:ok, _vote} ->
        IO.puts("✅ User #{user_id} vote cast successfully!")
        {:ok, user_id, option_id}

      {:error, _changeset} ->
        IO.puts("❌ User #{user_id} vote failed (likely duplicate)")
        {:error, user_id, option_id}
    end
  end
end

# Run the test
RealTimeVotingTest.run_test()
