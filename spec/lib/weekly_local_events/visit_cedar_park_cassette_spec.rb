# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "yaml"
require "weekly_local_events/scrapers/visit_cedar_park_scraper"

RSpec.describe "Visit Cedar Park recorded cassette" do
  let(:cassette_name) { "visit_cedar_park_events" }
  let(:cassette_path) do
    "/home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/vcr_cassettes/visit_cedar_park_events.yml"
  end
  let(:redacted_token) { "TOKEN_REDACTED" }
  let(:events_url) { "https://visitcedarparktexas.com/includes/rest_v2/plugins_events_events_by_date/find/" }
  let(:scraper) { WeeklyLocalEvents::Scrapers::VisitCedarParkScraper.new }

  # The cassette stores a single GET whose token is the redaction placeholder;
  # matching on method keeps the replay independent of query-parameter encoding.
  def replayed_body
    body = nil
    VCR.use_cassette(cassette_name, match_requests_on: %i[method]) do
      body = Net::HTTP.get(URI("#{events_url}?token=#{redacted_token}"))
    end
    body
  end

  it "parses real events from the recorded response with no network" do
    events = scraper.parse_response(replayed_body)

    expect(events).not_to be_empty
    expect(events.length).to be >= 3
    expect(events).to all(be_a(WeeklyLocalEvents::Event))
    expect(events.map(&:source).uniq).to eq(["visit_cedar_park"])
    expect(events.map(&:title)).to include("Kiddie Gym - Open Play")
    expect(events.first.url).to start_with("https://visitcedarparktexas.com/event/")
    expect(events.first.date).not_to be_nil
  end

  it "keeps credentials out of the cassette" do
    interaction = YAML.load_file(cassette_path).fetch("http_interactions").fetch(0)
    headers = interaction.fetch("request").fetch("headers")
                         .merge(interaction.fetch("response").fetch("headers"))

    expect(headers.keys.map(&:downcase)).not_to include(
      a_string_matching(/cookie|authorization|api[-_]?key|x-auth/)
    )
    expect(interaction.dig("request", "uri")).to include("token=#{redacted_token}")
    expect(interaction.dig("response", "status", "code")).to eq(200)

    body = interaction.dig("response", "body", "string")
    expect(body).not_to match(/[0-9a-f]{32}/), "response body contains a token-shaped value"
  end

  it "rejects an unrecorded request instead of reaching the network" do
    VCR.use_cassette("visit_cedar_park_events_unrecorded") do
      expect { Net::HTTP.get(URI("#{events_url}not_recorded/")) }
        .to raise_error(VCR::Errors::UnhandledHTTPRequestError)
    end
  end
end
