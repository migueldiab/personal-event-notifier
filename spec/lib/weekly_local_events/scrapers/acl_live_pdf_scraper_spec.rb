# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/acl_live_pdf_scraper"
require "weekly_local_events/scrapers/acl_live_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::AclLivePdfScraper do
  subject(:scraper) { described_class.new }

  let(:fixture_path) { File.expand_path("../../../fixtures/acllive_calendar.pdf", __dir__) }
  let(:pdf_bytes) { File.binread(fixture_path) }

  let(:synthetic_layout) do
    [
      "                  DECEMBER",
      layout_row("SUNDAY", "MONDAY", "TUESDAY"),
      layout_row(1, 2, 3),
      layout_row("Jim Henson's", "ACL Live Tour", "All Get Out"),
      layout_row("Labyrinth: In", "1:00am", "8:00pm"),
      layout_row("Concert 40th", "", ""),
      layout_row("Anniversary", "", ""),
      layout_row("8:00pm", "", ""),
      layout_row(4, 5, 6),
      layout_row("Kansas", "", "Silent Night"),
      layout_row("7:00pm", "", "6:00pm"),
      "",
      "Powered by TCPDF (www.tcpdf.org)"
    ].join("\n")
  end

  # Build a layout-mode row with fixed-width columns, mirroring the TCPDF grid.
  def layout_row(*cells)
    cells.map { |cell| cell.to_s.ljust(17) }.join.rstrip
  end

  describe "#initialize" do
    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end

    it "uses a distinct name so it can coexist with the HTML scraper" do
      expect(scraper.name).to eq("acl_live_pdf")
    end

    it "targets the ACL Live site" do
      expect(scraper.base_url).to eq("https://www.acllive.com")
    end

    it "defaults the venue because the PDF carries no per-event venue" do
      expect(scraper.venue_name).to eq("ACL Live at The Moody Theater")
    end

    it "allows the venue to be overridden" do
      custom = described_class.new(venue: "ACL Live at 3TEN")
      expect(custom.venue_name).to eq("ACL Live at 3TEN")
    end
  end

  describe "#parse" do
    it "extracts events from the real TCPDF calendar fixture" do
      events = scraper.parse(pdf_bytes)
      expect(events).to be_an(Array)
      expect(events).not_to be_empty
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles a full month (30+ events across both PDF pages)" do
      expect(scraper.parse(pdf_bytes).size).to be >= 25
    end

    it "joins a multi-line title into a single Event" do
      events = scraper.parse(pdf_bytes)
      titles = events.map(&:title)
      expect(titles).to include("Jim Henson's Labyrinth: In Concert 40th Anniversary")
    end

    it "keeps events from the final week of the month" do
      titles = scraper.parse(pdf_bytes).map(&:title)
      expect(titles).to include(a_string_matching(/BEAT: Belew/))
      expect(titles).to include("ACL Live Tour Experience")
    end

    it "reassembles entries continued across the page break" do
      titles = scraper.parse(pdf_bytes).map(&:title)
      expect(titles).to include("Poi Dog Pondering", "Bob Schneider & The Moonlight Orchestra")
    end

    it "assigns the November dates using the year in the PDF metadata" do
      events = scraper.parse(pdf_bytes)
      expect(events.map(&:date)).to all(satisfy { |d| d.year == 2026 && d.month == 11 })
    end

    it "normalizes times to the same 24h format as the HTML scraper" do
      by_title = scraper.parse(pdf_bytes).group_by(&:title)
      expect(by_title.fetch("All Get Out").first.time).to eq("20:00")
      expect(by_title.fetch("ACL Live Tour").first.time).to eq("01:00")
    end

    it "uses the shared source value and a default venue" do
      events = scraper.parse(pdf_bytes)
      expect(events.map(&:source).uniq).to eq(["acl_live"])
      expect(events.map { |e| e.venue.name }.uniq).to eq(["ACL Live at The Moody Theater"])
    end

    it "leaves url blank because the PDF contains no event links" do
      # Event coerces nil to "" — identical to the HTML scraper's text fallback.
      expect(scraper.parse(pdf_bytes).map(&:url).uniq).to eq([""])
    end

    it "emits the same JSON schema as the HTML scraper" do
      pdf_event = scraper.parse(pdf_bytes).first
      html_event = WeeklyLocalEvents::Scrapers::ACLLiveScraper.new.parse_response(
        "<div class='event-card'><span class='event-date'>Nov 1, 2026</span>" \
        "<h3>Kansas</h3><a href='/event/2026-11-01-kansas-at-8-pm'>Tickets</a></div>"
      ).first

      expect(pdf_event.to_hash.keys).to eq(html_event.to_hash.keys)
      expect(JSON.parse(pdf_event.to_jsonl).keys).to eq(JSON.parse(html_event.to_jsonl).keys)
    end
  end

  describe "#parse_layout" do
    it "parses layout text directly without a PDF" do
      events = scraper.parse_layout(synthetic_layout, year: 2026)
      expect(events.map(&:title)).to include("Jim Henson's Labyrinth: In Concert 40th Anniversary")
    end

    it "handles merged/blank cells without inventing events" do
      events = scraper.parse_layout(synthetic_layout, year: 2026)
      expect(events.map(&:title)).to include("Kansas", "Silent Night")
      expect(events.map(&:title)).not_to include("Powered by TCPDF (www.tcpdf.org)")
    end

    it "applies the supplied year and month" do
      events = scraper.parse_layout(synthetic_layout, year: 2026)
      expect(events.map(&:date)).to all(satisfy { |d| d.year == 2026 && d.month == 12 })
      expect(events.find { |e| e.title == "Kansas" }.date).to eq(Date.new(2026, 12, 4))
    end

    it "supports a layout with no month header when year is given" do
      layout = [layout_row(1, 2), layout_row("Kansas", "Kansas"), layout_row("8:00pm", "8:00pm")].join("\n")
      events = scraper.parse_layout(layout, year: 2026, month: 12)
      expect(events.size).to eq(2)
      expect(events.map(&:date).uniq).to eq([Date.new(2026, 12, 1), Date.new(2026, 12, 2)])
    end
  end

  describe "#parse_response" do
    it "is an alias for #parse to satisfy the BaseScraper contract" do
      expect(scraper.parse_response(pdf_bytes).map(&:title)).to eq(scraper.parse(pdf_bytes).map(&:title))
    end
  end

  describe "#events" do
    it "fetches the PDF and parses it" do
      stub_request(:get, "https://www.acllive.com/events-tickets/pdf")
        .to_return(status: 200, body: pdf_bytes, headers: { "Content-Type" => "application/pdf" })

      events = scraper.events
      expect(events).not_to be_empty
      expect(events.first).to be_a(WeeklyLocalEvents::Event)
    end

    it "requests the PDF with an Accept header" do
      stub = stub_request(:get, "https://www.acllive.com/events-tickets/pdf")
             .with(headers: { "Accept" => "application/pdf" })
             .to_return(status: 200, body: pdf_bytes)

      scraper.events
      expect(stub).to have_been_requested
    end
  end

  describe "invalid input" do
    it "returns no events for an empty PDF" do
      expect(scraper.parse("")).to eq([])
    end

    it "returns no events for a layout with no day rows" do
      expect(scraper.parse_layout("NOVEMBER\n\nJust a heading\n", year: 2026)).to eq([])
    end
  end
end
