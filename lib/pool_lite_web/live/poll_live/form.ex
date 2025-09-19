defmodule PoolLiteWeb.PollLive.Form do
  use PoolLiteWeb, :live_view

  alias PoolLite.Polls
  alias PoolLite.Polls.{Poll, PubSub}

  @impl true
  def mount(params, _session, socket) do
    # Subscribe to polls updates for real-time form notifications
    PubSub.subscribe_to_polls()

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:form_activity_count, 0)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    poll = Polls.get_poll!(id)
    options = Enum.map(poll.options, & &1.text)
    has_expiration = poll.expires_at != nil
    current_tags = poll.tags || []

    socket
    |> assign(:page_title, "Edit Poll")
    |> assign(:poll, poll)
    |> assign(:form, to_form(Polls.change_poll(poll)))
    |> assign(:options, options)
    |> assign(:has_expiration, has_expiration)
    |> assign(:available_categories, Poll.available_categories())
    |> assign(:current_tags, current_tags)
    |> assign(:suggested_tags, get_filtered_suggested_tags(current_tags))
  end

  defp apply_action(socket, :new, _params) do
    poll = %Poll{}
    # Start with 2 empty options
    options = ["", ""]
    current_tags = []

    socket
    |> assign(:page_title, "New Poll")
    |> assign(:poll, poll)
    |> assign(:form, to_form(Polls.change_poll(poll)))
    |> assign(:options, options)
    |> assign(:has_expiration, false)
    |> assign(:available_categories, Poll.available_categories())
    |> assign(:current_tags, current_tags)
    |> assign(:suggested_tags, get_filtered_suggested_tags(current_tags))
  end

  @impl true
  def handle_event("validate", %{"poll" => poll_params} = params, socket) do
    # Extract options from form data
    options = extract_options(params)

    # Handle tags from form submission
    tags =
      case poll_params["tags"] do
        nil ->
          socket.assigns.current_tags

        "" ->
          []

        tags_string ->
          tags_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.uniq()
      end

    poll_params_with_tags = Map.put(poll_params, "tags", tags)
    changeset = Polls.change_poll(socket.assigns.poll, poll_params_with_tags)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:options, options)
     |> assign(:current_tags, tags)
     |> assign(:suggested_tags, get_filtered_suggested_tags(tags))}
  end

  def handle_event("add_option", _params, socket) do
    options = socket.assigns.options ++ [""]
    # Limit to 10 options
    options = if length(options) <= 10, do: options, else: socket.assigns.options

    {:noreply, assign(socket, :options, options)}
  end

  def handle_event("remove_option", %{"index" => index}, socket) do
    index = String.to_integer(index)
    options = List.delete_at(socket.assigns.options, index)
    # Keep minimum 2 options
    options = if length(options) >= 2, do: options, else: socket.assigns.options

    {:noreply, assign(socket, :options, options)}
  end

  def handle_event("save", %{"poll" => poll_params} = params, socket) do
    options = extract_options(params)

    # Debug logging
    if Application.get_env(:pool_lite, :environment) == :test do
      IO.puts("params: #{inspect(params)}")
      IO.puts("options: #{inspect(options)}")
      IO.puts("socket.assigns: #{inspect(socket.assigns)}")
    end

    # Handle expiration date
    poll_params_with_expiration =
      if socket.assigns.has_expiration do
        poll_params
      else
        Map.put(poll_params, "expires_at", nil)
      end

    # Add current tags to poll params
    poll_params_with_tags =
      Map.put(poll_params_with_expiration, "tags", socket.assigns.current_tags)

    poll_params_final = Map.put(poll_params_with_tags, "options", options)

    # Debug final params
    if Application.get_env(:pool_lite, :environment) == :test do
      IO.puts("poll_params_with_expiration: #{inspect(poll_params_with_expiration)}")
      IO.puts("poll_params_with_tags: #{inspect(poll_params_with_tags)}")
      IO.puts("poll_params_final: #{inspect(poll_params_final)}")
    end

    save_poll(socket, socket.assigns.live_action, poll_params_final)
  end

  # Handle expiration toggle
  def handle_event("toggle_expiration", _params, socket) do
    {:noreply, assign(socket, :has_expiration, not socket.assigns.has_expiration)}
  end

  # Handle quick expiration setting
  def handle_event("set_quick_expiration", %{"hours" => hours}, socket) do
    hours_int = String.to_integer(hours)
    expires_at = DateTime.utc_now() |> DateTime.add(hours_int * 3600, :second)

    # Update the form with the new expiration date
    updated_poll = %{socket.assigns.poll | expires_at: expires_at}
    form = to_form(Polls.change_poll(updated_poll, %{"expires_at" => expires_at}))

    {:noreply,
     socket
     |> assign(:has_expiration, true)
     |> assign(:form, form)}
  end

  # Handle tag input (when user types in tag field)
  def handle_event("tag_input_keydown", %{"key" => "Enter", "value" => input}, socket) do
    add_tags_from_input(socket, input)
  end

  def handle_event("tag_input_keydown", %{"key" => ",", "value" => input}, socket) do
    add_tags_from_input(socket, input)
  end

  def handle_event("tag_input_keydown", _params, socket) do
    {:noreply, socket}
  end

  # Handle adding suggested tags
  def handle_event("add_suggested_tag", %{"tag" => tag}, socket) do
    current_tags = socket.assigns.current_tags

    if tag not in current_tags and length(current_tags) < 10 do
      new_tags = current_tags ++ [tag]

      {:noreply,
       socket
       |> assign(:current_tags, new_tags)
       |> assign(:suggested_tags, get_filtered_suggested_tags(new_tags))}
    else
      {:noreply, socket}
    end
  end

  # Handle removing tags
  def handle_event("remove_tag", %{"index" => index}, socket) do
    index = String.to_integer(index)
    new_tags = List.delete_at(socket.assigns.current_tags, index)

    {:noreply,
     socket
     |> assign(:current_tags, new_tags)
     |> assign(:suggested_tags, get_filtered_suggested_tags(new_tags))}
  end

  defp extract_options(params) do
    case Map.get(params, "options") do
      nil ->
        []

      options when is_map(options) ->
        options
        |> Enum.reject(fn {k, _v} -> String.starts_with?(k, "_unused_") end)
        |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
        |> Enum.map(fn {_k, v} -> String.trim(v) end)
        |> Enum.filter(&(&1 != ""))

      _ ->
        []
    end
  end

  defp save_poll(socket, :edit, poll_params) do
    case Polls.update_poll(socket.assigns.poll, poll_params) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> put_flash(:info, "Poll updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, poll))}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Preserve options on validation error
        options = Map.get(poll_params, "options", [])

        options_for_display =
          if is_list(options) && length(options) > 0 do
            options
          else
            socket.assigns.options
          end

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:options, options_for_display)}
    end
  end

  defp save_poll(socket, :new, poll_params) do
    case Polls.create_poll(poll_params) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> put_flash(:info, "Poll created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, poll))}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Preserve options on validation error
        options = Map.get(poll_params, "options", [])

        options_for_display =
          if is_list(options) && length(options) > 0 do
            options
          else
            socket.assigns.options
          end

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:options, options_for_display)}
    end
  end

  # Handle real-time notifications in the form
  @impl true
  def handle_info({:poll_created, poll}, socket) do
    {:noreply,
     socket
     |> update(:form_activity_count, &(&1 + 1))
     |> put_flash(:info, "✨ Another user just created a poll: '#{poll.title}'!")}
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    {:noreply,
     socket
     |> update(:form_activity_count, &(&1 + 1))
     |> put_flash(:info, "📝 Poll '#{poll.title}' was updated by someone else")}
  end

  @impl true
  def handle_info({:poll_vote_activity, _poll_id, _vote_data}, socket) do
    {:noreply,
     socket
     |> update(:form_activity_count, &(&1 + 1))}
  end

  # Tag helper functions
  defp add_tags_from_input(socket, input) do
    input = String.trim(input)

    if input != "" do
      new_tags =
        input
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()

      current_tags = socket.assigns.current_tags

      # Add only new tags, respecting the 10 tag limit
      unique_new_tags = new_tags -- current_tags
      final_tags = Enum.take(current_tags ++ unique_new_tags, 10)

      {:noreply,
       socket
       |> assign(:current_tags, final_tags)
       |> assign(:suggested_tags, get_filtered_suggested_tags(final_tags))}
    else
      {:noreply, socket}
    end
  end

  defp get_filtered_suggested_tags(current_tags) do
    Poll.suggested_tags()
    |> Kernel.--(current_tags)
    # Show up to 8 suggestions
    |> Enum.take(8)
  end

  defp return_path("index", _poll), do: ~p"/polls"
  defp return_path("show", poll), do: ~p"/polls/#{poll}"
  defp return_path(_, _poll), do: ~p"/polls"
end
