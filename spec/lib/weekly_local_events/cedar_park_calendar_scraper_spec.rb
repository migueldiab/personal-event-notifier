# frozen_string_literal: true

require "spec_helper"
require "weekly_local_events/scrapers/cedar_park_calendar_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::CedarParkCalendarScraper do
  # Wayback raw snapshot of https://www.cedarparktexas.gov/calendar.aspx,
  # archived 2026-02-07. Historical fallback only — never presented as current.
  let(:fixture_path) { File.expand_path("../../fixtures/cedar_park_events.html", __dir__) }
  let(:fixture_html) { File.read(fixture_path, encoding: "UTF-8") }
  let(:scraper) { described_class.new }
  let(:events) { scraper.parse_response(fixture_html) }
  let(:first_event) { events.first }

  describe "#parse_response with the archived CivicEngage fixture" do
    it "parses more than three events from the snapshot" do
      expect(events.length).to be >= 3
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
      expect(events.map(&:source).uniq).to eq(["cedar_park_calendar"])
    end

    it "extracts the exact fields of the first event" do
      expect(first_event.title).to eq("BASKETBALL (1 COURT)")
      expect(first_event.date).to eq(Date.new(2026, 2, 1))
      expect(first_event.time).to eq("13:00")
      expect(first_event.begin_time).to eq("13:00")
      expect(first_event.end_time).to eq("18:00")
      expect(scraper.iso_start(first_event)).to eq("2026-02-01T13:00:00")
      expect(first_event.venue.name).to eq("Recreation Center")
      expect(first_event.category).to eq("Gym Court Schedule")
      expect(first_event.url).to eq(
        "https://www.cedarparktexas.gov/Calendar.aspx?EID=3428" \
        "&month=2&year=2026&day=1&calType=0"
      )
    end

    it "deduplicates multi-day entries by EID" do
      keys = events.map { |event| scraper.dedupe_key(event) }

      expect(events.length).to eq(84)
      expect(keys).to all(match(/\Acedar_park_calendar:\d+\z/))
      expect(keys.uniq.length).to eq(events.length)
      expect(keys.count("cedar_park_calendar:3444")).to eq(1)
      expect(first_event.tags).to include("eid:3428")
    end
  end

  describe "#starts_at" do
    it "interprets a naive winter start as America/Chicago (CST)" do
      expect(scraper.starts_at(first_event)).to eq(Time.new(2026, 2, 1, 13, 0, 0, "-06:00"))
    end

    it "interprets a naive summer start as America/Chicago (CDT)" do
      summer_event = WeeklyLocalEvents::Event.from_hash(
        title: "Summer Court",
        date: Date.new(2026, 7, 15),
        time: "18:30",
        begin_time: "18:30",
        venue: WeeklyLocalEvents::Venue.new(name: "Recreation Center"),
        url: "https://www.cedarparktexas.gov/Calendar.aspx?EID=9000",
        source: "cedar_park_calendar"
      )

      expect(scraper.starts_at(summer_event)).to eq(Time.new(2026, 7, 15, 18, 30, 0, "-05:00"))
    end
  end

  describe "#events from an archived snapshot" do
    let(:snapshot) do
      WeeklyLocalEvents::ArchivedSnapshotFetcher::Snapshot.new(
        body: fixture_html,
        source_url: described_class::CALENDAR_URL,
        snapshot_url: "https://web.archive.org/web/20260207030455id_/#{described_class::CALENDAR_URL}",
        snapshot_timestamp: "20260207030455",
        route: :wayback,
        kind: :snapshot
      )
    end

    it "parses the snapshot body returned by the injected fetcher" do
      fetcher = instance_double(WeeklyLocalEvents::ArchivedSnapshotFetcher, fetch: snapshot)
      expect(fetcher).to receive(:fetch).with(described_class::CALENDAR_URL)

      expect(described_class.new(fetcher: fetcher).events.length).to eq(84)
    end

    it "returns no events when no snapshot can be validated" do
      fetcher = instance_double(WeeklyLocalEvents::ArchivedSnapshotFetcher, fetch: nil)

      expect(described_class.new(fetcher: fetcher).events).to eq([])
    end
  end

  describe "archived snapshot field coverage" do
    it "captures the venue address from the location microdata" do
      venue = first_event.venue

      expect(venue.name).to eq("Recreation Center")
      expect(venue.address).to eq("1435 Main Street")
      expect(venue.city).to eq("Cedar Park")
      expect(venue.state).to eq("TX")
      expect(venue.zip).to eq("78613")
    end

    it "leaves description empty and price unknown in this snapshot" do
      expect(first_event.description).to eq("")
      expect(first_event.price_cents).to be_nil
      expect(first_event.price.to_s.strip).to eq("")
      expect(first_event.category).to eq("Gym Court Schedule")
    end

    it "normalizes a human time range on an evening event" do
      evening = events.find { |event| event.title.start_with?("CANCELLED:") }

      expect(evening.begin_time).to eq("18:00")
      expect(evening.end_time).to eq("21:00")
    end
  end

  describe "cancellation handling" do
    it "flags CANCELLED-prefixed events without dropping them" do
      cancelled = events.select { |event| event.title.start_with?("CANCELLED:") }

      expect(cancelled.length).to eq(1)
      expect(cancelled.first.tags).to include("cancelled")
      expect(events.length).to eq(84)
    end
  end

  describe "#calendar_page_url" do
    it "constructs the crawlable month-grid URL for an adjacent month" do
      expect(scraper.calendar_page_url(1, 2026)).to eq(
        "https://www.cedarparktexas.gov/calendar.aspx?month=1&year=2026"
      )
    end
  end

  describe "fake-200 body rejection" do
    def expect_rejected(body)
      expect(WeeklyLocalEvents::ArchivedSnapshotFetcher.valid_body?(body)).to be(false)
      expect(scraper.parse_response(body)).to eq([])
    end

    it "parses zero events from a Cloudflare interstitial" do
      body = <<~HTML
        <html><head><title>Just a moment...</title></head>
        <body><h1>Attention Required!</h1><p>Checking your browser before access.</p></body></html>
      HTML

      expect_rejected(body)
    end

    it "parses zero events from a rate-limit page" do
      body = <<~HTML
        <html><head><title>Error 429</title></head>
        <body><p>Too Many Requests. Please try again later.</p></body></html>
      HTML

      expect_rejected(body)
    end

    it "parses zero events from a redirect stub" do
      body = <<~HTML
        <html><head><meta http-equiv="refresh"
        content="0; url=https://www.cedarparktexas.gov/calendar.aspx"></head>
        <body>Redirecting...</body></html>
      HTML

      expect_rejected(body)
    end
  end
end
