# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/stubbss_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::StubbssScraper do
  subject(:scraper) { described_class.new(config) }

  # A hash config keeps retries instant (no backoff sleeps); the scraper
  # builds its own Config internally, whose logger we replace with a double.
  let(:config) do
    { name: "stubbss", base_url: described_class::BASE_URL,
      rate_limit_delay: 0, max_retries: 1 }
  end
  let(:logger) { instance_double(Logger, warn: nil, info: nil, error: nil) }
  let(:events_url) { "https://www.stubbsaustin.com/events/" }
  let(:page_two_url) { "https://www.stubbsaustin.com/events/?page=2" }

  let(:sample_html) do
    <<~HTML
      <div class="event-card">
        <h3><a href="/events/2026-12-01-jazz-night">Jazz Night</a></h3>
        <time datetime="2026-12-01T19:30:00">December 1, 2026</time>
        <span class="time">7:30 PM</span>
        <span class="venue">Stubb's Bar-B-Q</span>
        <span class="price">$25</span>
        <p class="description">An evening of jazz.</p>
      </div>
    HTML
  end

  let(:page_two_html) do
    <<~HTML
      <div class="event-card">
        <h3><a href="/events/2026-12-02-blues-night">Blues Night</a></h3>
        <time datetime="2026-12-02T20:00:00">December 2, 2026</time>
        <span class="time">8:00 PM</span>
        <span class="venue">Stubb's Bar-B-Q</span>
        <span class="price">$18</span>
      </div>
    HTML
  end

  let(:html_with_next_link) do
    <<~HTML
      #{sample_html}
      <a class="next" href="/events/?page=2">Next</a>
    HTML
  end

  let(:incomplete_html) do
    <<~HTML
      <div class="event-card">
        <h3><a href="/events/2026-12-05-mystery-show">Mystery Show</a></h3>
      </div>
    HTML
  end

  let(:empty_html) do
    <<~HTML
      <html><body><p>No events scheduled.</p></body></html>
    HTML
  end

  before do
    allow(scraper.config).to receive(:logger).and_return(logger)
  end

  describe "#initialize" do
    it "sets the name and base URL for Stubb's" do
      expect(scraper.name).to eq("stubbss")
      expect(scraper.base_url).to eq("https://www.stubbsaustin.com")
    end

    it "inherits from BaseScraper and honours the supplied rate settings" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
      expect(scraper.rate_limit_delay).to eq(0.0)
      expect(scraper.max_retries).to eq(1)
    end
  end

  describe "#events" do
    it "returns Event objects with the correct fields from a valid response" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events.size).to eq(1)

      event = events.first
      expect(event.title).to eq("Jazz Night")
      expect(event.date).to eq(Date.new(2026, 12, 1))
      expect(event.time).to eq("19:30")
      expect(event.venue.name).to eq("Stubb's Bar-B-Q")
      expect(event.price).to eq("$25")
      expect(event.price_cents).to eq(2500)
      expect(event.url).to eq("https://www.stubbsaustin.com/events/2026-12-01-jazz-night")
      expect(event.source).to eq("stubbss")
      expect(event.description).to eq("An evening of jazz.")
    end

    it "collects events from every page linked by a next-page element" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: html_with_next_link, headers: { "Content-Type" => "text/html" })
      stub_request(:get, page_two_url)
        .to_return(status: 200, body: page_two_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events.map(&:title)).to eq(["Jazz Night", "Blues Night"])
      expect(events[0].url).to eq("https://www.stubbsaustin.com/events/2026-12-01-jazz-night")
      expect(events[1].url).to eq("https://www.stubbsaustin.com/events/2026-12-02-blues-night")
      expect(a_request(:get, events_url)).to have_been_made.once
      expect(a_request(:get, page_two_url)).to have_been_made.once
    end

    it "sets missing fields to nil (or empty string for Event-normalized fields)" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: incomplete_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events.size).to eq(1)
      event = events.first
      expect(event.title).to eq("Mystery Show")
      expect(event.date).to be_nil
      expect(event.venue).to be_nil
      expect(event.price_cents).to be_nil
      # Event#initialize coerces nil price/time/description to empty strings.
      expect(event.price).to eq("")
      expect(event.time).to eq("")
      expect(event.description).to eq("")
      expect(event.url).to eq("https://www.stubbsaustin.com/events/2026-12-05-mystery-show")
      expect(event.source).to eq("stubbss")
    end

    it "returns an empty array and logs a warning when the network fails" do
      stub_request(:get, events_url).to_raise(Errno::ECONNREFUSED)

      expect(scraper.events).to eq([])
      expect(logger).to have_received(:error).with(%r{Attempt 1/1 failed})
      expect(logger).to have_received(:warn).with(/\[stubbss\] Failed to fetch/)
    end

    it "returns an empty array and logs a warning when the page has no event cards" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: empty_html, headers: { "Content-Type" => "text/html" })

      expect(scraper.events).to eq([])
      expect(logger).to have_received(:warn).with(/No event cards found/)
    end

    it "returns an empty array when the page responds with 404" do
      stub_request(:get, events_url).to_return(status: 404)

      expect(scraper.events).to eq([])
      expect(logger).to have_received(:warn).with(/Failed to fetch/)
    end
  end

  describe "#parse_response" do
    it "returns an empty array for nil input" do
      expect(scraper.parse_response(nil)).to eq([])
    end

    it "returns an empty array for HTML with no event cards" do
      expect(scraper.parse_response(empty_html)).to eq([])
    end

    it "skips cards that have no title" do
      html = <<~HTML
        <div class="event-card">
          <span class="venue">Stubb's Bar-B-Q</span>
          <span class="price">$25</span>
        </div>
      HTML

      expect(scraper.parse_response(html)).to eq([])
    end
  end
end
