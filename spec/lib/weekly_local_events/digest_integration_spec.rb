# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tempfile"
require "yaml"
require "weekly_local_events/application"
require "weekly_local_events/scrapers/visit_cedar_park_scraper"

# End-to-end verification of the weekly digest with both Cedar Park sources in
# the enabled set. Production intentionally registers only `visit_cedar_park`:
# the city calendar (`cedar_park`) is behind Cloudflare and the only captured
# copy is a stale Wayback snapshot (docs/cedar_park_recon.md). To prove the
# pipeline carries two Cedar Park sources, this spec registers a fixture-backed
# stand-in under that name on the Application's own registry; the real
# VisitCedarParkScraper is exercised through its HTTP fetch pipeline.
RSpec.describe "Weekly digest end-to-end with both Cedar Park sources" do
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

  # Anonymous stand-in for the archived Cedar Park city calendar. Its event
  # shares a title with a Visit Cedar Park event but has a different venue and
  # absolute URL, so it exercises the "title overlap must not collapse" rule.
  let(:cedar_park_scraper_class) do
    title = overlap_title
    date = event_date
    Class.new(WeeklyLocalEvents::BaseScraper) do
      define_method(:name) { "cedar_park" }

      define_method(:events) do
        [
          WeeklyLocalEvents::Event.new(
            title: title,
            date: date,
            venue: WeeklyLocalEvents::Venue.new(
              name: "Cedar Park Recreation Center",
              city: "Cedar Park",
              state: "TX",
              lat: 30.5052,
              lng: -97.8203
            ),
            url: "https://www.cedarparktexas.gov/Calendar.aspx?EID=3428&month=2&year=2026&day=1",
            source: "cedar_park"
          )
        ]
      end
    end
  end

  let(:visit_class) { WeeklyLocalEvents::Scrapers::VisitCedarParkScraper }
  let(:token_url) { "#{visit_class::BASE_URL}#{visit_class::TOKEN_PATH}" }
  let(:events_url_pattern) do
    /\A#{Regexp.escape(visit_class::BASE_URL)}#{Regexp.escape(visit_class::EVENTS_PATH)}/
  end
  let(:token_body) { "0123456789abcdef0123456789abcdef" }

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

  let(:app) do
    application = WeeklyLocalEvents::Application.new(config)
    application.scraper_registry.register("cedar_park", cedar_park_scraper_class)
    application
  end

  before do
    # Let other File.expand_path calls (notably the CLI's own) work normally.
    allow(File).to receive(:expand_path).and_call_original
    allow(File).to receive(:expand_path)
      .with("~/.hermes/weekly_local_events/config.yml")
      .and_return(config_file.path)
    allow(config).to receive(:logger).and_return(null_logger)

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
    it "runs both Cedar Park sources and returns absolute URLs for every event" do
      summary = app.run(dry_run: true)

      expect(summary.sources).to include("cedar_park" => 1, "visit_cedar_park" => 4)
      expect(summary.total).to eq(summary.sources.values.sum)
      expect(summary.events.map(&:url)).to all(a_string_starting_with("https://"))
      expect(summary.events.map(&:source).uniq).to contain_exactly("cedar_park", "visit_cedar_park")
    end

    it "keeps distinct events when the two Cedar Park sites share a title" do
      summary = app.run(dry_run: true)
      matches = summary.events.select { |event| event.title == overlap_title }

      expect(matches.size).to eq(2)
      expect(matches.map(&:source)).to contain_exactly("cedar_park", "visit_cedar_park")
      expect(matches.map(&:url).uniq.size).to eq(2)
    end
  end

  describe "JSON CLI output" do
    it "emits the full events array with links for both Cedar Park sources" do
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
      expect(exit_status).to eq(0)
      expect(output["dry_run"]).to be(true)
      expect(output["sources"]).to include("cedar_park" => 1, "visit_cedar_park" => 4)
      expect(output["events"].size).to eq(output["total"])
      expect(output["events"].map { |event| event["url"] }).to all(a_string_starting_with("https://"))
      expect(output["events"].map { |event| event["source"] }).to include("cedar_park", "visit_cedar_park")
    end
  end
end
