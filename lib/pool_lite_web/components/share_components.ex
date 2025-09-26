defmodule PoolLiteWeb.Components.ShareComponents do
  @moduledoc """
  Sharing components for polls and other content.

  Provides components for:
  - Social media sharing
  - Link copying
  - QR code generation
  - Email sharing
  """

  use Phoenix.Component
  use PoolLiteWeb, :html

  @doc """
  Renders a comprehensive sharing widget for polls.

  ## Examples

      <.poll_share_widget poll={@poll} url={@current_url} />
  """
  attr :poll, :map, required: true
  attr :url, :string, required: true
  attr :class, :string, default: ""

  @spec poll_share_widget(assigns :: keyword()) :: Phoenix.Component.component()
  def poll_share_widget(assigns) do
    ~H"""
    <div class={["bg-white rounded-lg border border-gray-200 p-4", @class]}>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-gray-900 flex items-center">
          <.icon name="hero-share" class="w-5 h-5 mr-2 text-blue-600" /> Share This Poll
        </h3>
        <button
          phx-click="close-share"
          class="text-gray-400 hover:text-gray-600 transition-colors duration-200"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>
      
    <!-- Quick Copy Section -->
      <div class="mb-6">
        <label class="block text-sm font-medium text-gray-700 mb-2">Poll Link</label>
        <div class="flex items-center space-x-2">
          <input
            type="text"
            value={@url}
            readonly
            id="poll-share-url"
            class="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
          <button
            id="copy-poll-url-btn"
            phx-hook="CopyToClipboard"
            data-url={@url}
            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium rounded-lg transition-colors duration-200 flex items-center space-x-1"
          >
            <.icon name="hero-clipboard" class="w-4 h-4" />
            <span>Copy</span>
          </button>
        </div>
      </div>
      
    <!-- Social Media Sharing -->
      <div class="mb-6">
        <h4 class="text-sm font-medium text-gray-700 mb-3">Share on Social Media</h4>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <.social_share_button
            platform="twitter"
            url={@url}
            title={@poll.title}
            description="Vote in this poll: #{@poll.description}"
          />
          <.social_share_button
            platform="facebook"
            url={@url}
            title={@poll.title}
            description="Vote in this poll: #{@poll.description}"
          />
          <.social_share_button
            platform="linkedin"
            url={@url}
            title={@poll.title}
            description="Vote in this poll: #{@poll.description}"
          />
          <.social_share_button
            platform="whatsapp"
            url={@url}
            title={@poll.title}
            description="Vote in this poll"
          />
        </div>
      </div>
      
    <!-- Email Sharing -->
      <div class="mb-6">
        <h4 class="text-sm font-medium text-gray-700 mb-3">Share via Email</h4>
        <button
          phx-click="share-email"
          phx-value-url={@url}
          phx-value-title={@poll.title}
          phx-value-description={@poll.description}
          class="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors duration-200"
        >
          <.icon name="hero-envelope" class="w-5 h-5 mr-2 text-gray-600" />
          <span class="text-gray-700">Open Email Client</span>
        </button>
      </div>
      
    <!-- QR Code Section -->
      <div class="text-center">
        <h4 class="text-sm font-medium text-gray-700 mb-3">QR Code</h4>
        <div class="inline-block p-3 bg-gray-100 rounded-lg">
          <div class="w-32 h-32 flex items-center justify-center bg-white rounded border overflow-hidden">
            <img
              src={"https://api.qrserver.com/v1/create-qr-code/?size=128x128&data=#{URI.encode(@url)}&bgcolor=ffffff&color=000000"}
              alt="QR Code for poll"
              class="w-full h-full object-contain"
              onError="this.style.display='none'; this.nextElementSibling.style.display='flex'"
            />
            <div class="hidden w-full h-full flex-col items-center justify-center text-gray-400 text-xs text-center">
              <.icon name="hero-qr-code" class="w-8 h-8 mx-auto mb-1" /> QR Code
            </div>
          </div>
        </div>
        <p class="text-xs text-gray-500 mt-2">Scan to open poll</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a social media share button.
  """
  attr :platform, :string, required: true
  attr :url, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  @spec social_share_button(assigns :: keyword()) :: Phoenix.Component.component()
  def social_share_button(assigns) do
    assigns =
      assign(
        assigns,
        :share_url,
        build_share_url(assigns.platform, assigns.url, assigns.title, assigns.description)
      )

    assigns = assign(assigns, :platform_config, get_platform_config(assigns.platform))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      class={[
        "flex items-center justify-center px-3 py-2 rounded-lg transition-all duration-200 hover:scale-105 hover:shadow-md",
        @platform_config.class
      ]}
    >
      <div class="w-5 h-5 mr-2">
        {Phoenix.HTML.raw(@platform_config.icon)}
      </div>
      <span class="text-sm font-medium">{@platform_config.name}</span>
    </a>
    """
  end

  @doc """
  Renders a compact share button for quick access.
  """
  attr :poll, :map, required: true
  attr :url, :string, required: true
  attr :class, :string, default: ""

  @spec share_button(assigns :: keyword()) :: Phoenix.Component.component()
  def share_button(assigns) do
    ~H"""
    <button
      phx-click="toggle-share"
      class={[
        "inline-flex items-center px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium rounded-lg transition-colors duration-200",
        @class
      ]}
    >
      <.icon name="hero-share" class="w-5 h-5 mr-2" /> Share Poll
    </button>
    """
  end

  # Helper function to build social media share URLs
  defp build_share_url("twitter", url, title, description) do
    safe_title = title || "Poll"
    safe_description = description || "Vote now"
    safe_url = url || ""
    text = URI.encode("#{safe_title} - #{safe_description}")
    "https://twitter.com/intent/tweet?text=#{text}&url=#{URI.encode(safe_url)}"
  end

  defp build_share_url("facebook", url, _title, _description) do
    safe_url = url || ""
    "https://www.facebook.com/sharer/sharer.php?u=#{URI.encode(safe_url)}"
  end

  defp build_share_url("linkedin", url, title, description) do
    safe_url = url || ""
    safe_title = title || "Poll"
    safe_description = description || "Vote now"
    encoded_url = URI.encode(safe_url)
    encoded_title = URI.encode(safe_title)
    encoded_description = URI.encode(safe_description)

    "https://www.linkedin.com/sharing/share-offsite/?url=#{encoded_url}&title=#{encoded_title}&summary=#{encoded_description}"
  end

  defp build_share_url("whatsapp", url, title, _description) do
    safe_title = title || "Poll"
    safe_url = url || ""
    text = URI.encode("#{safe_title} - #{safe_url}")
    "https://wa.me/?text=#{text}"
  end

  # Platform configuration for styling and icons
  defp get_platform_config("twitter") do
    %{
      name: "Twitter",
      class: "bg-blue-500 hover:bg-blue-600 text-white",
      icon: """
      <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
      </svg>
      """
    }
  end

  defp get_platform_config("facebook") do
    %{
      name: "Facebook",
      class: "bg-blue-600 hover:bg-blue-700 text-white",
      icon: """
      <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
        <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
      </svg>
      """
    }
  end

  defp get_platform_config("linkedin") do
    %{
      name: "LinkedIn",
      class: "bg-blue-700 hover:bg-blue-800 text-white",
      icon: """
      <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
        <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/>
      </svg>
      """
    }
  end

  defp get_platform_config("whatsapp") do
    %{
      name: "WhatsApp",
      class: "bg-green-500 hover:bg-green-600 text-white",
      icon: """
      <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
        <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.890-5.335 11.893-11.893A11.821 11.821 0 0020.525 3.488"/>
      </svg>
      """
    }
  end
end
