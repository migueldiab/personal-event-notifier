# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/do512_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::Do512Scraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "do512", base_url: "https://www.do512.com",
      date_range: date_range, user_agent: "TestBot/1.0", rate_limit_delay: 0.1 }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <div class="ds-listing event-card ds-event-category-live-music" data-ds-ga-label="day" data-permalink="/events/2026/11/25/diles-que-no-me-maten-tickets" itemprop="event" itemscope="" itemtype="http://schema.org/Event">
        <a href="/events/2026/11/25/diles-que-no-me-maten-tickets" itemprop="url" class="ds-listing-event-title url summary">
          <span class="ds-byline">Resound Presents:</span>
          <span class="ds-listing-event-title-text" itemprop="name">Diles que no me maten</span>
        </a>
        <div class="ds-venue-name" itemprop="location" itemscope="" itemtype="http://schema.org/Place">
          <a href="/venues/29th-street-ballroom" itemprop="url"><span itemprop="name">29th Street Ballroom</span></a>
        </div>
        <div class="ds-event-time dtstart">7:00PM (doors)</div>
        <meta itemprop="startDate" datetime="2026-11-25T19:00">
      </div>
    HTML
  end

  let(:sample_html_free) do
    <<~HTML
      <div class="ds-listing event-card ds-event-category-live-music" data-permalink="/events/2026/11/25/drinksgiving-2026-tickets">
        <a href="/events/2026/11/25/drinksgiving-2026-tickets" itemprop="url" class="ds-listing-event-title url summary">
          <span class="ds-byline">Hotel Vegas presents</span>
          <span class="ds-listing-event-title-text">Drinksgiving 2026: Spirals, SHWING!</span>
        </a>
        <ul class="ds-listing-banners">
          <li class="ds-listing-soldout"><span>Free</span></li>
        </ul>
        <div class="ds-venue-name" itemprop="location">
          <a href="/venues/hotel-vegas"><span itemprop="name">Hotel Vegas</span></a>
        </div>
        <div class="ds-event-time dtstart">8:00PM</div>
        <meta itemprop="startDate" datetime="2026-11-25T20:00">
      </div>
    HTML
  end

  let(:sample_html_multiple) do
    <<~HTML
      <div class="ds-listing event-card ds-event-category-live-music" data-permalink="/events/2026/11/25/event-one">
        <a href="/events/2026/11/25/event-one" itemprop="url" class="ds-listing-event-title url summary">
          <span class="ds-listing-event-title-text">Event One</span>
        </a>
        <div class="ds-venue-name"><a><span itemprop="name">Venue A</span></a></div>
        <div class="ds-event-time dtstart">7:00PM</div>
        <meta itemprop="startDate" datetime="2026-11-25T19:00">
      </div>
      <div class="ds-listing event-card ds-event-category-art-culture" data-permalink="/events/2026/11/26/event-two">
        <a href="/events/2026/11/26/event-two" itemprop="url" class="ds-listing-event-title url summary">
          <span class="ds-listing-event-title-text">Event Two</span>
        </a>
        <div class="ds-venue-name"><a><span itemprop="name">Venue B</span></a></div>
        <div class="ds-event-time dtstart">3:00PM</div>
        <meta itemprop="startDate" datetime="2026-11-26T15:00">
      </div>
    HTML
  end

  describe "#initialize" do
    it "sets the name to do512" do
      expect(scraper.name).to eq("do512")
    end

    it "sets the base_url to the Do512 URL" do
      expect(scraper.base_url).to eq("https://www.do512.com")
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
      expect(events.size).to eq(1)
    end

    it "extracts title from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].title).to eq("Diles que no me maten")
    end

    it "extracts date from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].date).to eq(Date.new(2026, 11, 25))
    end

    it "extracts time from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].time).to eq("19:00")
    end

    it "extracts venue from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].venue.name).to eq("29th Street Ballroom")
    end

    it "extracts URL from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].url).to eq("https://www.do512.com/events/2026/11/25/diles-que-no-me-maten-tickets")
    end

    it "extracts description from byline" do
      events = scraper.parse_response(sample_html)
      expect(events[0].description).to eq("Resound Presents:")
    end

    it "handles free events" do
      events = scraper.parse_response(sample_html_free)
      expect(events[0].price).to eq("Free")
      expect(events[0].price_cents).to eq(0)
    end

    it "parses multiple events" do
      events = scraper.parse_response(sample_html_multiple)
      expect(events.size).to eq(2)
      expect(events[0].title).to eq("Event One")
      expect(events[1].title).to eq("Event Two")
    end

    it "handles missing time gracefully" do
      html_no_time = <<~HTML
        <div class="ds-listing event-card" data-permalink="/events/2026/11/25/no-time">
          <a href="/events/2026/11/25/no-time" class="ds-listing-event-title url summary">
            <span class="ds-listing-event-title-text">No Time Event</span>
          </a>
          <div class="ds-venue-name"><a><span itemprop="name">Some Venue</span></a></div>
        </div>
      HTML
      events = scraper.parse_response(html_no_time)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Time Event")
    end

    it "handles missing venue gracefully" do
      html_no_venue = <<~HTML
        <div class="ds-listing event-card" data-permalink="/events/2026/11/25/no-venue">
          <a href="/events/2026/11/25/no-venue" class="ds-listing-event-title url summary">
            <span class="ds-listing-event-title-text">No Venue Event</span>
          </a>
          <div class="ds-event-time dtstart">7:00PM</div>
        </div>
      HTML
      events = scraper.parse_response(html_no_venue)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Venue Event")
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
        <div class="ds-listing event-card" data-permalink="/events/2026/11/25/no-title">
          <div class="ds-venue-name"><a><span itemprop="name">Some Venue</span></a></div>
        </div>
      HTML
      events = scraper.parse_response(html_no_title)
      expect(events).to be_empty
    end
  end

  describe "#events" do
    it "returns an array of Event objects" do
      stub_request(:get, %r{https://www.do512.com/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, %r{https://www.do512.com/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, %r{https://www.do512.com/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, %r{https://www.do512.com/events/\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end
  end

  describe "#build_events_url" do
    it "builds correct URL for a given date" do
      date = Date.new(2026, 11, 25)
      url = scraper.send(:build_events_url, date, 1)
      expect(url).to eq("https://www.do512.com/events/?date=2026-11-25")
    end

    it "adds page parameter for pagination" do
      date = Date.new(2026, 11, 25)
      url = scraper.send(:build_events_url, date, 3)
      expect(url).to eq("https://www.do512.com/events/?date=2026-11-25&page=3")
    end
  end

  describe "#normalize_price" do
    it "handles free events" do
      expect(scraper.normalize_price("Free")).to eq(0)
      expect(scraper.normalize_price("FREE")).to eq(0)
    end

    it "handles simple prices" do
      expect(scraper.normalize_price("$15")).to eq(1500)
      expect(scraper.normalize_price("10")).to eq(1000)
    end
  end

  describe "#normalize_time" do
    it "converts 12h to 24h format" do
      expect(scraper.normalize_time("7:00 PM")).to eq("19:00")
      expect(scraper.normalize_time("3:00 PM")).to eq("15:00")
    end

    it "handles midnight and noon" do
      expect(scraper.normalize_time("12:00 AM")).to eq("00:00")
      expect(scraper.normalize_time("12:00 PM")).to eq("12:00")
    end
  end
end
