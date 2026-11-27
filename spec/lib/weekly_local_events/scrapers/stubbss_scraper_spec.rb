# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/stubbss_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::StubbssScraper do
  subject(:scraper) { described_class.new(config) }

  # A hash config keeps retries instant (no backoff sleeps); the scraper
  # builds its own Config internally, whose logger we replace with a double.
  # reference_date pins MM/DD parsing to the Wayback capture date so the
  # expected dates are deterministic.
  let(:config) do
    { name: "stubbss", base_url: described_class::BASE_URL,
      rate_limit_delay: 0, max_retries: 1,
      reference_date: Date.new(2026, 10, 11) }
  end
  let(:logger) { instance_double(Logger, warn: nil, info: nil, error: nil) }
  let(:events_url) { "https://stubbsaustin.com/concert-listings/" }
  let(:page_two_url) { "https://stubbsaustin.com/concert-listings/?page=2" }

  # Verbatim #tw-responsive block from the 2026-10-11 Wayback snapshot.
  let(:fixture_path) { File.expand_path("../../../fixtures/stubbs_concert_listings.html", __dir__) }
  let(:fixture_html) { File.read(fixture_path) }
  let(:html_with_next_link) do
    "#{fixture_html}\n<a rel=\"next\" href=\"/concert-listings/?page=2\">Next</a>"
  end
  let(:page_two_html) do
    card_html(title: "Blues Night", date: "12/2", time: "Show: 8:00pm",
              detail_href: "https://stubbsaustin.com/tm-event/blues-night/")
  end
  let(:incomplete_html) do
    card_html(title: "Mystery Show", date: "", time: "", detail_href: "https://stubbsaustin.com/tm-event/mystery-show/")
  end
  let(:empty_html) do
    "<html><body><div class=\"tm-paginate\"></div><p>No events scheduled.</p></body></html>"
  end

  # A single card reduced to the markup the real site actually emits.
  def card_html(title:, **opts)
    date = opts.fetch(:date, "10/11")
    time = opts.fetch(:time, "Show: 7:00pm")
    detail_href = opts[:detail_href]
    ticket_href = opts[:ticket_href]
    price = opts.fetch(:price, "")
    venue = opts.fetch(:venue, "")
    name = if detail_href
             %(<div class="tw-name"><a href="#{detail_href}">#{title}</a></div>)
           else
             %(<div class="tw-name">#{title}</div>)
           end
    ticket = if ticket_href
               %(<a href="#{ticket_href}" class="button button-primary tw-buy-tix-btn tw_onsale">Buy Tickets</a>)
             else
               ""
             end

    <<~HTML
      <div id="tw-responsive" class="event-list">
        <div class="tw-plugin-upcoming-event-list">
          <div class="container">
            <div class="tw-section">
              <div class="row">
                <div class="four columns date-img-wrapper">
                  <div class="tw-event-datetime">
                    <div class="tw-date-time date-col">
                      <span class="tw-day-of-week">Sun</span>
                      <span class="tw-event-date">#{date}</span>
                    </div>
                  </div>
                </div>
                <div class="five columns">
                  #{name}
                  <div class="tw-venue-details">#{venue}</div>
                  <div class="tw-date-time">
                    <span class="tw-event-time-complete">
                      <span class="tw-event-time">#{time}</span>
                    </span>
                  </div>
                  <div class="tw-age-restriction">All Ages</div>
                </div>
                <div class="three columns">
                  <div class="tw-info-price-buy-tix">
                    <span class="tw-price">#{price}</span>
                    #{ticket}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
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
    it "sets the name and canonical base URL for Stubb's" do
      expect(scraper.name).to eq("stubbss")
      expect(scraper.base_url).to eq("https://stubbsaustin.com")
    end

    it "inherits from BaseScraper and honours the supplied rate settings" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
      expect(scraper.rate_limit_delay).to eq(0.0)
      expect(scraper.max_retries).to eq(1)
    end
  end

  describe "#events" do
    it "parses the real concert-listings markup into Event objects" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: fixture_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events.size).to eq(24)

      event = events.first
      expect(event.title).to eq("Gospel Brunch: The Levites")
      expect(event.date).to eq(Date.new(2026, 10, 11))
      expect(event.time).to eq("10:30")
      expect(event.begin_time).to eq("10:30")
      expect(event.venue.name).to eq("Stubb's Bar-B-Q")
      expect(event.url).to eq("https://stubbsaustin.com/tm-event/gospel-brunch-the-levites-11/")
      expect(event.source).to eq("stubbss")
      expect(event.tags).to include("All Ages")
    end

    it "decodes HTML entities and follows the /tm-event/ detail link" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: fixture_html, headers: { "Content-Type" => "text/html" })

      event = scraper.events[1]

      expect(event.title).to eq("Cavetown – Running With Scissors Tour")
      expect(event.date).to eq(Date.new(2026, 10, 13))
      expect(event.time).to eq("19:00")
      expect(event.url).to eq("https://stubbsaustin.com/tm-event/cavetown-running-with-scissors-tour/")
    end

    it "rolls MM/DD dates already past into the following year" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: fixture_html, headers: { "Content-Type" => "text/html" })

      titles = scraper.events.map(&:title)

      vacations = scraper.events.find { |event| event.title.start_with?("Vacations") }
      saint_levant = scraper.events.find { |event| event.title.start_with?("SAINT LEVANT") }
      expect(titles.size).to eq(24)
      expect(vacations.date).to eq(Date.new(2027, 3, 12))
      expect(saint_levant.date).to eq(Date.new(2027, 4, 20))
    end

    it "collects events from every page linked by a next-page element" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: html_with_next_link, headers: { "Content-Type" => "text/html" })
      stub_request(:get, page_two_url)
        .to_return(status: 200, body: page_two_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events.map(&:title)).to eq(scraper.parse_response(fixture_html).map(&:title) + ["Blues Night"])
      expect(a_request(:get, events_url)).to have_been_made.once
      expect(a_request(:get, page_two_url)).to have_been_made.once
    end

    it "defaults missing fields without dropping an otherwise valid card" do
      stub_request(:get, events_url)
        .to_return(status: 200, body: incomplete_html, headers: { "Content-Type" => "text/html" })

      events = scraper.events

      expect(events.size).to eq(1)
      event = events.first
      expect(event.title).to eq("Mystery Show")
      expect(event.date).to be_nil
      expect(event.begin_time).to be_nil
      expect(event.price_cents).to be_nil
      # Event#initialize coerces nil price/time/description to empty strings.
      expect(event.price).to eq("")
      expect(event.time).to eq("")
      expect(event.description).to eq("")
      expect(event.venue.name).to eq("Stubb's Bar-B-Q")
      expect(event.url).to eq("https://stubbsaustin.com/tm-event/mystery-show/")
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

      expect(budgeted.events.size).to eq(25)
      expect(a_request(:get, events_url)).to have_been_made.once
      expect(a_request(:get, page_two_url)).to have_been_made.once
    end
  end

  describe "ticket links" do
    it "uses an external Buy Tickets link when the real card has no title anchor" do
      ticket_url = "https://www.ticketmaster.com/event/1A0099B2C3D4E5F6"
      html = card_html(title: "Big Show", date: "12/10", time: "Show: 8:00pm",
                       ticket_href: ticket_url)
      stub_request(:get, events_url)
        .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })

      event = scraper.events.first

      expect(event.title).to eq("Big Show")
      expect(event.date).to eq(Date.new(2026, 12, 10))
      expect(event.venue.name).to eq("Stubb's Bar-B-Q")
      expect(event.url).to eq(ticket_url)
    end

    it "prefers the /tm-event/ detail link over the ticket CTA" do
      ticket_url = "https://www.ticketmaster.com/event/ZZZZ"
      detail_url = "https://stubbsaustin.com/tm-event/big-show/"
      html = card_html(title: "Big Show", detail_href: detail_url, ticket_href: ticket_url)
      stub_request(:get, events_url)
        .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })

      expect(scraper.events.first.url).to eq(detail_url)
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
      html = card_html(title: "")

      expect(scraper.parse_response(html)).to eq([])
    end
  end
end
