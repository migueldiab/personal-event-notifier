# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tempfile"
require "yaml"
require "weekly_local_events/application"

# End-to-end verification of the weekly digest with the real, registered
# `cedar_park` source enabled. No stand-in is used: the Application builds its
# ScraperRegistry from KNOWN_SCRAPERS, so `cedar_park` resolves to the live
# CedarParkScraper (public CivicEngage RSS feed). Both enabled sources are
# stubbed at the HTTP boundary: the Cedar Park feed with a deterministic
# fixture-shaped XML body (the same shape as the recorded
# cedar_park_calendar_rss cassette, with dates placed in the aggregation
# window) and Visit Cedar Park with its recorded JSON payload. The real
# cassette replay is covered by cedar_park_scraper_spec.rb and
# cedar_park_rss_scraper_spec.rb; this spec verifies the integrated pipeline.
RSpec.describe "Weekly digest end-to-end with Cedar Park" do
  let(:cli_path) { "/home/madrax/src/ai/WeeklyLocalEvents/bin/weekly_local_events" }
  let(:visit_fixture) do
    "/home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/visit_cedar_park_events.json"
  end
  let(:config_file) { Tempfile.new(["digest-config", ".yml"]) }
  let(:overlap_title) { "Kiddie Gym - Open Play" }
  let(:event_date) { Date.today + 1 }
  let(:null_logger) { Logger.new(File::NULL) }

  let(:config) do
    config_file.rewind
    config_file.truncate(0)
    config_file.write(
      YAML.dump(
        "notification_channel_id" => "-1004330304115",
        "telegram_bot_token" => "123456:ABC-DEF",
        "sites" => %w[cedar_park visit_cedar_park],
        "enabled_scrapers" => %w[cedar_park visit_cedar_park],
        "date_range_days" => 7,
        "log_level" => "FATAL"
      )
    )
    config_file.flush
    WeeklyLocalEvents::Config.new
  end

  let(:visit_class) { WeeklyLocalEvents::Scrapers::VisitCedarParkScraper }
  let(:cedar_class) { WeeklyLocalEvents::Scrapers::CedarParkScraper }
  let(:feed_url) { cedar_class::FEED_URL }
  let(:token_url) { "#{visit_class::BASE_URL}#{visit_class::TOKEN_PATH}" }
  let(:events_url_pattern) do
    /\A#{Regexp.escape(visit_class::BASE_URL)}#{Regexp.escape(visit_class::EVENTS_PATH)}/
  end
  let(:token_body) { "0123456789abcdef0123456789abcdef" }

  # Three distinct Cedar Park events. The first deliberately shares a title
  # with a Visit Cedar Park event but has a different venue and URL, so the
  # Aggregator's venue+date+title dedupe must NOT collapse them.
  let(:cedar_items) do
    [
      { eid: "9001", title: overlap_title, venue: "Cedar Park Recreation Center" },
      { eid: "9002", title: "City Council Meeting", venue: "Cedar Park City Hall" },
      { eid: "9003", title: "Basketball", venue: "Cedar Park Recreation Center" },
    ]
  end

  def feed_item(eid:, title:, venue:)
    <<~XML
      <item>
        <title>#{title}</title>
        <link>https://www.cedarparktexas.gov/Calendar.aspx?EID=#{eid}</link>
        <description>&lt;p&gt;Integration fixture event.&lt;/p&gt;</description>
        <calendarEvent:EventDates>#{event_date.strftime("%B %-d, %Y")}</calendarEvent:EventDates>
        <calendarEvent:EventTimes>06:00 PM - 08:00 PM</calendarEvent:EventTimes>
        <calendarEvent:Location>#{venue}, Cedar Park, TX 78613</calendarEvent:Location>
      </item>
    XML
  end

  let(:cedar_feed) do
    items = cedar_items.map { |item| feed_item(**item) }.join("\n")
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:calendarEvent="https://www.cedarparktexas.gov/Calendar.aspx">
        <channel>
          <title>Cedar Park, TX - Calendar</title>
          #{items}
        </channel>
      </rss>
    XML
  end

  # Use the real recorded fixture but move its dates into the aggregation
  # window so the spec stays green on any run date. The URLs and venues stay
  # exactly as captured.
  let(:visit_payload) do
    payload = JSON.parse(File.read(visit_fixture))
    iso_date = event_date.iso8601
    docs = payload.fetch("docs").fetch("docs").first(4).map do |doc|
      doc.merge(
        "date" => iso_date,
        "dates" => { "eventDate" => iso_date },
        "nextDate" => nil
      )
    end
    payload["docs"] = { "count" => docs.size, "docs" => docs }
    payload
  end

  let(:app) { WeeklyLocalEvents::Application.new(config) }

  before do
    # Let other File.expand_path calls (notably the CLI's own) work normally.
    allow(File).to receive(:expand_path).and_call_original
    allow(File).to receive(:expand_path)
      .with("~/.hermes/weekly_local_events/config.yml")
      .and_return(config_file.path)
    allow(config).to receive(:logger).and_return(null_logger)

    stub_request(:get, feed_url).to_return(
      status: 200,
      body: cedar_feed,
      headers: { "Content-Type" => "text/xml" }
    )
    stub_request(:get, token_url).to_return(status: 200, body: token_body)
    stub_request(:get, events_url_pattern).to_return(
      status: 200,
      body: JSON.generate(visit_payload),
      headers: { "Content-Type" => "application/json" }
    )
  end

  after do
    config_file.close!
  end

  describe "Application#run(dry_run: true)" do
    let(:summary) { app.run(dry_run: true) }
    let(:cedar_events) { summary.events.select { |event| event.source == "cedar_park" } }

    it "runs the real cedar_park source and returns absolute URLs for its events" do
      expect(summary.sources).to include("cedar_park" => cedar_items.size)
      expect(cedar_events.size).to eq(cedar_items.size)
      expect(cedar_events.map(&:url)).to all(a_string_starting_with("https://www.cedarparktexas.gov/Calendar.aspx?EID="))
      expect(summary.total).to eq(summary.sources.values.sum)
    end

    it "uses the registry's CedarParkScraper, not a stand-in" do
      registry = app.scraper_registry

      expect(registry.get("cedar_park")).to be_a(cedar_class)
      expect(WeeklyLocalEvents::ScraperRegistry::KNOWN_SCRAPERS).to include(
        "cedar_park" => "WeeklyLocalEvents::Scrapers::CedarParkScraper"
      )
    end

    it "keeps distinct Cedar Park events when a title overlaps Visit Cedar Park" do
      matches = summary.events.select { |event| event.title == overlap_title }

      expect(matches.size).to eq(2)
      expect(matches.map(&:source)).to contain_exactly("cedar_park", "visit_cedar_park")
      expect(matches.map(&:url).uniq.size).to eq(2)
    end

    it "does not drop valid Cedar Park events during deduplication" do
      expect(cedar_events.map(&:title)).to contain_exactly(
        "Kiddie Gym - Open Play", "City Council Meeting", "Basketball"
      )
      expect(cedar_events.map(&:url).uniq.size).to eq(cedar_items.size)
    end
  end

  describe "JSON CLI output" do
    it "emits the full events array with links for Cedar Park" do
      prepared_app = app
      allow(WeeklyLocalEvents::Config).to receive(:new).and_return(config)
      allow(WeeklyLocalEvents::Application).to receive(:new).and_return(prepared_app)

      # The CLI calls exit, so SystemExit must be caught while stdout is
      # captured; RSpec's output matcher cannot expose the full JSON buffer.
      original_argv = ARGV.dup
      original_stdout = $stdout
      captured = StringIO.new
      exit_status = nil
      begin
        ARGV.replace(%w[--dry-run --json])
        $stdout = captured # rubocop:disable RSpec/ExpectOutput
        begin
          load cli_path
        rescue SystemExit => e
          exit_status = e.status
        end
      ensure
        $stdout = original_stdout # rubocop:disable RSpec/ExpectOutput
        ARGV.replace(original_argv)
      end

      output = JSON.parse(captured.string)
      cedar = output.fetch("events").select { |event| event["source"] == "cedar_park" }

      expect(exit_status).to eq(0)
      expect(output["dry_run"]).to be(true)
      expect(output["sources"]).to include("cedar_park" => cedar_items.size)
      expect(output["events"].size).to eq(output["total"])
      expect(cedar.size).to eq(cedar_items.size)
      expect(cedar.map { |event| event["url"] }).to all(a_string_starting_with("https://"))
    end
  end
end
