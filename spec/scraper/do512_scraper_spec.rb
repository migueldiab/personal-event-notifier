# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webmock/rspec"
require "weekly_local_events/scrapers/do512_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::Do512Scraper do
  subject(:scraper) { described_class.new(rate_limit_delay: 0, pages: 2) }

  let(:fixture_html) { File.read(File.expand_path("../fixtures/do512_page1.html", __dir__)) }
  let(:events_url) { "https://www.do512.com/events" }
  let(:page2_url) { "https://www.do512.com/events/?page=2" }

  describe "selector parsing against the page fixture" do
    let(:events) { scraper.parse_response(fixture_html) }

    it "extracts every event card using the ds-listing selectors" do
      expect(events.size).to eq(3)
      expect(events.map(&:title)).to eq(
        ["Cosmic Vibes", "Saturday Farmers Market", "Gallery Night"]
      )
    end

    it "parses title, venue and an absolute event URL" do
      first = events.first

      expect(first.title).to eq("Cosmic Vibes")
      expect(first.venue.name).to eq("Hotel Vegas")
      expect(first.url).to eq("https://www.do512.com/events/2026/11/20/cosmic-vibes-tickets")
      expect(first.source).to eq("do512")
    end

    it "normalizes the ISO startDate and the 12-hour display time" do
      first = events.first

      expect(first.date).to eq(Date.new(2026, 11, 20))
      expect(first.begin_time).to eq("19:00")
      expect(first.time).to eq("19:00")
    end

    it "reads a second dtstart element as the end time" do
      expect(events.last.end_time).to eq("21:00")
    end

    it "maps ds-event-category classes to readable categories" do
      expect(events.map(&:category)).to eq(
        ["Live: Music", "Community: Market", "Art: Culture"]
      )
    end

    it "detects free and sold-out banners" do
      expect(events[0].is_free).to be false
      expect(events[1].is_free).to be true
      expect(events[1].price).to eq("Free")
      expect(events[2].sold_out).to be true
      expect(events[2].is_free).to be false
    end

    it "extracts the ticket button href as the buy URL" do
      expect(events.first.buy_url).to eq("https://www.ticketmaster.com/event/cosmic-vibes")
      expect(events[1].buy_url).to be_nil
    end

    it "accepts an already parsed Nokogiri document" do
      document = Nokogiri::HTML5.parse(fixture_html, encoding: "UTF-8")

      expect(scraper.parse_response(document).size).to eq(3)
    end

    it "returns no events for empty or nil input" do
      expect(scraper.parse_response("")).to be_empty
      expect(scraper.parse_response(nil)).to be_empty
    end
  end

  describe "pagination detection" do
    it "omits the page parameter for the first page" do
      expect(scraper.send(:build_events_url, 1)).to eq(events_url)
    end

    it "adds ?page=N for later pages" do
      expect(scraper.send(:build_events_url, 2)).to eq(page2_url)
      expect(scraper.send(:build_events_url, 5)).to eq("https://www.do512.com/events/?page=5")
    end

    it "scrapes up to the configured page count and then stops" do
      stub_request(:get, events_url).to_return(status: 200, body: fixture_html)
      stub_request(:get, page2_url).to_return(status: 200, body: fixture_html)

      events = scraper.events

      expect(events.size).to eq(6)
      expect(scraper.pages_scraped).to eq(2)
      expect(a_request(:get, "https://www.do512.com/events/?page=3")).not_to have_been_made
    end

    it "stops when a page contains no event cards" do
      stub_request(:get, events_url).to_return(status: 200, body: fixture_html)
      stub_request(:get, page2_url).to_return(status: 200, body: "<html><body></body></html>")

      events = scraper.events

      expect(events.size).to eq(3)
      expect(scraper.pages_scraped).to eq(2)
    end

    it "treats max_pages as a hard ceiling" do
      limited = described_class.new(rate_limit_delay: 0, pages: 5, max_pages: 1)
      stub_request(:get, events_url).to_return(status: 200, body: fixture_html)

      expect(limited.events.size).to eq(3)
      expect(limited.pages_scraped).to eq(1)
    end
  end

  describe "anti-bot retry logic" do
    subject(:retry_scraper) { described_class.new(rate_limit_delay: 0, max_retries: 3) }

    it "draws its user agent from the anti-bot pool" do
      expect(described_class::USER_AGENTS).to include(retry_scraper.user_agent)
    end

    it "retries after HTTP 429 and parses the successful response" do
      stub_request(:get, events_url).to_return(
        { status: 429, body: "rate limited" },
        { status: 200, body: fixture_html, headers: { "Content-Type" => "text/html" } }
      )

      document = retry_scraper.send(:fetch_with_retry, events_url)

      expect(document.css(".event-card").size).to eq(3)
      expect(a_request(:get, events_url)).to have_been_made.times(2)
      expect(described_class::USER_AGENTS).to include(retry_scraper.last_user_agent)
    end

    it "retries after an HTTP 403 bot challenge" do
      stub_request(:get, events_url).to_return(
        { status: 403, body: "forbidden" },
        { status: 200, body: fixture_html }
      )

      document = retry_scraper.send(:fetch_with_retry, events_url)

      expect(document.css(".event-card").size).to eq(3)
      expect(a_request(:get, events_url)).to have_been_made.times(2)
    end

    it "gives up after max_retries consecutive rate-limit responses" do
      stub_request(:get, events_url).to_return(
        { status: 429, body: "rate limited" },
        { status: 429, body: "rate limited" },
        { status: 429, body: "rate limited" }
      )

      expect(retry_scraper.send(:fetch_with_retry, events_url)).to be_nil
      expect(a_request(:get, events_url)).to have_been_made.times(3)
    end

    it "does not retry an HTTP 404 response" do
      stub_request(:get, events_url).to_return(status: 404)

      expect(retry_scraper.send(:fetch_with_retry, events_url)).to be_nil
      expect(a_request(:get, events_url)).to have_been_made.once
    end

    it "retries after a transient network error" do
      stub_request(:get, events_url)
        .to_raise(Errno::ECONNRESET)
        .then.to_return(status: 200, body: fixture_html)

      document = retry_scraper.send(:fetch_with_retry, events_url)

      expect(document.css(".event-card").size).to eq(3)
      expect(a_request(:get, events_url)).to have_been_made.times(2)
    end

    it "sends browser-like anti-bot headers with each request" do
      stub_request(:get, events_url)
        .with(headers: { "Accept-Language" => "en-US,en;q=0.9" })
        .to_return(status: 200, body: fixture_html)

      retry_scraper.send(:fetch_with_retry, events_url)

      expect(a_request(:get, events_url)).to have_been_made.once
    end
  end

  describe "JSON output format validation" do
    def export_events(scraper_instance, path)
      events = scraper_instance.parse_response(fixture_html)
      scraper_instance.instance_variable_set(:@events, events)
      expect(scraper_instance.export_jsonl(path)).to eq(events.size)
      File.readlines(path, chomp: true).map { |line| JSON.parse(line) }
    end

    it "writes one valid JSON object per line" do
      Dir.mktmpdir do |dir|
        records = export_events(scraper, File.join(dir, "do512.jsonl"))

        expect(records.size).to eq(3)
        expect(records).to all(be_a(Hash))
        expect(records.first["title"]).to eq("Cosmic Vibes")
      end
    end

    it "includes the full field set in every JSON object" do
      expected_keys = %w[
        title description date time begin_time end_time venue artists price
        price_cents currency url source image_url category is_free sold_out
        buy_url tags created_at updated_at
      ]

      Dir.mktmpdir do |dir|
        records = export_events(scraper, File.join(dir, "do512.jsonl"))

        records.each do |record|
          expect(record.keys).to include(*expected_keys)
        end
      end
    end

    it "serializes the venue as a nested object" do
      Dir.mktmpdir do |dir|
        records = export_events(scraper, File.join(dir, "do512.jsonl"))

        expect(records.first["venue"]).to be_a(Hash)
        expect(records.first["venue"]["name"]).to eq("Hotel Vegas")
      end
    end

    it "creates missing parent directories" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "dir", "events.jsonl")

        records = export_events(scraper, path)

        expect(File.exist?(path)).to be true
        expect(records.size).to eq(3)
      end
    end
  end

  describe "required fields in extracted events" do
    let(:events) { scraper.parse_response(fixture_html) }

    it "produces only valid Event instances" do
      expect(events).not_to be_empty
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events).to all(be_valid)
    end

    it "populates the five required core fields on every event" do
      events.each do |event|
        expect(event.title.to_s.strip).not_to be_empty
        expect(event.date).to be_a(Date)
        expect(event.venue).to be_a(WeeklyLocalEvents::Venue)
        expect(event.url).to start_with("https://www.do512.com/events/")
        expect(event.source).to eq("do512")
      end
    end

    it "exposes the complete serialized field set" do
      fields = %i[
        title description date time begin_time end_time venue artists price
        price_cents currency url source image_url category is_free sold_out
        buy_url tags created_at updated_at
      ]

      events.each do |event|
        expect(event.to_hash.keys).to include(*fields)
      end
    end
  end
end
