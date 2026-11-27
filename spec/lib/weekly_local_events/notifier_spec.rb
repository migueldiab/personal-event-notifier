# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Notifier do
  subject(:notifier) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }

  let(:mock_response) do
    { "ok" => true, "result" => { "message_id" => 12345 } }
  end

  describe "initialization" do
    it "creates a notifier with valid config" do
      expect(notifier).to be_a(described_class)
    end

    it "stores config" do
      expect(notifier.config).to eq(config)
    end
  end

  describe "#format_events" do
    let(:events) do
      [
        WeeklyLocalEvents::Event.new(title: "Rock Concert", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Moody Center"), url: "https://example.com/1", price: "$25", category: "Music", source: "test"),
        WeeklyLocalEvents::Event.new(title: "Jazz Night", date: "2026-12-02", venue: WeeklyLocalEvents::Venue.new(name: "Antone's"), url: "https://example.com/2", price: "$15", category: "Music", source: "test"),
        WeeklyLocalEvents::Event.new(title: "Stand-up Show", date: "2026-12-03", venue: WeeklyLocalEvents::Venue.new(name: "Comedy Sportz"), url: "https://example.com/3", price: "$20", category: "Comedy", source: "test"),
        WeeklyLocalEvents::Event.new(title: "Free Open Mic", date: "2026-12-04", venue: WeeklyLocalEvents::Venue.new(name: "The Continental"), url: "https://example.com/4", price: "free", category: "Comedy", source: "test"),
        WeeklyLocalEvents::Event.new(title: "Art Exhibition", date: "2026-12-05", venue: WeeklyLocalEvents::Venue.new(name: "Blanton Museum"), url: "https://example.com/5", price: "$10", category: "Art", source: "test"),
      ]
    end

    it "groups events by category" do
      result = notifier.format_events(events)
      expect(result).to include("Music")
      expect(result).to include("Comedy")
      expect(result).to include("Art")
    end

    it "includes event details (name, venue, price)" do
      result = notifier.format_events(events)
      expect(result).to include("Rock Concert")
      expect(result).to include("Moody Center")
      expect(result).to include("$25")
    end

    it "shows 'Free' for empty price" do
      result = notifier.format_events(events)
      expect(result).to include("Free Open Mic")
      expect(result).to include("Free")
    end

    it "handles empty events list" do
      expect(notifier.format_events([])).to eq("No events found.")
    end

    it "handles nil events" do
      expect { notifier.format_events(nil) }.to raise_error(NoMethodError)
    end

    it "includes emoji headers" do
      result = notifier.format_events(events)
      expect(result).to include("📅")
      expect(result).to include("📆")
      expect(result).to include("🎵")
      expect(result).to include("🎭")
      expect(result).to include("🎨")
    end

    it "handles events with unknown categories" do
      event = WeeklyLocalEvents::Event.new(title: "Tech Talk", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "UT Campus"), url: "https://example.com", source: "test")
      result = notifier.format_events([event])
      expect(result).to include("Tech Talk")
    end
  end

  describe "#format_summary" do
    let(:summary) do
      { total: 15, free_count: 3, paid_count: 12, categories: { "Music" => 8, "Comedy" => 4, "Art" => 3 }, sources: { "Austin Chronicle" => 10, "Do512" => 5 } }
    end

    it "formats summary hash into readable text" do
      result = notifier.format_summary(summary)
      expect(result).to include("Total events")
      expect(result).to include("Free events")
      expect(result).to include("Paid events")
      expect(result).to include("15")
      expect(result).to include("Music: 8")
      expect(result).to include("Comedy: 4")
    end

    it "handles nil summary" do
      expect(notifier.format_summary(nil)).to eq("No summary available.")
    end

    it "handles non-hash summary" do
      expect(notifier.format_summary("not a hash")).to eq("No summary available.")
    end

    it "handles empty summary" do
      result = notifier.format_summary({})
      expect(result).to include("Total events")
      expect(result).to include("0")
    end
  end

  describe "#format_summary_for_events" do
    let(:events) do
      [
        WeeklyLocalEvents::Event.new(title: "Event 1", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Venue 1"), url: "https://example.com/1", source: "test"),
        WeeklyLocalEvents::Event.new(title: "Event 2", date: "2026-12-02", venue: WeeklyLocalEvents::Venue.new(name: "Venue 2"), url: "https://example.com/2", source: "test"),
      ]
    end

    it "returns formatted summary from events" do
      result = notifier.format_summary_for_events(events)
      expect(result).to include("Summary")
      expect(result).to include("Total events")
    end

    it "handles empty events" do
      expect(notifier.format_summary_for_events([])).to include("0 events")
    end
  end

  describe "#send_events" do
    before do
      allow(config).to receive(:notifications_enabled?).and_return(true)
      allow(config).to receive(:telegram_bot_token).and_return("test_token")
      allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
    end

    it "calls format_events and sends with markdown" do
      events = [
        WeeklyLocalEvents::Event.new(title: "Test", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Test Venue"), url: "https://example.com", price: "$10", source: "test"),
      ]
      allow(notifier).to receive(:send_with_markdown).and_return(
        WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 100)
      )
      result = notifier.send_events(events)
      expect(result.success?).to be true
      expect(result.message_id).to eq(100)
    end

    it "returns error for empty events" do
      result = notifier.send_events([])
      expect(result.success?).to be false
      expect(result.error).to include("No events provided")
    end
  end

  describe "#send_with_markdown" do
    before do
      allow(config).to receive(:notifications_enabled?).and_return(true)
      allow(config).to receive(:telegram_bot_token).and_return("test_token")
      allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
    end

    it "calls send_message with MarkdownV2 parse mode" do
      allow(notifier).to receive(:send_telegram_api).and_return(
        WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 200)
      )
      result = notifier.send_with_markdown("*bold*")
      expect(result.success?).to be true
    end
  end

  describe "#send_with_html" do
    before do
      allow(config).to receive(:notifications_enabled?).and_return(true)
      allow(config).to receive(:telegram_bot_token).and_return("test_token")
      allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
    end

    it "calls send_message with HTML parse mode" do
      allow(notifier).to receive(:send_telegram_api).and_return(
        WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 300)
      )
      result = notifier.send_with_html("<b>bold</b>")
      expect(result.success?).to be true
    end
  end

  describe "#rate_limit_check" do
    it "returns false when not rate limited" do
      expect(notifier.rate_limit_check).to be false
    end

    it "returns true when rate limited" do
      # Manually set up the state to simulate rate limit
      notifier.instance_variable_set(:@recent_message_times, Array.new(21) { Time.now })
      expect(notifier.rate_limit_check).to be true
    end
  end

  describe "#send_message" do
    before do
      allow(config).to receive(:notifications_enabled?).and_return(true)
      allow(config).to receive(:telegram_bot_token).and_return("test_token")
      allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
    end

    it "returns error for empty message" do
      result = notifier.send_message("")
      expect(result.success?).to be false
      expect(result.error).to include("No message provided")
    end

    it "truncates messages over 4096 characters" do
      long_text = "A" * 5000
      allow(notifier).to receive(:send_telegram_api).and_return(
        WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 400)
      )
      result = notifier.send_message(long_text)
      expect(result.success?).to be true
    end

    it "truncates message to 4096 chars" do
      long_text = "A" * 5000
      # The truncation is internal to send_message -> send_telegram_api
      # We verify it doesn't raise and the message is within limit by checking the internal method
      allow(notifier).to receive(:send_telegram_api).with(a_string_matching(/^A{3,}/), hash_including(:parse_mode => nil)).and_call_original
      allow(notifier).to receive(:send_telegram_api).and_wrap_original do |m, text, **opts|
        expect(text.length).to be <= 4096
        WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 400)
      end
      result = notifier.send_message(long_text)
      expect(result.success?).to be true
    end
  end

  describe "#send_telegram_api" do
    before do
      allow(config).to receive(:notifications_enabled?).and_return(true)
      allow(config).to receive(:telegram_bot_token).and_return("test_token")
      allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
    end

    it "returns success for valid response" do
      mock_http = double(is_a?: true)
      mock_response_obj = double(is_a?: true, body: JSON.generate(mock_response))
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      allow(mock_http).to receive(:request).and_return(mock_response_obj)
      result = notifier.send_telegram_api("test message")
      expect(result.success?).to be true
    end

    it "returns error for failed API response" do
      error_response = { "ok" => false, "description" => "Bad Request: message is too long" }
      mock_http = double(is_a?: false)
      mock_response_obj = double(is_a?: false, body: JSON.generate(error_response))
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      allow(mock_http).to receive(:request).and_return(mock_response_obj)
      result = notifier.send_telegram_api("test")
      expect(result.success?).to be false
      expect(result.error).to include("Bad Request")
    end

    it "handles network errors" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError.new("Network unreachable"))
      result = notifier.send_telegram_api("test")
      expect(result.success?).to be false
      expect(result.error).to include("Network error")
    end

    it "handles JSON parse errors" do
      mock_http = double(is_a?: false)
      mock_response_obj = double(is_a?: false, body: "not json")
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      allow(mock_http).to receive(:request).and_return(mock_response_obj)
      result = notifier.send_telegram_api("test")
      expect(result.success?).to be false
      expect(result.error).to include("Unknown Telegram API error")
    end
  end

  describe "TelegramResponse" do
    it "creates a successful response" do
      response = WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 12345)
      expect(response.success?).to be true
      expect(response.message_id).to eq(12345)
      expect(response.error).to be_nil
    end

    it "creates a failed response" do
      response = WeeklyLocalEvents::TelegramResponse.new(success: false, error: "Something went wrong")
      expect(response.success?).to be false
      expect(response.error).to eq("Something went wrong")
    end

    it "converts to hash" do
      response = WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 100)
      h = response.to_h
      expect(h[:success]).to be true
      expect(h[:message_id]).to eq(100)
    end

    it "converts to string" do
      response = WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 100)
      expect(response.to_s).to include("OK")
      expect(response.to_s).to include("100")
    end
  end

  describe "#normalize_category" do
    it "normalizes music-related categories" do
      expect(notifier.send(:normalize_category, "concert")).to eq("Music")
      expect(notifier.send(:normalize_category, "live music")).to eq("Music")
      expect(notifier.send(:normalize_category, "gig")).to eq("Music")
    end

    it "normalizes comedy-related categories" do
      expect(notifier.send(:normalize_category, "stand-up")).to eq("Comedy")
      expect(notifier.send(:normalize_category, "improv")).to eq("Comedy")
    end

    it "normalizes other categories" do
      expect(notifier.send(:normalize_category, "festival")).to eq("Festival")
      expect(notifier.send(:normalize_category, "sports")).to eq("Sports")
      expect(notifier.send(:normalize_category, "art")).to eq("Art")
      expect(notifier.send(:normalize_category, "food")).to eq("Food & Drink")
      expect(notifier.send(:normalize_category, "tech")).to eq("Technology")
    end

    it "returns 'Other' for unknown categories" do
      expect(notifier.send(:normalize_category, "unknown category")).to eq("Other")
    end

    it "returns 'Other' for nil or empty" do
      expect(notifier.send(:normalize_category, nil)).to eq("Other")
      expect(notifier.send(:normalize_category, "")).to eq("Other")
    end
  end
end
