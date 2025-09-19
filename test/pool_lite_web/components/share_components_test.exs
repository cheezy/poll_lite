defmodule PoolLiteWeb.Components.ShareComponentsTest do
  use PoolLiteWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PoolLite.PollsFixtures

  alias PoolLiteWeb.Components.ShareComponents

  describe "poll_share_widget/1" do
    test "renders share widget with poll information" do
      poll = poll_fixture(%{title: "Test Poll", description: "Test Description"})
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: url
        )

      assert html =~ "Share This Poll"
      assert html =~ "Test Poll"
      assert html =~ url
      assert html =~ "Poll Link"
      assert html =~ "Copy"
    end

    test "includes social media sharing buttons" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: url
        )

      assert html =~ "Share on Social Media"
      assert html =~ "Twitter"
      assert html =~ "Facebook"
      assert html =~ "LinkedIn"
      assert html =~ "WhatsApp"
    end

    test "includes email sharing functionality" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: url
        )

      assert html =~ "Share via Email"
      assert html =~ "Open Email Client"
      assert html =~ "phx-click=\"share-email\""
    end

    test "includes QR code section" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: url
        )

      assert html =~ "QR Code"
      assert html =~ "Scan to open poll"
      # QR code service URL
      assert html =~ "qrserver.com"
    end

    test "renders close button" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: url
        )

      assert html =~ "phx-click=\"close-share\""
      assert html =~ "hero-x-mark"
    end
  end

  describe "social_share_button/1" do
    test "renders Twitter share button correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "twitter",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Vote now"
        )

      assert html =~ "Twitter"
      assert html =~ "twitter.com/intent/tweet"
      assert html =~ "bg-blue-500"
      assert html =~ "target=\"_blank\""
    end

    test "renders Facebook share button correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "facebook",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Vote now"
        )

      assert html =~ "Facebook"
      assert html =~ "facebook.com/sharer"
      assert html =~ "bg-blue-600"
    end

    test "renders LinkedIn share button correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "linkedin",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Vote now"
        )

      assert html =~ "LinkedIn"
      assert html =~ "linkedin.com/sharing"
      assert html =~ "bg-blue-700"
    end

    test "renders WhatsApp share button correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "whatsapp",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Vote now"
        )

      assert html =~ "WhatsApp"
      assert html =~ "wa.me"
      assert html =~ "bg-green-500"
    end

    test "encodes URLs and text properly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "twitter",
          url: "http://example.com/poll with spaces",
          title: "Poll & Title",
          description: "Description with special chars <>"
        )

      # Should properly encode URLs
      # URL encoded space
      assert html =~ "%20"
    end
  end

  describe "share_button/1" do
    test "renders compact share button" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.share_button/1,
          poll: poll,
          url: url
        )

      assert html =~ "Share Poll"
      assert html =~ "phx-click=\"toggle-share\""
      assert html =~ "hero-share"
      assert html =~ "bg-gray-100"
    end

    test "applies custom CSS classes" do
      poll = poll_fixture()
      url = "http://example.com/polls/#{poll.id}"

      html =
        render_component(&ShareComponents.share_button/1,
          poll: poll,
          url: url,
          class: "custom-class"
        )

      assert html =~ "custom-class"
    end
  end

  describe "URL building functions" do
    test "builds Twitter share URL correctly" do
      # This tests the private function indirectly through the component
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "twitter",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Test Description"
        )

      assert html =~ "twitter.com/intent/tweet"
      assert html =~ "text="
      assert html =~ "url="
    end

    test "builds Facebook share URL correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "facebook",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Test Description"
        )

      assert html =~ "facebook.com/sharer/sharer.php"
      assert html =~ "u="
    end

    test "builds LinkedIn share URL correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "linkedin",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Test Description"
        )

      assert html =~ "linkedin.com/sharing/share-offsite"
      assert html =~ "url="
      assert html =~ "title="
      assert html =~ "summary="
    end

    test "builds WhatsApp share URL correctly" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "whatsapp",
          url: "http://example.com/poll",
          title: "Test Poll",
          description: "Test Description"
        )

      assert html =~ "wa.me"
      assert html =~ "text="
    end
  end

  describe "Error handling" do
    test "handles missing poll data gracefully" do
      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: %{title: nil, description: nil},
          url: "http://example.com"
        )

      # Should not crash even with missing data
      assert html =~ "Share This Poll"
    end

    test "handles invalid URLs gracefully" do
      poll = poll_fixture()

      html =
        render_component(&ShareComponents.poll_share_widget/1,
          poll: poll,
          url: "not-a-valid-url"
        )

      # Should still render without crashing
      assert html =~ "Share This Poll"
    end

    test "handles empty strings gracefully" do
      html =
        render_component(&ShareComponents.social_share_button/1,
          platform: "twitter",
          url: "",
          title: "",
          description: ""
        )

      # Should still render a functional button
      assert html =~ "Twitter"
      assert html =~ "twitter.com"
    end
  end
end
