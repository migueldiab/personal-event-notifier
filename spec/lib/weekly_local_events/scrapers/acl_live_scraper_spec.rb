# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "json"
require "weekly_local_events/scrapers/acl_live_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::ACLLiveScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "acl_live", base_url: "https://www.acllive.com",
      date_range: date_range, user_agent: "TestBot/1.0", rate_limit_delay: 0.1 }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <html>
      <head><title>Events | Austin City Limits Live</title></head>
      <body>
        <h1>Upcoming Events</h1>
        <div class="event-card">
          <span class="event-date">Nov 27, 2026</span>
          <h4>ACL Live at The Moody Theater</h4>
          <h3>Michael Martin Murphey's Cowboy Christmas</h3>
          <a href="/event/2026-11-27-michael-martin-murphey-s-cowboy-christmas-at-8-pm">Get Tickets</a>
          <span class="event-time">8:00 PM</span>
        </div>
        <div class="event-card">
          <span class="event-date">Nov 28, 2026</span>
          <h4>ACL Live at 3TEN</h4>
          <h3>Bob Schneider & The Moonlight Orchestra</h3>
          <a href="/event/2026-11-28-bob-schneider-and-the-moonlight-orchestra-at-8-pm">Get Tickets</a>
          <span class="event-time">8:00 PM</span>
        </div>
      </body>
      </html>
    HTML
  end

  let(:sample_html_single_event) do
    <<~HTML
      <html>
      <body>
        <div class="event-card">
          <span class="event-date">Dec 1, 2026</span>
          <h4>ACL Live at The Moody Theater</h4>
          <h3>Kansas</h3>
          <a href="/event/2026-12-01-kansas-at-8-pm">Get Tickets</a>
          <span class="event-time">8:00 PM</span>
        </div>
      </body>
      </html>
    HTML
  end

  let(:event_page_html) do
    <<~HTML
      <html>
      <head><title>Michael Martin Murphey's Cowboy Christmas - ACL Live at The Moody Theater</title></head>
      <body>
        <h1>Michael Martin Murphey's Cowboy Christmas</h1>
        <p class="event-date">Friday, Nov 27, 2026</p>
        <p class="event-time">8:00 PM</p>
        <p class="description">Michael Martin Murphey, "singing cowboy poet", is not only the number one, best-selling singer/songwriter of American Cowboy Music, he's one of the world's most respected singer/songwriters in the Pop and Country-Western field.</p>
        <p class="price">Tickets from $45</p>
        <a href="https://www.acllive.com/tickets" class="get-tickets">Get Tickets</a>
      </body>
      </html>
    HTML
  end

  describe "#initialize" do
    it "sets the name to acl_live" do
      expect(scraper.name).to eq("acl_live")
    end

    it "sets the base_url to the ACL Live URL" do
      expect(scraper.base_url).to eq("https://www.acllive.com")
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

    it "sets date_range_days to 30" do
      # Duration = end_date - start_date + 1
      expect(scraper.date_range.duration).to eq(31)
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
      expect(events[0].title).to eq("Michael Martin Murphey's Cowboy Christmas")
      expect(events[1].title).to eq("Bob Schneider & The Moonlight Orchestra")
    end

    it "extracts date from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].date).to eq(Date.new(2026, 11, 27))
      expect(events[1].date).to eq(Date.new(2026, 11, 28))
    end

    it "extracts venue from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].venue.name).to eq("ACL Live at The Moody Theater")
      expect(events[1].venue.name).to eq("ACL Live at 3TEN")
    end

    it "extracts URL from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].url).to eq("https://www.acllive.com/event/2026-11-27-michael-martin-murphey-s-cowboy-christmas-at-8-pm")
      expect(events[1].url).to eq("https://www.acllive.com/event/2026-11-28-bob-schneider-and-the-moonlight-orchestra-at-8-pm")
    end

    it "extracts time from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].time).to eq("20:00")
      expect(events[1].time).to eq("20:00")
    end

    it "handles single event" do
      events = scraper.parse_response(sample_html_single_event)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Kansas")
      expect(events[0].date).to eq(Date.new(2026, 12, 1))
    end

    it "handles missing time gracefully" do
      html_no_time = <<~HTML
        <html><body>
          <div class="event-card">
            <span class="event-date">Nov 30, 2026</span>
            <h4>ACL Live at The Moody Theater</h4>
            <h3>No Time Event</h3>
          </div>
        </body></html>
      HTML
      events = scraper.parse_response(html_no_time)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Time Event")
      # Event.to_s converts nil to "" for optional fields
      expect(events[0].time).to eq("")
    end

    it "handles missing venue gracefully" do
      html_no_venue = <<~HTML
        <html><body>
          <div class="event-card">
            <span class="event-date">Nov 30, 2026</span>
            <h3>Event Without Venue</h3>
          </div>
        </body></html>
      HTML
      events = scraper.parse_response(html_no_venue)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Event Without Venue")
      # Should default to the main venue
      expect(events[0].venue.name).to eq("ACL Live at The Moody Theater")
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
        <html><body>
          <div class="event-card">
            <span class="event-date">Nov 30, 2026</span>
            <h4>ACL Live at The Moody Theater</h4>
          </div>
        </body></html>
      HTML
      events = scraper.parse_response(html_no_title)
      expect(events).to be_empty
    end

    it "extracts description from linked event page" do
      stub_request(:get, /https:\/\/www\.acllive\.com\/event\//)
        .to_return(status: 200, body: event_page_html, headers: { "Content-Type" => "text/html" })

      events = scraper.parse_response(sample_html, fetch_details: true)
      expect(events[0].description).to include("Michael Martin Murphey")
    end

    it "extracts price from linked event page" do
      stub_request(:get, /https:\/\/www\.acllive\.com\/event\//)
        .to_return(status: 200, body: event_page_html, headers: { "Content-Type" => "text/html" })

      events = scraper.parse_response(sample_html, fetch_details: true)
      expect(events[0].price).to eq("Tickets from $45")
    end

    it "handles event page fetch failure gracefully" do
      stub_request(:get, /https:\/\/www\.acllive\.com\/event\//)
        .to_raise(Errno::ECONNREFUSED)

      events = scraper.parse_response(sample_html, fetch_details: true)
      expect(events.size).to eq(2)
      # Event.to_s converts nil to "" for optional fields
      expect(events[0].description).to eq("")
    end
  end

  describe "#events" do
    # The scraper now walks the pagination endpoint after the first page.
    before do
      stub_request(:get, %r{https://www\.acllive\.com/events/events_ajax/\d+})
        .to_return(status: 200, body: "\"\"", headers: { "Content-Type" => "application/json" })
    end

    it "returns an array of Event objects" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end
  end

  describe "#normalize_price" do
    it "handles free events" do
      expect(scraper.normalize_price("Free")).to eq(0)
      expect(scraper.normalize_price("FREE")).to eq(0)
    end

    it "handles simple prices" do
      expect(scraper.normalize_price("$15")).to eq(1500)
      expect(scraper.normalize_price("$45")).to eq(4500)
    end

    it "handles price ranges" do
      expect(scraper.normalize_price("$10-50")).to eq(1000)
    end
  end

  describe "#normalize_time" do
    it "converts 12h to 24h format" do
      expect(scraper.normalize_time("8:00 PM")).to eq("20:00")
      expect(scraper.normalize_time("7:00 PM")).to eq("19:00")
    end

    it "handles midnight and noon" do
      expect(scraper.normalize_time("12:00 AM")).to eq("00:00")
      expect(scraper.normalize_time("12:00 PM")).to eq("12:00")
    end

    it "handles time without minutes" do
      expect(scraper.normalize_time("7 PM")).to eq("19:00")
    end
  end

  # Verbatim capture from https://www.acllive.com/events on 2026-11-27 (CST),
  # plus the JSON-wrapped HTML fragment from /events/events_ajax/12.
  describe "live ACL Live markup" do
    let(:live_events_body) do
      File.read(File.expand_path("../../../fixtures/acllive_events.html", __dir__))
    end
    let(:live_ajax_body) do
      File.read(File.expand_path("../../../fixtures/acllive_ajax_12.json", __dir__))
    end
    let(:live_scraper) { described_class.new(config_with_range) }

    it "parses all 12 real event cards from the /events page" do
      expect(live_scraper.parse_response(live_events_body).size).to eq(12)
    end

    it "excludes the Vue template event card" do
      titles = live_scraper.parse_response(live_events_body).map(&:title)
      expect(titles).not_to include("{{decodeURI(data.name)}}")
    end

    it "extracts title, date, venue and URL from the live card markup" do
      first = live_scraper.parse_response(live_events_body).first
      expect(first.title).to eq("Michael Martin Murphey's Cowboy Christmas")
      expect(first.date).to eq(Date.new(2026, 11, 27))
      expect(first.venue.name).to eq("ACL Live at The Moody Theater")
      expect(first.url).to eq(
        "https://www.acllive.com/event/2026-11-27-michael-martin-murphey-s-cowboy-christmas-at-8-pm",
      )
    end

    it "normalizes dates with repeated whitespace in the date span" do
      ben = live_scraper.parse_response(live_events_body).find { |event| event.title == "Eric Benét" }
      expect(ben.date).to eq(Date.new(2026, 12, 1))
    end

    it "maps data-venue=3 to 3TEN and derives its category" do
      poi = live_scraper.parse_response(live_events_body).find { |event| event.title == "Poi Dog Pondering" }
      expect(poi.venue.name).to eq("ACL Live at 3TEN")
      expect(poi.category).to eq("3TEN ACL Live")
    end

    it "parses a JSON-wrapped AJAX fragment into events" do
      events = live_scraper.parse_ajax_response(live_ajax_body)
      expect(events.size).to eq(12)
      expect(events.first.title).to eq("Ben Schwartz & Friends")
    end

    it "derives the show time from the event URL slug" do
      echos = live_scraper.parse_ajax_response(live_ajax_body).find { |event| event.title == "Echos" }
      expect(echos.time).to eq("19:30")
    end
  end

  describe "#events with AJAX pagination" do
    let(:live_events_body) do
      File.read(File.expand_path("../../../fixtures/acllive_events.html", __dir__))
    end
    let(:live_ajax_body) do
      File.read(File.expand_path("../../../fixtures/acllive_ajax_12.json", __dir__))
    end
    let(:live_scraper) { described_class.new(config_with_range) }
    let(:empty_json) { "\"\"" }

    it "walks the AJAX pages and returns every unique event" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 200, body: live_events_body)
      stub_request(:get, %r{events_ajax/12\?})
        .to_return(status: 200, body: live_ajax_body, headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{events_ajax/24\?})
        .to_return(status: 200, body: empty_json, headers: { "Content-Type" => "application/json" })

      events = live_scraper.events
      expect(events.size).to eq(24)
      expect(events.map(&:url).uniq.size).to eq(24)
      expect(events.last.title).to eq("Underoath")
    end

    it "deduplicates events that repeat across pages" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 200, body: live_events_body)
      stub_request(:get, %r{events_ajax/12\?})
        .to_return(status: 200, body: JSON.generate(live_events_body))
      stub_request(:get, %r{events_ajax/24\?})
        .to_return(status: 200, body: empty_json)

      expect(live_scraper.events.size).to eq(12)
    end

    it "stops when the AJAX endpoint returns 406" do
      stub_request(:get, "https://www.acllive.com/events")
        .to_return(status: 200, body: live_events_body)
      stub_request(:get, %r{events_ajax/12\?}).to_return(status: 406)

      expect(live_scraper.events.size).to eq(12)
    end

    it "does not request AJAX pages when the primary page fails" do
      stub_request(:get, "https://www.acllive.com/events").to_raise(Errno::ECONNREFUSED)

      expect(live_scraper.events).to be_empty
      expect(a_request(:get, %r{events_ajax})).not_to have_been_made
    end
  end
end
