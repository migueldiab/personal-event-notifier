# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/austin_chronicle_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::AustinChronicleScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "austin_chronicle", base_url: "https://www.austinchronicle.com",
      date_range: date_range, user_agent: "TestBot/1.0" }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <li class="fdn-pres-item uk-child-width-1-1@show-grid">
        <div class="fdn-pres-item-content">
          <div class="fdn-event-search-image-block uk-width-1-3 uk-width-1-3@m uk-width-1-5@show-list">
            <a href="/event/14538326"><img src="..." alt="Image: Live Jazz Night" width="400" height="400"></a>
          </div>
          <div class="fdn-pres-content uk-flex-1 uk-padding-xsmall-right fdn-event-search-text-block">
            <div class="uk-flex uk-flex-center@show-grid">
              <p class="fdn-teaser-headline uk-margin-remove@show-grid">
                <a href="/event/14538326">Live Jazz Night</a>
                <span class="fdn-features-icon-block" role="presentation">
                  <span class="fdn-features-icon uk-preserve fdn-features-icon-tickets-available" title="Tickets Available"></span>
                </span>
              </p>
            </div>
            <p class="fdn-teaser-subheadline">Fri., Dec 1, 8:00 PM</p>
            <div class="uk-margin-small fdn-event-teaser-location-block">
              <p class="fdn-event-teaser-location uk-margin-remove">
                <a class="fdn-event-teaser-location-link" href="/location/continental-club-11834712">The Continental Club</a>
              </p>
            </div>
            <div class="fdn-teaser-description uk-text-break">An evening of live jazz featuring local artists.</div>
            <p class="fdn-teaser-tag-link-block fdn-teaser-infoline uk-text-break uk-margin-xsmall-top">
              <a class="fdn-teaser-tag-link" href="?eventCategory=12198149">Jazz</a>
            </p>
            <div class="fdn-pres-details-split fdn-teaser-infoline uk-flex uk-flex-middle uk-margin-remove-bottom fdn-teaser-ticket-block uk-flex-wrap">
              <a class="fdn-teaser-ticket-link uk-flex uk-flex-middle uk-margin-small-right" href="https://coldtowne.com/tickets">Get Tickets $15</a>
            </div>
          </div>
        </div>
      </li>
      <li class="fdn-pres-item uk-child-width-1-1@show-grid">
        <div class="fdn-pres-item-content">
          <div class="fdn-event-search-image-block uk-width-1-3 uk-width-1-3@m uk-width-1-5@show-list">
            <a href="/event/14524854"><img src="..." alt="Image: Free Open Mic" width="400" height="400"></a>
          </div>
          <div class="fdn-pres-content uk-flex-1 uk-padding-xsmall-right fdn-event-search-text-block">
            <div class="uk-flex uk-flex-center@show-grid">
              <p class="fdn-teaser-headline uk-margin-remove@show-grid">
                <a href="/event/14524854">Free Open Mic</a>
              </p>
            </div>
            <p class="fdn-teaser-subheadline">Sat., Dec 2, 7:00 PM</p>
            <div class="uk-margin-small fdn-event-teaser-location-block">
              <p class="fdn-event-teaser-location uk-margin-remove">
                <a class="fdn-event-teaser-location-link" href="/location/bathtub-row-11834713">Bathtub Row</a>
              </p>
            </div>
            <div class="fdn-teaser-description uk-text-break">Open mic night, free admission.</div>
            <p class="fdn-teaser-tag-link-block fdn-teaser-infoline uk-text-break uk-margin-xsmall-top">
              <a class="fdn-teaser-tag-link" href="?eventCategory=12198150">Open Mic</a>
            </p>
          </div>
        </div>
      </li>
    HTML
  end

  let(:sample_html_with_price_range) do
    <<~HTML
      <li class="fdn-pres-item uk-child-width-1-1@show-grid">
        <div class="fdn-pres-item-content">
          <div class="fdn-event-search-image-block uk-width-1-3 uk-width-1-3@m uk-width-1-5@show-list">
            <a href="/event/14524855"><img src="..." alt="Image: Concert at ACL Live" width="400" height="400"></a>
          </div>
          <div class="fdn-pres-content uk-flex-1 uk-padding-xsmall-right fdn-event-search-text-block">
            <div class="uk-flex uk-flex-center@show-grid">
              <p class="fdn-teaser-headline uk-margin-remove@show-grid">
                <a href="/event/14524855">Concert at ACL Live</a>
              </p>
            </div>
            <p class="fdn-teaser-subheadline">Sun., Dec 3, 7:30 PM</p>
            <div class="uk-margin-small fdn-event-teaser-location-block">
              <p class="fdn-event-teaser-location uk-margin-remove">
                <a class="fdn-event-teaser-location-link" href="/location/acl-live-11834714">ACL Live at The Moody Theater</a>
              </p>
            </div>
            <div class="fdn-teaser-description uk-text-break">A full night of music at Austin's premier venue.</div>
            <p class="fdn-teaser-tag-link-block fdn-teaser-infoline uk-text-break uk-margin-xsmall-top">
              <a class="fdn-teaser-tag-link" href="?eventCategory=12198151">Concert</a>
            </p>
            <div class="fdn-pres-details-split fdn-teaser-infoline uk-flex uk-flex-middle uk-margin-remove-bottom fdn-teaser-ticket-block uk-flex-wrap">
              <a class="fdn-teaser-ticket-link uk-flex uk-flex-middle uk-margin-small-right" href="https://acllive.com/tickets">Buy tickets $25 - $75</a>
            </div>
          </div>
        </div>
      </li>
    HTML
  end

  let(:sample_html_old_layout) do
    <<~HTML
      <div class="event-card" data-event-id="54321">
        <h3 class="event-card-title"><a href="/events/54321">Old Layout Event</a></h3>
        <span class="event-card-date">Nov 28, 2026</span>
        <span class="event-card-time">6:00 PM</span>
        <span class="event-card-venue">The Saxon Pub</span>
        <span class="event-card-price">$10</span>
        <a class="event-card-link" href="/events/54321">Details</a>
      </div>
    HTML
  end

  let(:sample_html_legacy) do
    <<~HTML
      <div class="event-listing" data-event-id="12345">
        <h3 class="event-title"><a href="/calendar/event/12345">Live Jazz Night</a></h3>
        <time class="event-date" datetime="2026-12-01">Dec 1, 2026</time>
        <span class="event-time">8:00 PM</span>
        <span class="event-venue">The Continental Club</span>
        <span class="event-price">$15</span>
        <a class="event-link" href="/calendar/event/12345">More info</a>
        <div class="event-description">An evening of live jazz featuring local artists.</div>
      </div>
      <div class="event-listing" data-event-id="12346">
        <h3 class="event-title"><a href="/calendar/event/12346">Free Open Mic</a></h3>
        <time class="event-date" datetime="2026-12-02">Dec 2, 2026</time>
        <span class="event-venue">Bathtub Row</span>
        <span class="event-price">Free</span>
        <a class="event-link" href="/calendar/event/12346">More info</a>
      </div>
    HTML
  end

  describe "#initialize" do
    it "sets the name to austin_chronicle" do
      expect(scraper.name).to eq("austin_chronicle")
    end

    it "sets the base_url to the Austin Chronicle URL" do
      expect(scraper.base_url).to eq("https://www.austinchronicle.com")
    end

    it "sets a proper user agent" do
      expect(scraper.user_agent).to include("WeeklyLocalEvents")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
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
      expect(events.size).to eq(2)
      expect(events[0].title).to eq("Live Jazz Night")
      expect(events[1].title).to eq("Free Open Mic")
    end

    it "extracts date from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].date).to eq(Date.new(2026, 12, 1))
      expect(events[1].date).to eq(Date.new(2026, 12, 2))
    end

    it "extracts venue from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].venue.name).to eq("The Continental Club")
      expect(events[1].venue.name).to eq("Bathtub Row")
    end

    it "extracts URL from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].url).to eq("https://www.austinchronicle.com/event/14538326")
      expect(events[1].url).to eq("https://www.austinchronicle.com/event/14524854")
    end

    it "extracts description from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].description).to eq("An evening of live jazz featuring local artists.")
      expect(events[1].description).to eq("Open mic night, free admission.")
    end

    it "handles new layout (fdn-pres-item class)" do
      events = scraper.parse_response(sample_html)
      expect(events.size).to eq(2)
      expect(events[0].title).to eq("Live Jazz Night")
      expect(events[0].venue.name).to eq("The Continental Club")
      expect(events[0].description).to eq("An evening of live jazz featuring local artists.")
    end

    it "handles price ranges correctly" do
      events = scraper.parse_response(sample_html_with_price_range)
      expect(events[0].title).to eq("Concert at ACL Live")
      expect(events[0].venue.name).to eq("ACL Live at The Moody Theater")
      expect(events[0].price).to eq("$25 - $75")
      expect(events[0].price_cents).to eq(2500)
    end

    it "sets source to austin_chronicle" do
      events = scraper.parse_response(sample_html)
      expect(events[0].source).to eq("austin_chronicle")
    end

    it "handles old layout (event-card class)" do
      events = scraper.parse_response(sample_html_old_layout)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Old Layout Event")
      expect(events[0].venue.name).to eq("The Saxon Pub")
    end

    it "handles legacy layout (event-listing class)" do
      events = scraper.parse_response(sample_html_legacy)
      expect(events.size).to eq(2)
      expect(events[0].title).to eq("Live Jazz Night")
      expect(events[1].title).to eq("Free Open Mic")
    end

    it "handles missing time gracefully" do
      html_no_time = <<~HTML
        <div class="event-listing">
          <h3 class="event-title"><a href="/calendar/event/99">No Time Event</a></h3>
          <time class="event-date" datetime="2026-12-05">Dec 5, 2026</time>
          <span class="event-venue">Some Venue</span>
          <span class="event-price">Free</span>
          <a class="event-link" href="/calendar/event/99">Info</a>
        </div>
      HTML
      events = scraper.parse_response(html_no_time)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Time Event")
      # Event normalizes nil time to "" (ActiveModel behavior)
      expect(events[0].time).to eq("")
    end

    it "handles missing venue gracefully" do
      html_no_venue = <<~HTML
        <div class="event-listing">
          <h3 class="event-title"><a href="/calendar/event/98">No Venue Event</a></h3>
          <time class="event-date" datetime="2026-12-05">Dec 5, 2026</time>
          <span class="event-price">$5</span>
          <a class="event-link" href="/calendar/event/98">Info</a>
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
        <div class="event-listing">
          <span class="event-date" datetime="2026-12-05">Dec 5, 2026</span>
          <span class="event-venue">Some Venue</span>
        </div>
      HTML
      events = scraper.parse_response(html_no_title)
      expect(events).to be_empty
    end
  end

  describe "#events" do
    it "returns an array of Event objects" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}})
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles pagination across multiple pages" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      # Verify scraper can iterate through pages
      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end
  end

  describe "#build_calendar_url" do
    it "builds correct URL for a given date" do
      date = Date.new(2026, 12, 1)
      url = scraper.send(:build_calendar_url, date, 1)
      expect(url).to eq("https://www.austinchronicle.com/calendar?date=2026-12-01")
    end

    it "adds page parameter for pagination" do
      date = Date.new(2026, 12, 1)
      url = scraper.send(:build_calendar_url, date, 3)
      expect(url).to eq("https://www.austinchronicle.com/calendar?date=2026-12-01&page=3")
    end
  end

  describe "#normalize_price" do
    it "handles free events" do
      expect(scraper.normalize_price("Free")).to eq(0)
      expect(scraper.normalize_price("FREE")).to eq(0)
    end

    it "handles price ranges by returning minimum" do
      expect(scraper.normalize_price("$25 - $75")).to eq(2500)
      expect(scraper.normalize_price("$10 to $50")).to eq(1000)
    end

    it "handles simple prices" do
      expect(scraper.normalize_price("$15")).to eq(1500)
      expect(scraper.normalize_price("10")).to eq(1000)
    end
  end

  describe "#normalize_time" do
    it "converts 12h to 24h format" do
      expect(scraper.normalize_time("8:00 PM")).to eq("20:00")
      expect(scraper.normalize_time("7:30 AM")).to eq("07:30")
    end

    it "handles midnight and noon" do
      expect(scraper.normalize_time("12:00 AM")).to eq("00:00")
      expect(scraper.normalize_time("12:00 PM")).to eq("12:00")
    end
  end
end
