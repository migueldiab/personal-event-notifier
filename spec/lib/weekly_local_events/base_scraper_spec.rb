# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe WeeklyLocalEvents::BaseScraper do
  subject(:scraper) { build_scraper }

  # A hash config keeps these examples independent of ~/.hermes config.yml
  # (which sets retries, delays and a date range in this developer's env).
  let(:config) do
    {
      name: "base_scraper",
      base_url: "https://example.com",
      date_range_days: 7,
      rate_limit_delay: 0.25,
      max_retries: 3,
    }
  end
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:events_url) { "https://example.com/events" }
  let(:html_response) { "<html><body><h1>Austin Events</h1></body></html>" }

  # --- Custom factory methods -------------------------------------------------

  def build_scraper(overrides = {})
    described_class.new(config.merge(overrides))
  end

  # Custom factory helpers keep these examples self-contained: the shared
  # FactoryBot :venue factory is not usable on main (Venue has no setters).
  def build_venue(overrides = {})
    attributes = {
      name: "Test Venue",
      address: "123 Main St",
      city: "Austin",
      state: "TX",
      zip: "78701",
    }.merge(overrides)

    WeeklyLocalEvents::Venue.new(**attributes)
  end

  def build_event(overrides = {})
    attributes = {
      title: "Summer Concert",
      date: Date.new(2024, 1, 15),
      venue: build_venue,
      url: "https://example.com/events/summer-concert",
      source: "test_scraper",
    }.merge(overrides)

    WeeklyLocalEvents::Event.new(**attributes)
  end

  before do
    allow(scraper.config).to receive(:logger).and_return(logger)
    # Never really sleep; the examples below assert the requested delay.
    allow(scraper).to receive(:sleep)
  end

  describe ".initialize" do
    it "uses the supplied name and base URL" do
      expect(scraper.name).to eq("base_scraper")
      expect(scraper.base_url).to eq("https://example.com")
    end

    it "defaults the name to the class name when none is supplied" do
      expect(described_class.new({}).name).to eq("BaseScraper")
    end

    it "defaults the base URL to an empty string" do
      expect(described_class.new({}).base_url).to eq("")
    end

    it "builds a date range from date_range_days" do
      range = scraper.date_range

      expect(range).to be_a(WeeklyLocalEvents::DateRange)
      expect(range.end_date - range.start_date).to eq(7)
    end

    it "accepts an explicit date range" do
      range = WeeklyLocalEvents::DateRange.new(
        start: Date.new(2024, 1, 1), end_date: Date.new(2024, 1, 31)
      )

      expect(build_scraper(date_range: range).date_range).to equal(range)
    end

    it "uses the supplied rate limit delay and retry budget" do
      expect(scraper.rate_limit_delay).to eq(0.25)
      expect(scraper.max_retries).to eq(3)
    end

    it "defaults the delay, headers and cookies when they are omitted" do
      bare = described_class.new({})

      expect(bare.rate_limit_delay).to eq(2.0)
      expect(bare.headers).to eq({})
      expect(bare.cookies).to eq({})
    end

    it "defaults the user agent to the gem identifier" do
      expect(scraper.user_agent).to eq("WeeklyLocalEvents/#{WeeklyLocalEvents::VERSION}")
    end

    it "honours custom user agent, headers and cookies" do
      custom = build_scraper(
        user_agent: "SpecAgent/1.0",
        headers: { "X-Test" => "yes" },
        cookies: { "session" => "abc" }
      )

      expect(custom.user_agent).to eq("SpecAgent/1.0")
      expect(custom.headers).to eq("X-Test" => "yes")
      expect(custom.cookies).to eq("session" => "abc")
    end

    it "accepts a Config instance and stores it" do
      config_instance = WeeklyLocalEvents::Config.new

      expect(described_class.new(config_instance).config).to equal(config_instance)
    end

    it "falls back to a fresh Config for an unsupported config object" do
      expect(described_class.new(Object.new).config).to be_a(WeeklyLocalEvents::Config)
    end
  end

  describe ".fetch" do
    it "returns a parsed Nokogiri document for a successful response" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: html_response, headers: { "Content-Type" => "text/html" })

      document = scraper.fetch(events_url)

      expect(document).to be_a(Nokogiri::HTML::Document)
      expect(document.at_css("h1").text).to eq("Austin Events")
    end

    it "sends the configured user agent, headers and cookies" do
      custom = build_scraper(
        user_agent: "SpecAgent/1.0",
        headers: { "X-Test" => "yes" },
        cookies: { "session" => "abc" }
      )
      request = stub_request(:get, events_url)
                .with(headers: {
                        "User-Agent" => "SpecAgent/1.0",
                        "X-Test" => "yes",
                        "Cookie" => "session=abc",
                      })
                .to_return(status: 200, body: html_response)

      custom.fetch(events_url)

      expect(request).to have_been_requested.once
    end

    it "raises ScraperError for a 500 response" do
      stub_request(:get, events_url).to_return(status: 500, body: "boom")

      expect { scraper.fetch(events_url) }
        .to raise_error(WeeklyLocalEvents::ScraperError, /Failed after 3 attempts.*HTTP 500/)
    end

    it "surfaces the NotFoundError message when the response is 404" do
      stub_request(:get, events_url).to_return(status: 404)

      expect { scraper.fetch(events_url) }
        .to raise_error(WeeklyLocalEvents::ScraperError, /Not found: #{events_url}/)
    end

    it "raises RateLimitError immediately for a 429 response" do
      stub_request(:get, events_url).to_return(status: 429)

      expect { scraper.fetch(events_url) }
        .to raise_error(WeeklyLocalEvents::RateLimitError, /Rate limited: #{events_url}/)
    end

    it "raises ScraperError after a network failure" do
      stub_request(:get, events_url).to_raise(Errno::ECONNREFUSED)

      expect { scraper.fetch(events_url) }
        .to raise_error(WeeklyLocalEvents::ScraperError, /ECONNREFUSED/)
    end

    it "raises ArgumentError for a URL without a scheme or host" do
      expect { scraper.fetch("not-a-url") }
        .to raise_error(ArgumentError, /Invalid URL/)
    end

    it "applies the rate limit delay before retrying a failed request" do
      stub_request(:get, events_url).to_return(status: 500)

      expect(scraper).to receive(:sleep).with(0.25).once

      expect { scraper.fetch(events_url) }.to raise_error(WeeklyLocalEvents::ScraperError)
    end

    it "does not back off when max_retries is one" do
      single_attempt = build_scraper(max_retries: 1)
      allow(single_attempt.config).to receive(:logger).and_return(logger)
      stub_request(:get, events_url).to_return(status: 500)

      expect(single_attempt).not_to receive(:sleep)
      expect { single_attempt.fetch(events_url) }
        .to raise_error(WeeklyLocalEvents::ScraperError, /Failed after 1 attempts/)
    end

    it "never exceeds the configured retry budget" do
      stub_request(:get, events_url).to_return(status: 503)

      expect { scraper.fetch(events_url) }.to raise_error(WeeklyLocalEvents::ScraperError)
      expect(a_request(:get, events_url)).to have_been_made.at_most_times(3)
    end
  end

  describe ".normalize_price" do
  {
    "$10" => 1000,
    "$10.00" => 1000,
    "$10-50" => 1000,
    "Free" => 0,
    "$0" => 0,
    # BaseScraper documents free/TBD/empty as 0 cents, so TBD maps to 0.
    "TBD" => 0,
  }.each do |input, expected|
    it "converts #{input.inspect} to #{expected} cents" do
      expect(scraper.normalize_price(input)).to eq(expected)
    end
  end

    it "converts a written-out range to its minimum price" do
      expect(scraper.normalize_price("$10 to $50")).to eq(1000)
    end

    it "handles nil and blank strings as free" do
      expect(scraper.normalize_price(nil)).to eq(0)
      expect(scraper.normalize_price("  ")).to eq(0)
    end

    it "handles non-dollar currency symbols and whitespace" do
      expect(scraper.normalize_price(" €15.50 ")).to eq(1550)
    end

    it "converts a plain numeric string" do
      expect(scraper.normalize_price("12")).to eq(1200)
    end
  end

  describe ".normalize_date" do
    {
      "2024-01-15" => Date.new(2024, 1, 15),
      "Jan 15, 2024" => Date.new(2024, 1, 15),
      "1/15/2024" => Date.new(2024, 1, 15),
    }.each do |input, expected|
      it "parses #{input.inspect} into #{expected}" do
        expect(scraper.normalize_date(input)).to eq(expected)
      end
    end

    it "returns nil for nil input" do
      expect(scraper.normalize_date(nil)).to be_nil
    end

    it "returns nil for an unparseable string" do
      expect(scraper.normalize_date("not a date")).to be_nil
    end

    it "resolves relative dates" do
      expect(scraper.normalize_date("today")).to eq(Date.today)
      expect(scraper.normalize_date("tomorrow")).to eq(Date.today + 1)
      expect(scraper.normalize_date("yesterday")).to eq(Date.today - 1)
    end

    it "parses a fully spelled-out month" do
      expect(scraper.normalize_date("January 15, 2024")).to eq(Date.new(2024, 1, 15))
    end
  end

  describe ".validate_event" do
    it "returns the same event when all required fields are present" do
      event = build_event

      expect(scraper.validate_event(event)).to equal(event)
    end

    {
      title: { title: "" },
      date: { date: nil },
      venue: { venue: nil },
      url: { url: "" },
      source: { source: "" },
    }.each do |field, overrides|
      it "raises ParseError when #{field} is missing" do
        event = build_event(overrides)

        expect { scraper.validate_event(event) }
          .to raise_error(WeeklyLocalEvents::ParseError, /#{field}/)
      end
    end

    it "rejects a venue whose name is blank" do
      event = build_event(venue: WeeklyLocalEvents::Venue.new(name: "  "))

      expect { scraper.validate_event(event) }
        .to raise_error(WeeklyLocalEvents::ParseError, /venue is missing or empty/)
    end

    it "reports every invalid field in one error" do
      event = build_event(title: "", url: "", source: "")

      expect { scraper.validate_event(event) }
        .to raise_error(WeeklyLocalEvents::ParseError, /title is empty.*url is empty.*source is empty/)
    end
  end

  describe "#normalize_time" do
    it "normalizes 12-hour times to 24-hour format" do
      expect(scraper.normalize_time("7:00 PM")).to eq("19:00")
      expect(scraper.normalize_time("7pm")).to eq("19:00")
    end

    it "handles midnight and noon" do
      expect(scraper.normalize_time("12:00 AM")).to eq("00:00")
      expect(scraper.normalize_time("12:00 PM")).to eq("12:00")
    end

    it "passes through already-normalized and compact times" do
      expect(scraper.normalize_time("19:00")).to eq("19:00")
      expect(scraper.normalize_time("1900")).to eq("19:00")
    end

    it "returns nil for nil or blank input" do
      expect(scraper.normalize_time(nil)).to be_nil
      expect(scraper.normalize_time("  ")).to be_nil
    end

    it "returns unrecognized input unchanged" do
      expect(scraper.normalize_time("sometime around dinner")).to eq("sometime around dinner")
    end
  end

  describe "#scrape_page" do
    it "fetches a relative path against the base URL and parses the response" do
      allow(scraper).to receive(:fetch).with("https://example.com/events").and_return(:document)
      allow(scraper).to receive(:parse_response).with(:document).and_return([:event])

      expect(scraper.scrape_page("/events")).to eq([:event])
    end

    it "uses an absolute URL unchanged" do
      allow(scraper).to receive(:fetch).with("https://other.example.com/events").and_return(:document)
      allow(scraper).to receive(:parse_response).with(:document).and_return([])

      expect(scraper.scrape_page("https://other.example.com/events")).to eq([])
    end

    it "returns an empty array when the page is not found" do
      allow(scraper).to receive(:fetch).and_raise(WeeklyLocalEvents::NotFoundError)

      expect(scraper.scrape_page("/events")).to eq([])
      expect(logger).to have_received(:info).with(/Page not found/)
    end

    it "returns an empty array when rate limited" do
      allow(scraper).to receive(:fetch).and_raise(WeeklyLocalEvents::RateLimitError)

      expect(scraper.scrape_page("/events")).to eq([])
      expect(logger).to have_received(:error).with(/Rate limit hit/)
    end

    it "returns an empty array on any other fetch error" do
      allow(scraper).to receive(:fetch).and_raise(StandardError, "network down")

      expect(scraper.scrape_page("/events")).to eq([])
      expect(logger).to have_received(:error).with(/Error scraping/)
    end
  end

  describe "abstract base class interface" do
    it "requires subclasses to implement #events" do
      expect { scraper.events }.to raise_error(NotImplementedError, /must implement #events/)
    end

    it "requires subclasses to implement #parse_response" do
      expect { scraper.parse_response(html_response) }
        .to raise_error(NotImplementedError, /must implement #parse_response/)
    end

    it "delegates #scrape to #events" do
      allow(scraper).to receive(:events).and_return(:events)

      expect(scraper.scrape).to eq(:events)
    end
  end
end
