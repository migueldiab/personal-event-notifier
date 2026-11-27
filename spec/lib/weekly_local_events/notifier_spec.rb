# frozen_string_literal: true

require "spec_helper"
require "weekly_local_events/notifier"
require "weekly_local_events/event"

RSpec.describe WeeklyLocalEvents::Notifier do
  let(:config) { WeeklyLocalEvents::Config.new }
  let(:notifier) { described_class.new(config) }
  let(:bot_token) { config.telegram_bot_token }
  let(:channel_id) { config.notification_channel_id.to_s }
  let(:api_base) { "https://api.telegram.org/bot#{bot_token}" }

  # Helper to build a test event
  let(:venue) do
    WeeklyLocalEvents::Venue.new(
      name: "ACL Live",
      address: "310 W 5th St",
      city: "Austin",
      state: "TX",
      zip: "78701"
    )
  end

  let(:event) do
    WeeklyLocalEvents::Event.new(
      title: "Live Music Night",
      date: Date.today + 2,
      venue: venue,
      url: "https://example.com/event",
      source: "austin_chronicle",
      price: "15",
      category: "Music"
    )
  end

  let(:events) { [event] }

  # Helper to stub the Telegram sendMessage API
  let(:success_response) do
    JSON.generate({ "ok" => true, "result" => { "message_id" => 42 } })
  end

  let(:error_response) do
    JSON.generate({ "ok" => false, "description" => "Bad Request: message is too long" })
  end

  describe ".send_message" do
    it "sends a message via the Telegram API" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: { "chat_id" => channel_id, "text" => "Hello, world!" },
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Hello, world!")

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be true
      expect(response.message_id).to eq(42)
    end

    it "returns an error response for empty messages" do
      response = notifier.send_message("")

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be false
      expect(response.error).to eq("No message provided")
    end

    it "returns an error response for nil messages" do
      response = notifier.send_message(nil)

      expect(response.success?).to be false
      expect(response.error).to eq("No message provided")
    end

    it "sends with the correct parse_mode when specified" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: { "chat_id" => channel_id, "text" => "Bold text", "parse_mode" => "HTML" },
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Bold text", parse_mode: "HTML")

      expect(response.success?).to be true
    end

    it "sends without parse_mode when nil" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: { "chat_id" => channel_id, "text" => "Plain text" },
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Plain text", parse_mode: nil)

      expect(response.success?).to be true
    end
  end

  describe ".send_events" do
    it "formats and sends events via Telegram" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /Weekly Austin Events/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_events(events)

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be true
      expect(response.message_id).to eq(42)
    end

    it "returns error response when no events provided" do
      response = notifier.send_events([])

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be false
      expect(response.error).to eq("No events provided")
    end

    it "includes event title, venue, and price in the formatted message" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /Live Music Night/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_events(events)
    end

    it "includes a summary section in the message" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /Summary/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_events(events)
    end
  end

  describe ".format_events" do
    it "produces correct markdown with event title and venue" do
      result = notifier.format_events(events)

      expect(result).to include("📅 *Weekly Austin Events*")
      expect(result).to include("📆 *Next 7 days*")
      expect(result).to include("*Live Music Night*")
      expect(result).to include("ACL Live")
      expect(result).to include("$15")
    end

    it "returns 'No events found.' for empty events" do
      result = notifier.format_events([])

      expect(result).to eq("No events found.")
    end

    it "groups events by category with correct emoji" do
      music_event = WeeklyLocalEvents::Event.new(
        title: "Rock Concert",
        date: Date.today + 1,
        venue: venue,
        url: "https://example.com",
        source: "test",
        category: "Music"
      )

      comedy_event = WeeklyLocalEvents::Event.new(
        title: "Stand-up Show",
        date: Date.today + 3,
        venue: venue,
        url: "https://example.com",
        source: "test",
        category: "Comedy"
      )

      result = notifier.format_events([music_event, comedy_event])

      expect(result).to include("🎵 *Music*")
      expect(result).to include("🎭 *Comedy*")
      expect(result).to include("*Rock Concert*")
      expect(result).to include("*Stand-up Show*")
    end

    it "shows 'Free' for events with no price" do
      free_event = WeeklyLocalEvents::Event.new(
        title: "Free Event",
        date: Date.today + 1,
        venue: venue,
        url: "https://example.com",
        source: "test"
      )

      result = notifier.format_events([free_event])

      expect(result).to include("*Free Event*")
      expect(result).to include("Free")
    end

    it "shows 'Unknown' when venue is nil" do
      event_without_venue = WeeklyLocalEvents::Event.new(
        title: "No Venue Event",
        date: Date.today + 1,
        venue: nil,
        url: "https://example.com",
        source: "test"
      )

      result = notifier.format_events([event_without_venue])

      expect(result).to include("Unknown")
    end

    it "normalizes category names" do
      gig_event = WeeklyLocalEvents::Event.new(
        title: "Band Gig",
        date: Date.today + 1,
        venue: venue,
        url: "https://example.com",
        source: "test",
        category: "concert"
      )

      result = notifier.format_events([gig_event])

      expect(result).to include("🎵 *Music*")
    end
  end

  describe ".format_summary" do
    it "produces correct markdown summary" do
      summary = {
        total: 10,
        free_count: 4,
        paid_count: 6,
        categories: { "Music" => 5, "Comedy" => 3, "Art" => 2 },
        sources: { "austin_chronicle" => 6, "do512" => 4 }
      }

      result = notifier.format_summary(summary)

      expect(result).to include("📊 *Summary*")
      expect(result).to include("*Total events*: 10")
      expect(result).to include("*Free events*: 4")
      expect(result).to include("*Paid events*: 6")
      expect(result).to include("📂 *By Category*:")
      expect(result).to include("Music: 5")
      expect(result).to include("📡 *By Source*:")
      expect(result).to include("austin_chronicle: 6")
    end

    it "returns 'No summary available.' for nil input" do
      result = notifier.format_summary(nil)

      expect(result).to eq("No summary available.")
    end

    it "returns 'No summary available.' for non-hash input" do
      result = notifier.format_summary("not a hash")

      expect(result).to eq("No summary available.")
    end

    it "handles summary with no categories or sources" do
      summary = { total: 0, free_count: 0, paid_count: 0, categories: [], sources: [] }

      result = notifier.format_summary(summary)

      expect(result).to include("📊 *Summary*")
      expect(result).to include("*Total events*: 0")
      expect(result).not_to include("📂 *By Category*")
      expect(result).not_to include("📡 *By Source*")
    end

    it "handles hash with string keys" do
      summary = { "total" => 5, "free_count" => 2, "paid_count" => 3, "categories" => [], "sources" => [] }

      result = notifier.format_summary(summary)

      expect(result).to include("*Total events*: 5")
    end
  end

  describe ".send_with_markdown" do
    it "sends message with MarkdownV2 parse mode" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("parse_mode" => "MarkdownV2"),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_with_markdown("*Bold* and _italic_")

      expect(response.success?).to be true
    end
  end

  describe ".send_with_html" do
    it "sends message with HTML parse mode" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("parse_mode" => "HTML"),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_with_html("<b>Bold</b> and <i>italic</i>")

      expect(response.success?).to be true
    end
  end

  describe ".rate_limit_check" do
    it "returns false when under rate limit" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))

      expect(notifier.rate_limit_check).to be false
    end

    it "returns true when rate limit is reached" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))

      # Simulate hitting the rate limit by directly setting the internal state
      notifier.instance_variable_set(:@recent_message_times,
        Array.new(20) { Time.at(1_700_000_000) })

      expect(notifier.rate_limit_check).to be true
    end

    it "returns false when old messages are outside the 60-second window" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_061))

      # Set 19 times that are more than 60 seconds old (under the 20-message limit)
      notifier.instance_variable_set(:@recent_message_times,
        Array.new(19) { Time.at(1_700_000_000) })

      expect(notifier.rate_limit_check).to be false
    end
  end

  describe "message truncation at 4096 char limit" do
    it "truncates messages exceeding 4096 characters" do
      long_text = "x" * 5000

      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /truncated/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_message(long_text)
    end

    it "keeps messages under the limit unchanged" do
      short_text = "x" * 100

      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => "x" * 100),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_message(short_text)
    end

    it "includes truncation note in the truncated message" do
      long_text = "x" * 5000

      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /truncated — 5000 chars/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_message(long_text)
    end

    it "tries to break at the last newline before truncation" do
      long_text = "line1\nline2\n" + "x" * 5000

      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("text" => /line1\nline2\n/),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      notifier.send_message(long_text)
    end
  end

  describe "error handling for Telegram API failures" do
    it "returns error response on non-200 Telegram API response" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 400, body: error_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Test message")

      expect(response.success?).to be false
      expect(response.error).to eq("Bad Request: message is too long")
      expect(response.api_error).to be_a(Hash)
    end

    it "returns error for unrecognized Telegram API error" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 500, body: JSON.generate({ "ok" => false, "description" => nil }),
                   headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Test")

      expect(response.success?).to be false
      expect(response.error).to eq("Unknown Telegram API error")
    end

    it "returns success with nil message_id for malformed JSON response" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: "{ broken json", headers: { "Content-Type" => "application/json" })

      response = notifier.send_message("Test")

      expect(response.success?).to be true
      expect(response.message_id).to be_nil
    end
  end

  describe "error handling for network failures" do
    it "returns error response on SocketError" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      response = notifier.send_message("Test")

      expect(response.success?).to be false
      expect(response.error).to match(/Network error:/)
    end

    it "returns error response on connection refused" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_raise(Errno::ECONNREFUSED.new("Connection refused"))

      response = notifier.send_message("Test")

      expect(response.success?).to be false
      expect(response.error).to match(/Network error:/)
    end

    it "returns error response on connection reset" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_raise(Errno::ECONNRESET.new("Connection reset by peer"))

      response = notifier.send_message("Test")

      expect(response.success?).to be false
      expect(response.error).to match(/Network error:/)
    end

    it "returns error for unexpected StandardError" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_raise(StandardError.new("Something unexpected happened"))

      response = notifier.send_message("Test")

      expect(response.success?).to be false
      expect(response.error).to match(/Unexpected error: StandardError/)
    end
  end

  describe ".notify" do
    it "calls send_events when notifications are enabled" do
      allow(config).to receive(:notifications_enabled?).and_return(true)

      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.notify(events)

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be true
    end

    it "returns nil when notifications are disabled" do
      allow(config).to receive(:notifications_enabled?).and_return(false)

      response = notifier.notify(events)

      expect(response).to be_nil
    end

    it "returns error when no events to send" do
      allow(config).to receive(:notifications_enabled?).and_return(true)

      response = notifier.notify([])

      expect(response.success?).to be false
      expect(response.error).to eq("No events to send")
    end
  end

  describe ".initialize" do
    it "sets the api_base from the bot token" do
      expect(notifier.api_base).to eq("https://api.telegram.org/bot#{bot_token}")
    end

    it "initializes empty state for rate limiting" do
      expect(notifier.last_send_at).to be_nil
      expect(notifier.recent_message_count).to eq(0)
      expect(notifier.recent_message_times).to be_empty
    end

    it "uses a mutex for thread safety" do
      expect(notifier.instance_variable_get(:@mutex)).to be_a(Mutex)
    end
  end

  describe "TelegramResponse" do
    it "has a to_h method" do
      response = WeeklyLocalEvents::TelegramResponse.new(
        success: true, message_id: 42, error: nil, api_error: nil
      )

      expect(response.to_h).to eq({
        success: true, message_id: 42, error: nil, api_error: nil
      })
    end

    it "has a to_s method for success" do
      response = WeeklyLocalEvents::TelegramResponse.new(
        success: true, message_id: 42
      )

      expect(response.to_s).to eq("TelegramResponse(OK: message_id=42)")
    end

    it "has a to_s method for failure with api_error" do
      response = WeeklyLocalEvents::TelegramResponse.new(
        success: false, api_error: { "ok" => false }
      )

      expect(response.to_s).to eq("TelegramResponse(FAILED: API error)")
    end

    it "has a to_s method for failure with both error and api_error" do
      response = WeeklyLocalEvents::TelegramResponse.new(
        success: false, error: "Custom error", api_error: { "ok" => false }
      )

      expect(response.to_s).to eq("TelegramResponse(FAILED: Custom error)")
    end
  end

  describe ".format_summary_for_events" do
    it "returns summary for non-empty events" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      result = notifier.format_summary_for_events(events)

      expect(result).to include("📊 *Summary*")
      expect(result).to include("Total events")
    end

    it "returns '0 events' for empty events" do
      result = notifier.format_summary_for_events([])

      expect(result).to eq("📊 *Summary*: 0 events")
    end

    it "returns summary for multiple events" do
      multi_events = [
        WeeklyLocalEvents::Event.new(
          title: "Event A", date: Date.today + 1,
          venue: venue, url: "https://example.com", source: "test", category: "Music"
        ),
        WeeklyLocalEvents::Event.new(
          title: "Event B", date: Date.today + 2,
          venue: venue, url: "https://example.com", source: "test", category: "Comedy", price: "Free"
        )
      ]

      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      result = notifier.format_summary_for_events(multi_events)

      expect(result).to include("Total events")
      expect(result).to include("Free events")
      expect(result).to include("Paid events")
    end
  end

  describe ".normalize_category" do
    it "normalizes 'concert' to 'Music'" do
      expect(notifier.send(:normalize_category, "concert")).to eq("Music")
    end

    it "normalizes 'live music' to 'Music'" do
      expect(notifier.send(:normalize_category, "live music")).to eq("Music")
    end

    it "normalizes 'show' to 'Music'" do
      expect(notifier.send(:normalize_category, "show")).to eq("Music")
    end

    it "normalizes 'performance' to 'Music'" do
      expect(notifier.send(:normalize_category, "performance")).to eq("Music")
    end

    it "normalizes 'gig' to 'Music'" do
      expect(notifier.send(:normalize_category, "gig")).to eq("Music")
    end

    it "normalizes 'band' to 'Music'" do
      expect(notifier.send(:normalize_category, "band")).to eq("Music")
    end

    it "normalizes 'musician' to 'Music'" do
      expect(notifier.send(:normalize_category, "musician")).to eq("Music")
    end

    it "normalizes 'music' to 'Music'" do
      expect(notifier.send(:normalize_category, "music")).to eq("Music")
    end

    it "normalizes 'stand-up' to 'Comedy'" do
      expect(notifier.send(:normalize_category, "stand-up")).to eq("Comedy")
    end

    it "normalizes 'improv' to 'Comedy'" do
      expect(notifier.send(:normalize_category, "improv")).to eq("Comedy")
    end

    it "normalizes 'joke' to 'Comedy'" do
      expect(notifier.send(:normalize_category, "joke")).to eq("Comedy")
    end

    it "normalizes 'humor' to 'Comedy'" do
      expect(notifier.send(:normalize_category, "humor")).to eq("Comedy")
    end

    it "normalizes 'festival' to 'Festival'" do
      expect(notifier.send(:normalize_category, "festival")).to eq("Festival")
    end

    it "normalizes 'fair' to 'Festival'" do
      expect(notifier.send(:normalize_category, "fair")).to eq("Festival")
    end

    it "normalizes 'carnival' to 'Festival'" do
      expect(notifier.send(:normalize_category, "carnival")).to eq("Festival")
    end

    it "normalizes 'sport' to 'Sports'" do
      expect(notifier.send(:normalize_category, "sport")).to eq("Sports")
    end

    it "normalizes 'game' to 'Sports'" do
      expect(notifier.send(:normalize_category, "game")).to eq("Sports")
    end

    it "normalizes 'art' to 'Art'" do
      expect(notifier.send(:normalize_category, "art")).to eq("Art")
    end

    it "normalizes 'exhibition' to 'Art'" do
      expect(notifier.send(:normalize_category, "exhibition")).to eq("Art")
    end

    it "normalizes 'gallery' to 'Art'" do
      expect(notifier.send(:normalize_category, "gallery")).to eq("Art")
    end

    it "normalizes 'food' to 'Food & Drink'" do
      expect(notifier.send(:normalize_category, "food")).to eq("Food & Drink")
    end

    it "normalizes 'culinary' to 'Food & Drink'" do
      expect(notifier.send(:normalize_category, "culinary")).to eq("Food & Drink")
    end

    it "normalizes 'market' to 'Market'" do
      expect(notifier.send(:normalize_category, "market")).to eq("Market")
    end

    it "normalizes 'education' to 'Education'" do
      expect(notifier.send(:normalize_category, "education")).to eq("Education")
    end

    it "normalizes 'theater' to 'Theater'" do
      expect(notifier.send(:normalize_category, "theater")).to eq("Theater")
    end

    it "normalizes 'play' to 'Theater'" do
      expect(notifier.send(:normalize_category, "play")).to eq("Theater")
    end

    it "normalizes 'family' to 'Family'" do
      expect(notifier.send(:normalize_category, "family")).to eq("Family")
    end

    it "normalizes 'kids' to 'Family'" do
      expect(notifier.send(:normalize_category, "kids")).to eq("Family")
    end

    it "normalizes 'nightlife' to 'Nightlife'" do
      expect(notifier.send(:normalize_category, "nightlife")).to eq("Nightlife")
    end

    it "normalizes 'club' to 'Nightlife'" do
      expect(notifier.send(:normalize_category, "club")).to eq("Nightlife")
    end

    it "normalizes 'outdoor' to 'Outdoor'" do
      expect(notifier.send(:normalize_category, "outdoor")).to eq("Outdoor")
    end

    it "normalizes 'park' to 'Outdoor'" do
      expect(notifier.send(:normalize_category, "park")).to eq("Outdoor")
    end

    it "normalizes 'religious' to 'Religious'" do
      expect(notifier.send(:normalize_category, "religious")).to eq("Religious")
    end

    it "normalizes 'church' to 'Religious'" do
      expect(notifier.send(:normalize_category, "church")).to eq("Religious")
    end

    it "normalizes 'politics' to 'Politics'" do
      expect(notifier.send(:normalize_category, "politics")).to eq("Politics")
    end

    it "normalizes 'tech' to 'Technology'" do
      expect(notifier.send(:normalize_category, "tech")).to eq("Technology")
    end

    it "normalizes 'startup' to 'Technology'" do
      expect(notifier.send(:normalize_category, "startup")).to eq("Technology")
    end

    it "returns 'Other' for unknown category" do
      expect(notifier.send(:normalize_category, "unknown_category")).to eq("Other")
    end

    it "returns 'Other' for nil category" do
      expect(notifier.send(:normalize_category, nil)).to eq("Other")
    end

    it "returns 'Other' for empty string" do
      expect(notifier.send(:normalize_category, "")).to eq("Other")
    end

    it "returns 'Other' for whitespace-only string" do
      expect(notifier.send(:normalize_category, "   ")).to eq("Other")
    end

    it "normalizes case-insensitively" do
      expect(notifier.send(:normalize_category, "MUSIC")).to eq("Music")
      expect(notifier.send(:normalize_category, "CONCERT")).to eq("Music")
    end
  end

  describe ".check_rate_limit!" do
    it "raises when rate limit is reached" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))
      notifier.instance_variable_set(:@recent_message_times,
        Array.new(20) { Time.at(1_700_000_000) })

      expect { notifier.send(:check_rate_limit!) }.to raise_error(StandardError, /Rate limit exceeded/)
    end

    it "does not raise when under rate limit" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))

      expect { notifier.send(:check_rate_limit!) }.not_to raise_error
    end

    it "does not sleep when no previous send" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))
      notifier.instance_variable_set(:@last_send_at, nil)

      expect { notifier.send(:check_rate_limit!) }.not_to raise_error
    end

    it "does not sleep when enough time has passed" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_002))
      notifier.instance_variable_set(:@last_send_at, Time.at(1_700_000_000))

      expect { notifier.send(:check_rate_limit!) }.not_to raise_error
    end
  end

  describe ".truncate_message" do
    it "does not truncate short messages" do
      short = "This is a short message"
      result = notifier.send(:truncate_message, short)
      expect(result).to eq(short)
    end

    it "truncates long messages" do
      long = "x" * 5000
      result = notifier.send(:truncate_message, long)
      expect(result.length).to be <= 4096
    end

    it "includes truncation note" do
      long = "x" * 5000
      result = notifier.send(:truncate_message, long)
      expect(result).to include("truncated")
    end

    it "breaks at newline when available" do
      long = "line1\nline2\n" + "x" * 5000
      result = notifier.send(:truncate_message, long)
      expect(result).to include("line1")
      expect(result).to include("line2")
    end

    it "breaks at newline when it's before 80% of available space" do
      long = "short\n" + "x" * 5000
      result = notifier.send(:truncate_message, long)
      expect(result).to include("short")
    end

    it "does not break at newline when it's too close to the end" do
      # Create a scenario where the newline is beyond 80% of available space
      # available = 4096 - note.length
      long = "x" * 4000 + "\n" + "y" * 200
      result = notifier.send(:truncate_message, long)
      # The newline at position 4000 is beyond 80% of available (which is ~4050)
      # So it should NOT break there
      expect(result.length).to be <= 4096
    end
  end

  describe ".send_telegram_api" do
    it "returns error when no bot token configured" do
      allow(config).to receive(:telegram_bot_token).and_return(nil)
      allow(config).to receive(:notification_channel_id).and_return("123")

      response = notifier.send(:send_telegram_api, "test")

      expect(response.success?).to be false
      expect(response.error).to eq("No bot token configured")
    end

    it "returns error when bot token is empty string" do
      allow(config).to receive(:telegram_bot_token).and_return("")
      allow(config).to receive(:notification_channel_id).and_return("123")

      response = notifier.send(:send_telegram_api, "test")

      expect(response.success?).to be false
      expect(response.error).to eq("No bot token configured")
    end

    it "returns error when bot token is whitespace only" do
      allow(config).to receive(:telegram_bot_token).and_return("   ")
      allow(config).to receive(:notification_channel_id).and_return("123")

      response = notifier.send(:send_telegram_api, "test")

      expect(response.success?).to be false
      expect(response.error).to eq("No bot token configured")
    end

    it "sends with correct chat_id" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("chat_id" => channel_id),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send(:send_telegram_api, "test")
      expect(response.success?).to be true
    end

    it "sends with parse_mode when specified" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("parse_mode" => "HTML"),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send(:send_telegram_api, "test", parse_mode: "HTML")
      expect(response.success?).to be true
    end

    it "does not include parse_mode when nil" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: { "chat_id" => channel_id, "text" => "test" },
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send(:send_telegram_api, "test", parse_mode: nil)
      expect(response.success?).to be true
    end
  end

  describe ".rate_limit_check" do
    it "rejects old messages outside 60-second window" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_061))
      notifier.instance_variable_set(:@recent_message_times,
        Array.new(19) { Time.at(1_700_000_000) })

      expect(notifier.rate_limit_check).to be false
    end

    it "rejects messages within 60-second window" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_030))
      notifier.instance_variable_set(:@recent_message_times,
        Array.new(20) { Time.at(1_700_000_000) })

      expect(notifier.rate_limit_check).to be true
    end

    it "handles empty message times" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))
      notifier.instance_variable_set(:@recent_message_times, [])

      expect(notifier.rate_limit_check).to be false
    end
  end

  describe ".send_message" do
    it "calls check_rate_limit and updates state" do
      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000))

      notifier.send_message("test")

      expect(notifier.recent_message_count).to eq(1)
      expect(notifier.recent_message_times.size).to eq(1)
    end

    it "returns error for whitespace-only message" do
      response = notifier.send_message("   ")

      expect(response.success?).to be false
      expect(response.error).to eq("No message provided")
    end
  end

  describe ".send_with_markdown" do
    it "calls send_message with MarkdownV2" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("parse_mode" => "MarkdownV2"),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_with_markdown("test")
      expect(response.success?).to be true
    end
  end

  describe ".send_with_html" do
    it "calls send_message with HTML" do
      stub_request(:post, "#{api_base}/sendMessage")
        .with(
          body: hash_including("parse_mode" => "HTML"),
          headers: { "Content-Type" => "application/x-www-form-urlencoded" }
        )
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.send_with_html("test")
      expect(response.success?).to be true
    end
  end

  describe ".format_events" do
    it "covers all category emojis" do
      categories = {
        "Music" => "🎵",
        "Comedy" => "🎭",
        "Festival" => "🎪",
        "Sports" => "⚽",
        "Art" => "🎨",
        "Food & Drink" => "🍽️",
        "Market" => "🏪",
        "Education" => "📚",
        "Theater" => "🎭",
        "Family" => "👨‍👩‍👧",
        "Nightlife" => "🌙",
        "Outdoor" => "🌲",
        "Religious" => "⛪",
        "Politics" => "🗳️",
        "Technology" => "💻"
      }

      events = categories.map do |cat, emoji|
        WeeklyLocalEvents::Event.new(
          title: "#{cat} Event", date: Date.today + 1,
          venue: venue, url: "https://example.com", source: "test", category: cat
        )
      end

      result = notifier.format_events(events)

      categories.each do |cat, emoji|
        expect(result).to include("#{emoji} *#{cat}*")
      end
    end

    it "covers unknown category with '📋' emoji" do
      event = WeeklyLocalEvents::Event.new(
        title: "Unknown Event", date: Date.today + 1,
        venue: venue, url: "https://example.com", source: "test", category: "unknown"
      )

      result = notifier.format_events([event])

      expect(result).to include("📋 *Other*")
      expect(result).to include("- *Unknown Event* - ACL Live - Free")
    end

    it "handles events without price" do
      event = WeeklyLocalEvents::Event.new(
        title: "No Price Event", date: Date.today + 1,
        venue: venue, url: "https://example.com", source: "test"
      )

      result = notifier.format_events([event])

      expect(result).to include("Free")
    end

    it "handles events without venue" do
      event = WeeklyLocalEvents::Event.new(
        title: "No Venue Event", date: Date.today + 1,
        venue: nil, url: "https://example.com", source: "test"
      )

      result = notifier.format_events([event])

      expect(result).to include("Unknown")
    end

    it "groups by normalized category" do
      music_event = WeeklyLocalEvents::Event.new(
        title: "Rock Show", date: Date.today + 1,
        venue: venue, url: "https://example.com", source: "test", category: "concert"
      )
      comedy_event = WeeklyLocalEvents::Event.new(
        title: "Joke Night", date: Date.today + 2,
        venue: venue, url: "https://example.com", source: "test", category: "comedy"
      )

      result = notifier.format_events([music_event, comedy_event])

      expect(result).to include("🎵 *Music*")
      expect(result).to include("🎭 *Comedy*")
    end

    it "handles multiple events in same category" do
      events = [
        WeeklyLocalEvents::Event.new(
          title: "Event 1", date: Date.today + 1,
          venue: venue, url: "https://example.com", source: "test", category: "Music"
        ),
        WeeklyLocalEvents::Event.new(
          title: "Event 2", date: Date.today + 2,
          venue: venue, url: "https://example.com", source: "test", category: "Music"
        )
      ]

      result = notifier.format_events(events)

      expect(result).to include("*Event 1*")
      expect(result).to include("*Event 2*")
      expect(result).to include("🎵 *Music*")
    end

    it "handles events with price range" do
      event = WeeklyLocalEvents::Event.new(
        title: "Range Event", date: Date.today + 1,
        venue: venue, url: "https://example.com", source: "test",
        price: "$10–$50"
      )

      result = notifier.format_events([event])

      expect(result).to include("$10–$50")
    end
  end

  describe ".format_summary" do
    it "handles categories with symbol keys" do
      summary = { total: 5, free_count: 2, paid_count: 3,
                  categories: { :Music => 3, :Comedy => 2 },
                  sources: { :austin_chronicle => 5 } }

      result = notifier.format_summary(summary)

      expect(result).to include("Music: 3")
      expect(result).to include("austin_chronicle: 5")
    end

    it "handles categories with string keys" do
      summary = { total: 5, free_count: 2, paid_count: 3,
                  categories: { "Music" => 3, "Comedy" => 2 },
                  sources: { "austin_chronicle" => 5 } }

      result = notifier.format_summary(summary)

      expect(result).to include("Music: 3")
    end

    it "handles mixed keys" do
      summary = { total: 5, free_count: 2, paid_count: 3,
                  categories: { :Music => 3, "Comedy" => 2 },
                  sources: { "austin_chronicle" => 5 } }

      result = notifier.format_summary(summary)

      expect(result).to include("Music: 3")
      expect(result).to include("Comedy: 2")
    end

    it "handles zero counts" do
      summary = { total: 0, free_count: 0, paid_count: 0,
                  categories: [], sources: [] }

      result = notifier.format_summary(summary)

      expect(result).to include("*Total events*: 0")
      expect(result).to include("*Free events*: 0")
      expect(result).to include("*Paid events*: 0")
    end

    it "handles missing keys gracefully" do
      summary = { total: 5 }

      result = notifier.format_summary(summary)

      expect(result).to include("*Total events*: 5")
      expect(result).to include("*Free events*: 0")
      expect(result).to include("*Paid events*: 5")
    end
  end

  describe ".notify" do
    it "returns nil when config notifications_enabled is false" do
      allow(config).to receive(:notifications_enabled?).and_return(false)

      response = notifier.notify(events)

      expect(response).to be_nil
    end

    it "returns error when events are empty and notifications enabled" do
      allow(config).to receive(:notifications_enabled?).and_return(true)

      response = notifier.notify([])

      expect(response.success?).to be false
      expect(response.error).to eq("No events to send")
    end

    it "calls send_events and returns response when enabled" do
      allow(config).to receive(:notifications_enabled?).and_return(true)

      stub_request(:post, "#{api_base}/sendMessage")
        .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })

      response = notifier.notify(events)

      expect(response).to be_a(WeeklyLocalEvents::TelegramResponse)
      expect(response.success?).to be true
    end
  end

  describe ".initialize" do
    it "sets api_base with bot token" do
      expect(notifier.api_base).to eq("https://api.telegram.org/bot#{bot_token}")
    end

    it "sets api_base without bot token" do
      allow(config).to receive(:telegram_bot_token).and_return(nil)
      notifier2 = described_class.new(config)

      expect(notifier2.api_base).to eq("https://api.telegram.org/bot")
    end

    it "initializes rate limiting state" do
      expect(notifier.last_send_at).to be_nil
      expect(notifier.recent_message_count).to eq(0)
      expect(notifier.recent_message_times).to be_empty
    end

    it "creates a mutex" do
      expect(notifier.instance_variable_get(:@mutex)).to be_a(Mutex)
    end
  end
end
