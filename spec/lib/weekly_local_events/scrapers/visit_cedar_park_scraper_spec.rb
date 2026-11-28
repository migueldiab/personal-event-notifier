# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/visit_cedar_park_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::VisitCedarParkScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { { rate_limit_delay: 0, max_retries: 1 } }
  let(:fixture_path) do
    "/home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/visit_cedar_park_events.json"
  end
  let(:fixture_payload) { JSON.parse(File.read(fixture_path)) }
  let(:token_url) { "#{described_class::BASE_URL}#{described_class::TOKEN_PATH}" }
  let(:events_url_pattern) do
    %r{\A#{Regexp.escape(described_class::BASE_URL)}#{Regexp.escape(described_class::EVENTS_PATH)}}
  end
  let(:token_body) { "0123456789abcdef0123456789abcdef" }
  let(:json_headers) { { "Content-Type" => "application/json; charset=utf-8" } }

  def payload_for(docs, count: docs.size)
    { "docs" => { "count" => count, "docs" => docs } }
  end

  def event_doc(overrides = {})
    {
      "title" => "Test Event",
      "date" => "2026-12-02T05:59:59.000Z",
      "absoluteUrl" => "https://visitcedarparktexas.com/event/test-event/",
    }.merge(overrides)
  end

  describe "constants and initialization" do
    it "uses the expected source name" do
      expect(described_class::SOURCE_NAME).to eq("visit_cedar_park")
      expect(scraper.name).to eq("visit_cedar_park")
    end

    it "uses the Simpleview REST endpoints" do
      expect(described_class::BASE_URL).to eq("https://visitcedarparktexas.com")
      expect(described_class::EVENTS_PATH).to eq(
        "/includes/rest_v2/plugins_events_events_by_date/find/",
      )
      expect(described_class::TOKEN_PATH).to eq("/plugins/core/get_simple_token/")
      expect(scraper.base_url).to eq(described_class::BASE_URL)
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end

    it "sends a browser-like user agent and a referer" do
      expect(scraper.user_agent).to include("Mozilla/5.0")
      expect(scraper.headers).to include("Referer" => "https://visitcedarparktexas.com/events/")
    end
  end

  describe "#parse_response" do
    it "parses all 30 real events from the discovery fixture" do
      events = scraper.parse_response(fixture_payload)

      expect(events.size).to eq(30)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events).to all(be_valid)
      expect(events.map(&:source).uniq).to eq(["visit_cedar_park"])
    end

    it "maps every documented field from the first fixture event" do
      event = scraper.parse_response(fixture_payload).first

      expect(event.title).to eq("Kiddie Gym - Open Play")
      expect(event.date).to eq(Date.new(2026, 11, 27))
      expect(event.url).to eq("https://visitcedarparktexas.com/event/kiddie-gym-open-play/2230/")
      expect(event.venue.name).to eq("Little Land")
      expect(event.category).to eq("Fun For The Whole Family")
      expect(event.description).to start_with("Our play gym")
      expect(event.description).not_to include("<p>")
      expect(event.price).to include("15$ per child")
      expect(event.image_url).to start_with("https://assets.simpleviewinc.com/")
    end

    it "normalizes startTime to 24-hour HH:MM" do
      event = scraper.parse_response(fixture_payload).find { |e| e.title == "Free Live Music" }

      expect(event.time).to eq("19:00")
      expect(event.begin_time).to eq("19:00")
    end

    it "returns an empty array for malformed or empty payloads" do
      expect(scraper.parse_response(nil)).to eq([])
      expect(scraper.parse_response({})).to eq([])
      expect(scraper.parse_response({ "docs" => {} })).to eq([])
      expect(scraper.parse_response("not json")).to eq([])
    end

    it "accepts a JSON string payload" do
      events = scraper.parse_response(JSON.generate(payload_for([event_doc])))

      expect(events.size).to eq(1)
      expect(events.first.title).to eq("Test Event")
    end

    it "skips entries without a usable date or URL" do
      docs = [
        event_doc("title" => "No date", "date" => nil, "dates" => {}, "nextDate" => nil),
        event_doc("title" => "Bad date", "date" => "not-a-date"),
        event_doc("title" => "No URL", "absoluteUrl" => nil, "url" => nil),
        event_doc("title" => "Keep me"),
      ]

      events = scraper.parse_response(payload_for(docs))

      expect(events.map(&:title)).to eq(["Keep me"])
    end

    it "uses hostname then the default venue when location is missing" do
      docs = [
        event_doc("title" => "Hosted", "location" => nil, "hostname" => "Haute Spot"),
        event_doc("title" => "Unknown venue", "location" => nil, "hostname" => nil),
      ]

      events = scraper.parse_response(payload_for(docs))

      expect(events.map { |event| event.venue.name }).to eq(["Haute Spot", "Cedar Park, TX"])
    end

    it "builds venue address and coordinates from the event data" do
      doc = event_doc(
        "location" => "Little Land",
        "address1" => "200 Buttercup Creek Blvd",
        "city" => "Cedar Park",
        "state" => "TX",
        "zip" => "78613",
        "latitude" => 30.5023048,
        "longitude" => -97.8219236,
      )

      venue = scraper.parse_response(payload_for([doc])).first.venue

      expect(venue.address).to eq("200 Buttercup Creek Blvd")
      expect(venue.city).to eq("Cedar Park")
      expect(venue.state).to eq("TX")
      expect(venue.zip).to eq("78613")
      expect(venue.lat).to eq(30.5023048)
      expect(venue.lng).to eq(-97.8219236)
    end

    it "resolves a relative url against the base URL" do
      doc = event_doc("absoluteUrl" => nil, "url" => "/event/test-event/")
      event = scraper.parse_response(payload_for([doc])).first

      expect(event.url).to eq("https://visitcedarparktexas.com/event/test-event/")
    end

    it "prefers the primary category and falls back to the first category" do
      docs = [
        event_doc(
          "categories" => [
            { "catName" => "Concerts", "catId" => "1" },
            { "catName" => "Free", "catId" => "2" },
          ],
          "primarycatid" => "2",
        ),
        event_doc(
          "categories" => [{ "catName" => "Festivals", "catId" => "3" }],
          "primarycatid" => nil,
        ),
      ]

      events = scraper.parse_response(payload_for(docs))

      expect(events.map(&:category)).to eq(["Free", "Festivals"])
    end

    it "falls back to teaser for description and to admission for price" do
      doc = event_doc(
        "description" => nil,
        "teaser" => "<p>Short &amp; sweet</p>",
        "admission" => "$10 at the door",
      )
      event = scraper.parse_response(payload_for([doc])).first

      expect(event.description).to eq("Short & sweet")
      expect(event.price).to eq("$10 at the door")
      expect(event.price_cents).to eq(1000)
    end

    it "keeps an external ticket link as the buy url" do
      doc = event_doc("linkUrl" => "https://tickets.example.com/event")
      event = scraper.parse_response(payload_for([doc])).first

      expect(event.buy_url).to eq("https://tickets.example.com/event")
    end
  end

  describe "date normalization" do
    it "converts an end-of-day UTC instant to the prior America/Chicago calendar date" do
      doc = event_doc("date" => "2026-11-28T05:59:59.000Z")

      expect(scraper.parse_response(payload_for([doc])).first.date).to eq(Date.new(2026, 11, 27))
    end

    it "uses daylight-saving time for a summer UTC instant" do
      doc = event_doc("date" => "2026-07-02T05:59:59.000Z")

      # CDT is UTC-5, so 05:59:59Z is 00:59 on the same calendar day.
      expect(scraper.parse_response(payload_for([doc])).first.date).to eq(Date.new(2026, 7, 2))
    end

    it "accepts date-only values without shifting the day" do
      doc = event_doc("date" => "2026-12-25")

      expect(scraper.parse_response(payload_for([doc])).first.date).to eq(Date.new(2026, 12, 25))
    end

    it "falls back to dates.eventDate then nextDate" do
      docs = [
        event_doc("date" => nil, "dates" => { "eventDate" => "2026-12-03T05:59:59.000Z" }),
        event_doc("date" => nil, "dates" => {}, "nextDate" => "2026-12-04T05:59:59.000Z"),
      ]

      events = scraper.parse_response(payload_for(docs))

      expect(events.map(&:date)).to eq([Date.new(2026, 12, 2), Date.new(2026, 12, 3)])
    end

    it "normalizes a human-readable time from the times field" do
      doc = event_doc("startTime" => nil, "times" => "Starting: 7:00 PM")

      expect(scraper.parse_response(payload_for([doc])).first.time).to eq("19:00")
    end
  end

  describe "#events" do
    before do
      stub_request(:get, token_url).to_return(status: 200, body: token_body)
    end

    let(:first_doc) { event_doc("title" => "First Event") }
    let(:second_doc) { event_doc("title" => "Second Event") }

    it "fetches the token and returns events from every page" do
      stub_request(:get, events_url_pattern).to_return(
        { status: 200, body: JSON.generate(payload_for([first_doc], count: 31)), headers: json_headers },
        { status: 200, body: JSON.generate(payload_for([second_doc], count: 31)), headers: json_headers },
      )

      expect(scraper.events.map(&:title)).to eq(["First Event", "Second Event"])
      expect(a_request(:get, token_url)).to have_been_made.once
      expect(a_request(:get, events_url_pattern)).to have_been_made.twice
    end

    it "advances skip by the page size across requests" do
      stub_request(:get, events_url_pattern).to_return(
        { status: 200, body: JSON.generate(payload_for([first_doc], count: 31)), headers: json_headers },
        { status: 200, body: JSON.generate(payload_for([second_doc], count: 31)), headers: json_headers },
      )
      scraper.events

      requests = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select do |request|
        request.uri.to_s.include?(described_class::EVENTS_PATH)
      end
      skips = requests.map do |request|
        options = JSON.parse(URI.decode_www_form(request.uri.query.to_s).to_h.fetch("json"))
        options.fetch("options").fetch("skip")
      end

      expect(skips).to eq([0, 30])
    end

    it "stops when a page returns no documents" do
      stub_request(:get, events_url_pattern).to_return(
        { status: 200, body: JSON.generate(payload_for([first_doc], count: 100)), headers: json_headers },
        { status: 200, body: JSON.generate(payload_for([], count: 100)), headers: json_headers },
      )

      expect(scraper.events.map(&:title)).to eq(["First Event"])
      expect(a_request(:get, events_url_pattern)).to have_been_made.twice
    end

    it "returns no events when the token endpoint is blocked" do
      stub_request(:get, token_url).to_return(status: 403, body: "Access Denied")
      stub_request(:get, events_url_pattern).to_return(
        status: 200, body: JSON.generate(payload_for([first_doc])), headers: json_headers,
      )

      expect(scraper.events).to eq([])
      expect(a_request(:get, events_url_pattern)).not_to have_been_made
    end

    it "treats an invalid-credentials token response as a failure" do
      stub_request(:get, token_url).to_return(status: 200, body: "Invalid credentials")
      stub_request(:get, events_url_pattern).to_return(
        status: 200, body: JSON.generate(payload_for([first_doc])), headers: json_headers,
      )

      expect(scraper.events).to eq([])
      expect(a_request(:get, events_url_pattern)).not_to have_been_made
    end

    it "returns no events when the API responds with a fake success body" do
      stub_request(:get, events_url_pattern).to_return(status: 200, body: "Invalid credentials")

      expect(scraper.events).to eq([])
    end

    it "sends the browser UA and Referer on both requests" do
      stub_request(:get, events_url_pattern).to_return(
        status: 200, body: JSON.generate(payload_for([first_doc])), headers: json_headers,
      )
      scraper.events

      expect(
        a_request(:get, token_url).with(
          headers: { "Referer" => "https://visitcedarparktexas.com/events/", "User-Agent" => /Mozilla\/5\.0/ },
        ),
      ).to have_been_made.once
      expect(
        a_request(:get, events_url_pattern).with(
          headers: { "Referer" => "https://visitcedarparktexas.com/events/", "User-Agent" => /Mozilla\/5\.0/ },
        ),
      ).to have_been_made.once
    end
  end
end
