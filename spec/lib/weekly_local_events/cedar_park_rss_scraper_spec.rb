# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "weekly_local_events/scrapers/cedar_park_rss_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::CedarParkRssScraper do
  let(:config) { WeeklyLocalEvents::Config.new }
  let(:scraper) { described_class.new(config) }
  let(:cassette_name) { "cedar_park_calendar_rss" }
  let(:cassette_path) { File.join(VCR_CASSETTE_DIR, "#{cassette_name}.yml") }

  # The cassette was recorded from the live public CivicEngage feed and replays
  # with record: :none; WebMock blocks every unrecorded request in spec_helper.
  def replay_events
    VCR.use_cassette(cassette_name, record: :none, match_requests_on: %i[method uri]) do
      scraper.events
    end
  end

  describe "#events from the recorded live feed" do
    let(:events) { replay_events }

    it "parses the feed into events with absolute Cedar Park calendar links" do
      expect(events.length).to be >= 3
      expect(events.length).to eq(15)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events.map(&:source).uniq).to eq(["cedar_park_rss"])
      expect(events.map(&:url)).to all(
        start_with("https://www.cedarparktexas.gov/Calendar.aspx?EID=")
      )
    end

    it "gives every item a distinct EID-derived dedupe key" do
      keys = events.map { |event| scraper.dedupe_key(event) }

      expect(keys).to all(match(/\Acedar_park_rss:\d+\z/))
      expect(keys.uniq.length).to eq(events.length)
      expect(events.map { |event| event.tags.grep(/\Aeid:\d+\z/) }.flatten.length).to eq(events.length)
    end

    context "with EID=4323" do
      let(:event) { events.find { |candidate| candidate.url.include?("EID=4323") } }

      it "uses the event dates and times in America/Chicago, not pubDate" do
        expect(event.title).to eq("Courts and Track Closed for Resurfacing")
        expect(event.date).to eq(Date.new(2026, 11, 23))
        expect(event.date).not_to eq(Date.new(2026, 11, 2)) # pubDate is 2026-11-02
        expect(event.time).to eq("00:00")
        expect(event.begin_time).to eq("00:00")
        expect(event.end_time).to eq("23:59")
      end

      it "resolves the event start in America/Chicago" do
        start_time = scraper.starts_at(event)

        expect(start_time).to eq(Time.new(2026, 11, 23, 0, 0, 0, "-06:00"))
        expect(start_time.utc_offset).to eq(-21_600)
      end

      it "carries the location and EID tag, and no price" do
        expect(event.venue.name).to eq("Cedar Park, TX 78613")
        expect(event.venue.state).to eq("TX")
        expect(scraper.dedupe_key(event)).to eq("cedar_park_rss:4323")
        expect(event.tags).to include("eid:4323")
        expect(event.price.to_s).to be_empty
        expect(event.price_cents).to be_nil
      end
    end
  end

  describe "#parse_response" do
    let(:xml) do
      <<~XML
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:calendarEvent="https://www.cedarparktexas.gov/Calendar.aspx">
          <channel>
            <item>
              <title>CANCELLED: Flashback Friday</title>
              <link>https://www.cedarparktexas.gov/Calendar.aspx?EID=9999</link>
              <pubDate>Mon, 02 Nov 2026 16:24:24 -0600</pubDate>
              <description>&lt;strong&gt;Event dates:&lt;/strong&gt; November 23, 2026</description>
              <calendarEvent:EventDates>November 23, 2026</calendarEvent:EventDates>
              <calendarEvent:EventTimes>06:00 PM - 09:00 PM</calendarEvent:EventTimes>
              <calendarEvent:Location>450 Cypress Creek Road, Cedar Park, TX 78613</calendarEvent:Location>
            </item>
          </channel>
        </rss>
      XML
    end

    it "flags CANCELLED: titles while keeping the original title and event details" do
      event = scraper.parse_response(xml).first

      expect(event.title).to eq("CANCELLED: Flashback Friday")
      expect(event.tags).to include("cancelled")
      expect(event.date).to eq(Date.new(2026, 11, 23))
      expect(event.begin_time).to eq("18:00")
      expect(event.end_time).to eq("21:00")
      expect(event.venue.name).to eq("450 Cypress Creek Road, Cedar Park, TX 78613")
    end
  end

  describe "recorded cassette provenance" do
    it "replays a 200 XML response without credentials" do
      interaction = YAML.load_file(cassette_path).fetch("http_interactions").fetch(0)
      request = interaction.fetch("request")

      expect(interaction.dig("response", "status", "code")).to eq(200)
      expect(interaction.dig("response", "body", "string")).to include("EID=4323")
      expect(request.fetch("headers").keys.map(&:downcase)).not_to include(
        a_string_matching(/cookie|authorization|api[-_]?key/)
      )
    end
  end

  describe "registry integration" do
    it "is known to and enabled in the scraper registry" do
      registry = WeeklyLocalEvents::ScraperRegistry.new(config)

      expect(WeeklyLocalEvents::ScraperRegistry::KNOWN_SCRAPERS).to include(
        "cedar_park_rss" => "WeeklyLocalEvents::Scrapers::CedarParkRssScraper"
      )
      expect(WeeklyLocalEvents::ScraperRegistry::DEFAULT_SCRAPERS).to include("cedar_park_rss")
      expect(registry.get("cedar_park_rss")).to be_a(described_class)
    end
  end
end
