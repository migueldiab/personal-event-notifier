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

  # Build a scraper with different politeness settings while keeping the
  # logger stubbed, so no example can emit real log noise or really sleep.
  def build_scraper(overrides = {})
    described_class.new(config.merge(overrides)).tap do |instance|
      allow(instance.config).to receive(:logger).and_return(logger)
    end
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
      expect(event.begin_time).to eq("19:30")
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
      expect(event.begin_time).to be_nil
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

  describe "rate limiting" do
    it "defaults to a polite 2 second delay (about 30 requests per minute)" do
      expect(described_class.new.rate_limit_delay).to eq(2.0)
      expect(described_class::DEFAULT_RATE_LIMIT_DELAY).to eq(2.0)
    end

    it "accepts request_delay as an alias for rate_limit_delay" do
      expect(build_scraper(rate_limit_delay: nil, request_delay: 7.5).rate_limit_delay).to eq(7.5)
    end

    it "waits the configured delay before giving up on a failed request" do
      polite = build_scraper(rate_limit_delay: 0.25, max_retries: 2)
      allow(polite).to receive(:sleep)
      stub_request(:get, events_url).to_return(status: 500)

      expect(polite.events).to eq([])
      expect(polite).to have_received(:sleep).with(0.25).once
      expect(a_request(:get, events_url)).to have_been_made.once
    end

    it "does not back off at all when max_retries is one" do
      immediate = build_scraper(rate_limit_delay: 0.25, max_retries: 1)
      allow(immediate).to receive(:sleep)
      stub_request(:get, events_url).to_return(status: 500)

      expect(immediate.events).to eq([])
      expect(immediate).not_to have_received(:sleep)
    end

    it "does not retry or wait when the site returns 429" do
      stub_request(:get, events_url).to_return(status: 429, headers: { "Retry-After" => "60" })

      expect(scraper.events).to eq([])
      expect(logger).to have_received(:warn).with(/\[stubbss\] Failed to fetch.*Rate limited/)
      expect(a_request(:get, events_url)).to have_been_made.once
    end

    it "never makes more requests than max_pages allows" do
      budgeted = build_scraper(max_pages: 2)
      stub_request(:get, events_url)
        .to_return(status: 200, body: html_with_next_link, headers: { "Content-Type" => "text/html" })
      stub_request(:get, page_two_url)
        .to_return(status: 200, body: page_two_html, headers: { "Content-Type" => "text/html" })

      expect(budgeted.events.map(&:title)).to eq(["Jazz Night", "Blues Night"])
      expect(a_request(:get, events_url)).to have_been_made.once
      expect(a_request(:get, page_two_url)).to have_been_made.once
    end
  end

  describe "ticket links" do
    it "uses an external Buy Tickets link when the card has no title anchor" do
      ticket_url = "https://www.ticketmaster.com/event/1A0099B2C3D4E5F6"
      html = <<~HTML
        <div class="event-card">
          <h3>Big Show</h3>
          <time datetime="2026-12-10T20:00:00">December 10, 2026</time>
          <span class="time">8:00 PM</span>
          <span class="venue">Stubb's Waller Creek Amphitheater</span>
          <a class="buy-tickets" href="#{ticket_url}">Buy Tickets</a>
        </div>
      HTML
      stub_request(:get, events_url)
        .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })

      event = scraper.events.first

      expect(event.title).to eq("Big Show")
      expect(event.date).to eq(Date.new(2026, 12, 10))
      expect(event.venue.name).to eq("Stubb's Waller Creek Amphitheater")
      expect(event.url).to eq(ticket_url)
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
