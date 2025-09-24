defmodule PoolLite.PollsFixtures do
  @moduledoc """
  This module defines test fixtures for the Polls context.
  """

  alias PoolLite.Polls

  @doc """
  Generate a poll with options.
  """
  def poll_fixture(attrs \\ %{}) do
    default_attrs = %{
      title: "What's your favorite color?",
      description: "Please choose your favorite color from the options below.",
      options: ["Red", "Blue", "Green", "Yellow"]
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, poll} = Polls.create_poll(attrs)
    # Preload associations to avoid NotLoaded errors
    Polls.get_poll!(poll.id)
  end

  @doc """
  Generate a poll with custom options.
  """
  def poll_with_options_fixture(options, attrs \\ %{}) do
    default_attrs = %{
      title: "Test Poll",
      description: "This is a test poll.",
      options: options
    }

    attrs = Enum.into(attrs, default_attrs)

    {:ok, poll} = Polls.create_poll(attrs)
    # Preload options association to avoid NotLoaded errors
    Polls.get_poll!(poll.id)
  end

  @doc """
  Generate a vote for a poll option.
  """
  def vote_fixture(poll_id, option_id, user_identifier \\ "test_user") do
    {:ok, vote} = Polls.vote_for_option(poll_id, option_id, user_identifier)
    vote
  end
end
