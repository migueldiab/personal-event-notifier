# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "weekly_local_events/scrapers/community_impact_scraper"
require "weekly_local_events/scrapers/acl_live_scraper"

RSpec.describe "recorded HTML cassettes" do
  let(:config) { WeeklyLocalEvents::Config.new }

  it "parses community impact events from recorded HTML with no live request" do
    html = nil
    VCR.use_cassette("community_impact_calendar") do
      uri = URI("https://communityimpact.com/austin/calendar/?from=2026-11-27&to=2026-11-27")
      html = Net::HTTP.get(uri)
    end

    events = WeeklyLocalEvents::Scrapers::CommunityImpactScraper.new(config).parse_response(html)

    expect(events).not_to be_empty
    expect(events.first.url).to start_with("https://communityimpact.com/")
  end

  it "parses ACL Live events from recorded HTML with no live request" do
    html = nil
    VCR.use_cassette("acl_live_events") do
      html = Net::HTTP.get(URI("https://www.acllive.com/events"))
    end

    events = WeeklyLocalEvents::Scrapers::ACLLiveScraper.new(config).parse_response(html)

    expect(events).not_to be_empty
  end

  it "rejects a request that has no cassette instead of reaching the network" do
    VCR.use_cassette("no_such_cassette") do
      expect { Net::HTTP.get(URI("https://example.invalid/events")) }
        .to raise_error(VCR::Errors::UnhandledHTTPRequestError)
    end
  end
end
