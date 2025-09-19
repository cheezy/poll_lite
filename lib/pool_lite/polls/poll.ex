defmodule PoolLite.Polls.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  alias PoolLite.Polls.{Option, Vote}

  schema "polls" do
    field :title, :string
    field :description, :string
    field :expires_at, :utc_datetime
    field :category, :string
    field :tags, {:array, :string}, default: []

    has_many :options, Option, on_delete: :delete_all
    has_many :votes, Vote, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:title, :description, :expires_at, :category, :tags])
    |> validate_required([:title, :description])
    |> validate_length(:title, min: 3, max: 200)
    |> validate_length(:description, max: 1000)
    |> validate_category()
    |> validate_tags()
    |> validate_expiration_date()
  end

  # Custom validation for expiration date
  defp validate_expiration_date(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        changeset

      expires_at ->
        now = DateTime.utc_now()

        if DateTime.compare(expires_at, now) == :gt do
          changeset
        else
          add_error(changeset, :expires_at, "must be in the future")
        end
    end
  end

  # Custom validation for category
  defp validate_category(changeset) do
    case get_change(changeset, :category) do
      nil ->
        changeset

      category when is_binary(category) ->
        if category in available_categories() do
          changeset
        else
          add_error(changeset, :category, "is not a valid category")
        end

      _ ->
        add_error(changeset, :category, "must be a string")
    end
  end

  # Custom validation for tags
  defp validate_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        cond do
          length(tags) > 10 ->
            add_error(changeset, :tags, "cannot have more than 10 tags")

          Enum.any?(tags, &(!is_binary(&1))) ->
            add_error(changeset, :tags, "all tags must be strings")

          Enum.any?(tags, &(String.length(&1) > 50)) ->
            add_error(changeset, :tags, "tags cannot be longer than 50 characters")

          Enum.any?(tags, &(String.length(String.trim(&1)) == 0)) ->
            add_error(changeset, :tags, "tags cannot be empty")

          length(tags) != length(Enum.uniq(tags)) ->
            add_error(changeset, :tags, "tags must be unique")

          true ->
            # Clean up tags: trim whitespace and convert to lowercase
            clean_tags =
              tags |> Enum.map(&String.trim/1) |> Enum.map(&String.downcase/1) |> Enum.uniq()

            put_change(changeset, :tags, clean_tags)
        end

      _ ->
        add_error(changeset, :tags, "must be a list")
    end
  end

  # Helper function to check if a poll has expired
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) != :lt
  end

  # Helper function to check if a poll is active (not expired)
  def active?(%__MODULE__{} = poll), do: not expired?(poll)

  # Helper function to get time remaining until expiration
  def time_remaining(%__MODULE__{expires_at: nil}), do: nil

  def time_remaining(%__MODULE__{expires_at: expires_at}) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :second) do
      seconds when seconds > 0 -> seconds
      _ -> 0
    end
  end

  # Helper function to format expiration status
  def expiration_status(%__MODULE__{} = poll) do
    cond do
      poll.expires_at == nil -> :no_expiration
      expired?(poll) -> :expired
      # Less than 1 hour
      time_remaining(poll) < 3600 -> :expiring_soon
      true -> :active
    end
  end

  # Available poll categories
  def available_categories do
    [
      "General",
      "Technology",
      "Sports",
      "Entertainment",
      "Politics",
      "Education",
      "Business",
      "Health",
      "Science",
      "Travel",
      "Food",
      "Lifestyle",
      "Gaming",
      "Music",
      "Movies",
      "Books",
      "Art",
      "Photography",
      "Fashion",
      "Other"
    ]
  end

  # Get category display name with icon
  def category_display(%__MODULE__{category: nil}), do: {"📝", "General"}

  def category_display(%__MODULE__{category: category}) do
    case category do
      "Technology" -> {"💻", "Technology"}
      "Sports" -> {"⚽", "Sports"}
      "Entertainment" -> {"🎬", "Entertainment"}
      "Politics" -> {"🏛️", "Politics"}
      "Education" -> {"📚", "Education"}
      "Business" -> {"💼", "Business"}
      "Health" -> {"🏥", "Health"}
      "Science" -> {"🔬", "Science"}
      "Travel" -> {"✈️", "Travel"}
      "Food" -> {"🍕", "Food"}
      "Lifestyle" -> {"🌟", "Lifestyle"}
      "Gaming" -> {"🎮", "Gaming"}
      "Music" -> {"🎵", "Music"}
      "Movies" -> {"🎭", "Movies"}
      "Books" -> {"📖", "Books"}
      "Art" -> {"🎨", "Art"}
      "Photography" -> {"📸", "Photography"}
      "Fashion" -> {"👗", "Fashion"}
      _ -> {"📝", category || "General"}
    end
  end

  # Get formatted tags for display
  def formatted_tags(%__MODULE__{tags: nil}), do: []
  def formatted_tags(%__MODULE__{tags: tags}) when is_list(tags), do: tags
  def formatted_tags(_), do: []

  # Check if poll has a specific tag
  def has_tag?(%__MODULE__{tags: tags}, tag) when is_list(tags) do
    String.downcase(tag) in Enum.map(tags, &String.downcase/1)
  end

  def has_tag?(_, _), do: false

  # Check if poll belongs to a specific category
  def in_category?(%__MODULE__{category: category}, target_category) do
    String.downcase(category || "general") == String.downcase(target_category)
  end

  # Get popular tags from all polls (would typically be implemented in context)
  def suggested_tags do
    [
      "urgent",
      "fun",
      "quick",
      "important",
      "feedback",
      "opinion",
      "choice",
      "decision",
      "vote",
      "survey",
      "question",
      "help",
      "community",
      "discussion",
      "trending",
      "new",
      "popular",
      "hot"
    ]
  end
end
