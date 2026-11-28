# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "weekly_local_events/scrapers/cedar_park_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::CedarParkScraper do
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

  def item_xml(title:, eid:, dates: nil, times: nil, location: nil, link: nil,
               category: nil, description: nil, price: nil)
    parts = ["<item>", "<title>#{title}</title>"]
    parts << "<link>#{link || "https://www.cedarparktexas.gov/Calendar.aspx?EID=#{eid}"}</link>"
    parts << "<description>#{description}</description>" if description
    parts << "<category>#{category}</category>" if category
    parts << "<price>#{price}</price>" if price
    parts << "<calendarEvent:EventDates>#{dates}</calendarEvent:EventDates>" if dates
    parts << "<calendarEvent:EventTimes>#{times}</calendarEvent:EventTimes>" if times
    parts << "<calendarEvent:Location>#{location}</calendarEvent:Location>" if location
    parts << "</item>"
    parts.join("\n")
  end

  def feed_xml(items, channel_extras: "")
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:calendarEvent="https://www.cedarparktexas.gov/Calendar.aspx"
           xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>Cedar Park, TX - Calendar</title>
          #{channel_extras}
          #{items.join("\n")}
        </channel>
      </rss>
    XML
  end

  describe "constants and configuration" do
    it "exposes the cedar_park source and the live feed endpoints" do
      expect(described_class::SOURCE_NAME).to eq("cedar_park")
      expect(described_class::BASE_URL).to eq("https://www.cedarparktexas.gov")
      expect(described_class::EVENTS_PATH).to start_with("/RSSFeed.aspx?")
      expect(described_class::FEED_URL).to eq(
        "https://www.cedarparktexas.gov/RSSFeed.aspx?CID=All-calendar.xml&ModID=58"
      )
    end

    it "uses the city Parks & Recreation default venue with its street address" do
      venue = scraper.default_venue

      expect(venue.name).to eq("Cedar Park Parks & Recreation")
      expect(venue.address).to eq("1435 Main Street")
      expect(venue.city).to eq("Cedar Park")
      expect(venue.state).to eq("TX")
      expect(venue.zip).to eq("78613")
    end
  end

  describe "#events from the recorded live feed" do
    let(:events) { replay_events }

    it "parses all 15 items into Events from the cedar_park source" do
      expect(events.length).to eq(15)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events.map(&:source).uniq).to eq(["cedar_park"])
      expect(events.map(&:url)).to all(
        start_with("https://www.cedarparktexas.gov/Calendar.aspx?EID=")
      )
    end

    it "gives every item a usable venue and an EID-based dedupe key" do
      expect(events).to all(satisfy { |event| event.venue.state == "TX" && event.venue.zip == "78613" })
      expect(events).to all(satisfy { |event| !event.venue.name.to_s.strip.empty? })
      expect(events).to all(satisfy { |event| !event.venue.address.to_s.strip.empty? })
      expect(events.any? { |event| event.venue.name == "Cedar Park Parks & Recreation" }).to be(true)
      expect(events.any? { |event| event.venue.address.include?("450 Cypress Creek Road") }).to be(true)
      expect(events.map { |event| scraper.dedupe_key(event) }.uniq.length).to eq(events.length)
      expect(events.map(&:tags).flatten).to all(match(/\A(?:eid:\d+|cancelled)\z/))
    end

    context "with EID=4323" do
      let(:event) { events.find { |candidate| candidate.url.include?("EID=4323") } }

      it "uses EventDates/EventTimes rather than pubDate" do
        expect(event.title).to eq("Courts and Track Closed for Resurfacing")
        expect(event.date).to eq(Date.new(2026, 11, 23))
        expect(event.date).not_to eq(Date.new(2026, 11, 2)) # pubDate is 2026-11-02
        expect(event.time).to eq("00:00")
        expect(event.begin_time).to eq("00:00")
        expect(event.end_time).to eq("23:59")
      end

      it "carries the default venue address, EID tag and no price" do
        expect(event.venue.name).to eq("Cedar Park Parks & Recreation")
        expect(event.venue.address).to eq("1435 Main Street")
        expect(event.venue.city).to eq("Cedar Park")
        expect(event.venue.state).to eq("TX")
        expect(event.venue.zip).to eq("78613")
        expect(event.tags).to include("eid:4323")
        expect(scraper.dedupe_key(event)).to eq("cedar_park:4323")
        expect(event.price.to_s.strip).to be_empty
        expect(event.price_cents).to be_nil
      end

      it "resolves the wall-clock start in America/Chicago" do
        expect(scraper.starts_at(event)).to eq(Time.new(2026, 11, 23, 0, 0, 0, "-06:00"))
      end
    end
  end

  describe "#parse_response" do
    let(:feed) do
      feed_xml(
        [
          item_xml(
            title: "Date and time range",
            eid: "1001",
            dates: "November 23, 2026",
            times: "06:00 PM - 09:00 PM",
            location: "450 Cypress Creek Road, Cedar Park, TX 78613",
            category: "Meetings",
            description: "&lt;p&gt;A real event with prose.&lt;/p&gt;",
            price: "$12.00"
          ),
          item_xml(
            title: "Date only",
            eid: "1002",
            link: "/Calendar.aspx?EID=1002",
            dates: "12/01/2026"
          ),
          item_xml(title: "No date", eid: "1003"),
          item_xml(title: "No url", eid: "1004", link: "", dates: "November 24, 2026"),
          item_xml(
            title: "CANCELLED: Flashback Friday",
            eid: "1005",
            dates: "November 25, 2026",
            times: "06:00 PM - 09:00 PM"
          ),
        ]
      )
    end

    let(:parsed) { scraper.parse_response(feed) }

    it "parses date+time and date-only items, skipping items missing a date or url" do
      expect(parsed.map(&:title)).to eq(
        ["Date and time range", "Date only", "CANCELLED: Flashback Friday"]
      )
    end

    it "normalizes time ranges and resolves relative links" do
      expect(parsed.first.begin_time).to eq("18:00")
      expect(parsed.first.end_time).to eq("21:00")
      expect(parsed.first.url).to eq("https://www.cedarparktexas.gov/Calendar.aspx?EID=1001")
      expect(parsed[1].url).to eq("https://www.cedarparktexas.gov/Calendar.aspx?EID=1002")
      expect(parsed[1].date).to eq(Date.new(2026, 12, 1))
    end

    it "keeps a specific venue when the feed carries a street address" do
      venue = parsed.first.venue

      expect(venue.name).to eq("450 Cypress Creek Road, Cedar Park, TX 78613")
      expect(venue.address).to eq("450 Cypress Creek Road")
      expect(venue.city).to eq("Cedar Park")
      expect(venue.state).to eq("TX")
      expect(venue.zip).to eq("78613")
    end

    it "falls back to the default venue when the location is generic" do
      expect(parsed.last.venue.name).to eq("Cedar Park Parks & Recreation")
    end

    it "carries category, description and price when available" do
      first = parsed.first

      expect(first.category).to eq("Meetings")
      expect(first.description).to eq("A real event with prose.")
      expect(first.price_cents).to eq(1200)
      expect(parsed[1].price_cents).to be_nil
    end

    it "flags CANCELLED titles while keeping the original title" do
      expect(parsed.last.title).to eq("CANCELLED: Flashback Friday")
      expect(parsed.last.tags).to include("cancelled")
    end

    it "returns no events for nil, empty or non-feed bodies" do
      expect(scraper.parse_response(nil)).to eq([])
      expect(scraper.parse_response("")).to eq([])
      expect(scraper.parse_response("<html><body>no items</body></html>")).to eq([])
    end

    it "accepts an already-parsed XML document" do
      doc = Nokogiri::XML(feed)

      expect(scraper.parse_response(doc).map(&:title)).to eq(parsed.map(&:title))
    end
  end

  describe "pagination" do
    let(:first_url) { described_class::FEED_URL }
    let(:second_url) { "#{first_url}&page=2" }

    it "follows an advertised next page and deduplicates repeated EIDs" do
      first_page = feed_xml(
        [item_xml(title: "First", eid: "2001", dates: "December 1, 2026")],
        channel_extras: %(<atom:link rel="next" href="#{second_url.gsub("&", "&amp;")}" />)
      )
      second_page = feed_xml(
        [
          item_xml(title: "First (duplicate)", eid: "2001", dates: "December 1, 2026"),
          item_xml(title: "Second", eid: "2002", dates: "December 2, 2026"),
        ]
      )
      stub_request(:get, first_url)
        .to_return(status: 200, body: first_page, headers: { "Content-Type" => "text/xml" })
      stub_request(:get, second_url)
        .to_return(status: 200, body: second_page, headers: { "Content-Type" => "text/xml" })

      expect(scraper.events.map(&:title)).to eq(["First", "Second"])
    end
  end

  describe "recorded cassette provenance" do
    it "replays a credential-free 200 XML response" do
      interaction = YAML.load_file(cassette_path).fetch("http_interactions").fetch(0)
      request = interaction.fetch("request")

      expect(interaction.dig("response", "status", "code")).to eq(200)
      expect(interaction.dig("response", "body", "string")).to include("EID=4323")
      expect(request.fetch("headers").keys.map(&:downcase)).not_to include(
        a_string_matching(/cookie|authorization|api[-_]?key/)
      )
    end
  end
end
