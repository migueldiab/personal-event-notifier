# frozen_string_literal: true

require "spec_helper"
require "vcr"

RSpec.describe "VCR configuration" do
  it "replays recordings during normal test runs instead of hitting real sites" do
    expect(VCR.configuration.default_cassette_options[:record]).to eq(:none)
  end

  it "stores cassettes under the project fixture directory" do
    expect(VCR.configuration.cassette_library_dir).to eq(
      "/home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/vcr_cassettes"
    )
  end

  it "matches recorded requests by method and URI" do
    expect(VCR.configuration.default_cassette_options[:match_requests_on]).to include(:method, :uri)
  end

  it "blocks real HTTP when no cassette is in use" do
    expect(VCR.configuration.allow_http_connections_when_no_cassette?).to be false
  end
end
