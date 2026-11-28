# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "yaml"
require "weekly_local_events/scrapers/cedar_park_calendar_scraper"

# Network-free replay of the real Wayback HTML snapshot. The live calendar page
# is Cloudflare-blocked, so the cassette captures the archived `id_` snapshot
# (20260207030455). CedarParkCalendarScraper is the parser for this HTML; the
# live RSS CedarParkScraper has its own cassette (cedar_park_calendar_rss).
RSpec.describe "Cedar Park recorded cassette" do
  let(:cassette_name) { "cedar_park_events" }
  let(:cassette_path) { File.join(VCR_CASSETTE_DIR, "#{cassette_name}.yml") }
  let(:snapshot_url) do
    "https://web.archive.org/web/20260207030455id_/https://www.cedarparktexas.gov/calendar.aspx"
  end
  let(:scraper) { WeeklyLocalEvents::Scrapers::CedarParkCalendarScraper.new }

  # VCR's default record mode in spec_helper is :none, so a request that is not
  # in the cassette raises instead of silently reaching the network.
  def replayed_body
    body = nil
    VCR.use_cassette(cassette_name, match_requests_on: %i[method uri]) do
      body = Net::HTTP.get(URI(snapshot_url))
    end
    body
  end

  it "parses real events from the recorded archived HTML with no network" do
    events = scraper.parse_response(replayed_body)

    expect(events).not_to be_empty
    expect(events.length).to be >= 3
    expect(events).to all(be_a(WeeklyLocalEvents::Event))
    expect(events.map(&:source).uniq).to eq(["cedar_park_calendar"])
    expect(events.map(&:title)).to include("BASKETBALL (1 COURT)")
    expect(events.first.url).to start_with("https://www.cedarparktexas.gov/Calendar.aspx?EID=")
    expect(events.first.date).not_to be_nil
  end

  it "keeps credentials and interstitial bodies out of the cassette" do
    interaction = YAML.load_file(cassette_path).fetch("http_interactions").fetch(0)
    headers = interaction.fetch("request").fetch("headers")
                         .merge(interaction.fetch("response").fetch("headers"))

    expect(headers.keys.map(&:downcase)).not_to include(
      a_string_matching(/cookie|authorization|api[-_]?key|x-auth/)
    )
    expect(interaction.dig("request", "uri")).to include("/20260207030455id_/")
    expect(interaction.dig("response", "status", "code")).to eq(200)

    body = interaction.dig("response", "body", "string").to_s
    expect(body.scan('itemtype="http://schema.org/Event"').length).to be >= 3
    expect(body).not_to match(/Attention Required|Just a moment|One more step|Access Denied/i)
  end

  it "documents the snapshot timestamp in the cassette context" do
    header = File.read(cassette_path).lines.take_while { |line| line.start_with?("#") }.join
    expect(header).to include("20260207030455")
    expect(header).to include("as archived 2026-02-07")
    expect(header).to include("NOT the live page")
  end

  it "rejects an unrecorded request instead of reaching the network" do
    VCR.use_cassette("cedar_park_events_unrecorded") do
      expect do
        Net::HTTP.get(URI("https://web.archive.org/web/19990101000000id_/https://www.cedarparktexas.gov/calendar.aspx"))
      end.to raise_error(VCR::Errors::UnhandledHTTPRequestError)
    end
  end
end
