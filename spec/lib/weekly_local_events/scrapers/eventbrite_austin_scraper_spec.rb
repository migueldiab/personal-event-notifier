# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/eventbrite_austin_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::EventbriteAustinScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "eventbrite_austin", base_url: "https://www.eventbrite.com",
      date_range: date_range, user_agent: "TestBot/1.0", rate_limit_delay: 0.1 }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <!DOCTYPE html>
      <html lang="en-us">
      <head><title>Austin, TX Events</title></head>
      <body>
        <section class="discover-vertical-event-card">
          <div class="event-card event-card__vertical" data-event-id="1996475889128" data-event-category="food-and-drink" data-event-paid-status="paid">
            <a href="https://www.eventbrite.com/e/meet-the-winemaker-a-louis-roederer-four-course-paired-dinner-tickets-1996475889128" class="event-card-link" aria-label="View Meet the Winemaker: A Louis Roederer Four-Course Paired Dinner">
              <h3 class="Typography_body-lg__10ijx event-card__clamp-line--two">Meet the Winemaker: A Louis Roederer Four-Course Paired Dinner</h3>
            </a>
            <p class="Typography_body-md-bold__10ijx">Sat, Dec 5 •  5:30 PM</p>
            <p class="Typography_body-md__10ijx event-card__clamp-line--one">Central Market Austin North Lamar</p>
            <div class="DiscoverVerticalEventCard-module__priceWrapper___usWo6">
              <span>$75</span>
            </div>
          </div>
        </section>
        <section class="discover-vertical-event-card">
          <div class="event-card event-card__vertical" data-event-id="2003689538347" data-event-category="music" data-event-paid-status="paid">
            <a href="https://www.eventbrite.com/e/soundcheck-tickets-2003689538347" class="event-card-link" aria-label="View SOUNDCHECK">
              <h3 class="Typography_body-lg__10ijx event-card__clamp-line--two">SOUNDCHECK</h3>
            </a>
            <p class="Typography_body-md-bold__10ijx">Sat, Dec 12 •  7:00 PM</p>
            <p class="Typography_body-md__10ijx event-card__clamp-line--one">The Royale Room</p>
            <div class="DiscoverVerticalEventCard-module__priceWrapper___usWo6">
              <div class="loading-skeleton-md">
                <div class="shimmer-effect"></div>
              </div>
            </div>
          </div>
        </section>
      </body>
      </html>
    HTML
  end

  let(:sample_html_free) do
    <<~HTML
      <!DOCTYPE html>
      <html lang="en-us">
      <body>
        <section class="discover-vertical-event-card">
          <div class="event-card event-card__vertical" data-event-id="2004420333174" data-event-category="community" data-event-paid-status="free">
            <a href="https://www.eventbrite.com/e/operation-turkey-downtown-austin-2026-tickets-2004420333174" class="event-card-link" aria-label="View Operation Turkey Downtown Austin 2026">
              <h3 class="Typography_body-lg__10ijx event-card__clamp-line--two">Operation Turkey Downtown Austin 2026</h3>
            </a>
            <p class="Typography_body-md-bold__10ijx">Tomorrow •  8:00 AM</p>
            <p class="Typography_body-md__10ijx event-card__clamp-line--one">Juliet Italian Kitchen</p>
            <div class="DiscoverVerticalEventCard-module__priceWrapper___usWo6">
              <span>Free</span>
            </div>
          </div>
        </section>
      </body>
      </html>
    HTML
  end

  let(:sample_html_no_venue) do
    <<~HTML
      <!DOCTYPE html>
      <html lang="en-us">
      <body>
        <section class="discover-vertical-event-card">
          <div class="event-card event-card__vertical" data-event-id="1997551526388" data-event-category="education" data-event-paid-status="paid">
            <a href="https://www.eventbrite.com/e/the-mi5-archive-official-secrets-tickets-1997551526388" class="event-card-link" aria-label="View The MI5 Archive: Official Secrets">
              <h3 class="Typography_body-lg__10ijx event-card__clamp-line--two">The MI5 Archive: Official Secrets</h3>
            </a>
            <p class="Typography_body-md-bold__10ijx">Friday •  2:00 PM</p>
            <div class="DiscoverVerticalEventCard-module__priceWrapper___usWo6">
              <span>£25</span>
            </div>
          </div>
        </section>
      </body>
      </html>
    HTML
  end

  describe "#initialize" do
    it "sets the name to eventbrite_austin" do
      expect(scraper.name).to eq("eventbrite_austin")
    end

    it "sets the base_url to the Eventbrite URL" do
      expect(scraper.base_url).to eq("https://www.eventbrite.com")
    end

    it "sets a proper user agent" do
      expect(scraper.user_agent).to include("WeeklyLocalEvents")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end

    it "sets rate_limit_delay to 3.0" do
      expect(scraper.rate_limit_delay).to eq(3.0)
    end
  end

  describe "#parse_response" do
    it "parses event listings from HTML" do
      events = scraper.parse_response(sample_html)
      expect(events).to be_an(Array)
      expect(events.size).to eq(2)
    end

    it "extracts title from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].title).to eq("Meet the Winemaker: A Louis Roederer Four-Course Paired Dinner")
      expect(events[1].title).to eq("SOUNDCHECK")
    end

    it "extracts date from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].date).to eq(Date.new(2026, 12, 5))
      expect(events[1].date).to eq(Date.new(2026, 12, 12))
    end

    it "extracts time from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].time).to eq("17:30")
      expect(events[1].time).to eq("19:00")
    end

    it "extracts venue from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].venue.name).to eq("Central Market Austin North Lamar")
      expect(events[1].venue.name).to eq("The Royale Room")
    end

    it "extracts URL from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].url).to eq("https://www.eventbrite.com/e/meet-the-winemaker-a-louis-roederer-four-course-paired-dinner-tickets-1996475889128")
      expect(events[1].url).to eq("https://www.eventbrite.com/e/soundcheck-tickets-2003689538347")
    end

    it "extracts category from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].category).to eq("Food and drink")
      expect(events[1].category).to eq("Music")
    end

    it "handles free events" do
      events = scraper.parse_response(sample_html_free)
      expect(events[0].price).to eq("Free")
      expect(events[0].price_cents).to eq(0)
    end

    it "handles paid events" do
      events = scraper.parse_response(sample_html)
      expect(events[0].price_cents).to eq(7500)
    end

    it "handles events without price (skeleton)" do
      events = scraper.parse_response(sample_html)
      expect(events[1].price).to be_empty
      expect(events[1].price_cents).to be_nil
    end

    it "handles events without venue" do
      events = scraper.parse_response(sample_html_no_venue)
      expect(events[0].title).to eq("The MI5 Archive: Official Secrets")
      expect(events[0].venue).to be_nil
    end

    it "returns empty array for empty HTML" do
      events = scraper.parse_response("<html><body></body></html>")
      expect(events).to be_empty
    end

    it "returns empty array for nil input" do
      events = scraper.parse_response(nil)
      expect(events).to be_empty
    end

    it "skips events without a title" do
      html_no_title = <<~HTML
        <!DOCTYPE html>
        <html lang="en-us">
        <body>
          <section class="discover-vertical-event-card">
            <div class="event-card event-card__vertical">
              <p class="Typography_body-md__10ijx event-card__clamp-line--one">Some Venue</p>
            </div>
          </section>
        </body>
        </html>
      HTML
      events = scraper.parse_response(html_no_title)
      expect(events).to be_empty
    end
  end

  describe "#events" do
    it "returns an array of Event objects" do
      stub_request(:get, %r{https://www.eventbrite.com/d/tx--austin/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, %r{https://www.eventbrite.com/d/tx--austin/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, %r{https://www.eventbrite.com/d/tx--austin/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, %r{https://www.eventbrite.com/d/tx--austin/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end
  end

  describe "#build_events_url" do
    it "builds correct URL for a given date" do
      date = Date.new(2026, 11, 25)
      url = scraper.send(:build_events_url, date)
      expect(url).to eq("/d/tx--austin/events/?date=2026-11-25")
    end
  end

  describe "#normalize_price" do
    it "handles free events" do
      expect(scraper.normalize_price("Free")).to eq(0)
      expect(scraper.normalize_price("FREE")).to eq(0)
    end

    it "handles simple prices" do
      expect(scraper.normalize_price("$75")).to eq(7500)
      expect(scraper.normalize_price("25")).to eq(2500)
    end
  end

  describe "#normalize_time" do
    it "converts 12h to 24h format" do
      expect(scraper.normalize_time("5:30 PM")).to eq("17:30")
      expect(scraper.normalize_time("7:00 PM")).to eq("19:00")
    end

    it "handles midnight and noon" do
      expect(scraper.normalize_time("12:00 AM")).to eq("00:00")
      expect(scraper.normalize_time("12:00 PM")).to eq("12:00")
    end
  end
end
