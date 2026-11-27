# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/paramount_austin_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::ParamountAustinScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "paramount_austin", base_url: "https://tickets.austintheatre.org",
      date_range: date_range, user_agent: "TestBot/1.0" }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <ul class="list-unstyled" aria-labelledby="tn-event-listing-view-results-heading">
        <li data-tn-prod-season-no="14376" class="tn-prod-list-item">
          <h4 id="tn-prod-list-item-heading-14376" class="tn-prod-list-item__property tn-prod-list-item__property--heading">
            <a href="https://tickets.austintheatre.org/14376">BLACK FRIDAY TEXAS SHOWDOWN</a>
          </h4>
          <h5 class="sr-only">Items</h5>
          <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list" aria-labelledby="tn-prod-list-item-heading-14376">
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14377" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14376/14377" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Friday, November 27, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">6:30PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Black Friday Texas Showdown</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
          </ul>
          <div class="tn-prod-list-item__property tn-prod-list-item__property--img-container">
            <a href="https://tickets.austintheatre.org/14376">
              <img alt="" src="https://paramount-theatre.s3.us-east-2.amazonaws.com/wp-content/uploads/Lonestar-600x400-2.jpg">
            </a>
          </div>
        </li>
        <li data-tn-prod-season-no="14096" class="tn-prod-list-item">
          <h4 id="tn-prod-list-item-heading-14096" class="tn-prod-list-item__property tn-prod-list-item__property--heading">
            <a href="https://tickets.austintheatre.org/14096">NACHO REDONDO</a>
          </h4>
          <h5 class="sr-only">Items</h5>
          <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list" aria-labelledby="tn-prod-list-item-heading-14096">
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14097" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14096/14097" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Sunday, November 29, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">6:00PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Nacho Redondo</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
          </ul>
          <div class="tn-prod-list-item__property tn-prod-list-item__property--img-container">
            <a href="https://tickets.austintheatre.org/14096">
              <img alt="Nacho Redondo" src="https://paramount-theatre.s3.us-east-2.amazonaws.com/wp-content/uploads/Nacho-Redondo-600x400.jpg">
            </a>
          </div>
        </li>
        <li data-tn-prod-season-no="14200" class="tn-prod-list-item">
          <h4 id="tn-prod-list-item-heading-14200" class="tn-prod-list-item__property tn-prod-list-item__property--heading">
            <a href="https://tickets.austintheatre.org/14200">ELF PUB RUN</a>
          </h4>
          <h5 class="sr-only">Items</h5>
          <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list" aria-labelledby="tn-prod-list-item-heading-14200">
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14201" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14200/14201" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Tuesday, December 1, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">8:00PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Elf Pub Run</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
          </ul>
        </li>
      </ul>
    HTML
  end

  let(:sample_html_with_multiple_performances) do
    <<~HTML
      <ul class="list-unstyled" aria-labelledby="tn-event-listing-view-results-heading">
        <li data-tn-prod-season-no="14300" class="tn-prod-list-item">
          <h4 id="tn-prod-list-item-heading-14300" class="tn-prod-list-item__property tn-prod-list-item__property--heading">
            <a href="https://tickets.austintheatre.org/14300">DAVIDE DE PIERRO</a>
          </h4>
          <h5 class="sr-only">Items</h5>
          <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list" aria-labelledby="tn-prod-list-item-heading-14300">
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14301" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14300/14301" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Thursday, December 3, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">8:00PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Davide de Pierro</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14302" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14300/14302" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Friday, December 4, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">8:00PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Davide de Pierro</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
          </ul>
        </li>
      </ul>
    HTML
  end

  let(:sample_html_no_image) do
    <<~HTML
      <ul class="list-unstyled" aria-labelledby="tn-event-listing-view-results-heading">
        <li data-tn-prod-season-no="14400" class="tn-prod-list-item">
          <h4 id="tn-prod-list-item-heading-14400" class="tn-prod-list-item__property tn-prod-list-item__property--heading">
            <a href="https://tickets.austintheatre.org/14400">MIDNIGHT SHOW</a>
          </h4>
          <h5 class="sr-only">Items</h5>
          <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list" aria-labelledby="tn-prod-list-item-heading-14400">
            <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14401" data-tn-product-type-id="20">
              <a href="https://tickets.austintheatre.org/14400/14401" class="tn-prod-list-item__perf-anchor">
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                  <span class="tn-prod-list-item__perf-date">Wednesday, December 9, 2026</span>
                  <span class="sr-only">,&nbsp;</span>
                  <span class="tn-prod-list-item__perf-time">11:30PM</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                  <span class="tn-performance-title">Midnight Show</span>
                  <span class="sr-only">,&nbsp;</span>
                </span>
                <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                  <span class="tn-prod-list-item__perf-action">Purchase</span>
                </span>
                <span class="glyphicon glyphicon-chevron-right btn btn-primary" aria-hidden="true"></span>
              </a>
            </li>
          </ul>
        </li>
      </ul>
    HTML
  end

  describe "#initialize" do
    it "sets the name to paramount_austin" do
      expect(scraper.name).to eq("paramount_austin")
    end

    it "sets the base_url to the ticketing site" do
      expect(scraper.base_url).to eq("https://tickets.austintheatre.org")
    end

    it "sets a proper user agent" do
      expect(scraper.user_agent).to include("WeeklyLocalEvents")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end
  end

  describe "#parse_response" do
    it "parses event listings from HTML" do
      events = scraper.parse_response(sample_html)
      expect(events).to be_an(Array)
      expect(events.size).to eq(3)
    end

    it "extracts title from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].title).to eq("Black Friday Texas Showdown")
      expect(events[1].title).to eq("Nacho Redondo")
      expect(events[2].title).to eq("Elf Pub Run")
    end

    it "extracts date from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].date).to eq(Date.new(2026, 11, 27))
      expect(events[1].date).to eq(Date.new(2026, 11, 29))
      expect(events[2].date).to eq(Date.new(2026, 12, 1))
    end

    it "extracts time from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].time).to eq("18:30")
      expect(events[1].time).to eq("18:00")
      expect(events[2].time).to eq("20:00")
    end

    it "extracts venue from event listings" do
      events = scraper.parse_response(sample_html)
      expect(events[0].venue.name).to eq("Paramount Theatre (Austin, TX)")
    end

    it "extracts URL from event listings (ticket URL format)" do
      events = scraper.parse_response(sample_html)
      expect(events[0].url).to eq("https://tickets.austintheatre.org/14376/14377")
      expect(events[1].url).to eq("https://tickets.austintheatre.org/14096/14097")
      expect(events[2].url).to eq("https://tickets.austintheatre.org/14200/14201")
    end

    it "sets source to paramount_austin" do
      events = scraper.parse_response(sample_html)
      expect(events[0].source).to eq("paramount_austin")
    end

    it "handles multiple performances for the same event" do
      events = scraper.parse_response(sample_html_with_multiple_performances)
      expect(events.size).to eq(2)
      expect(events[0].date).to eq(Date.new(2026, 12, 3))
      expect(events[1].date).to eq(Date.new(2026, 12, 4))
      expect(events[0].url).to eq("https://tickets.austintheatre.org/14300/14301")
      expect(events[1].url).to eq("https://tickets.austintheatre.org/14300/14302")
    end

    it "handles events without images" do
      events = scraper.parse_response(sample_html_no_image)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Midnight Show")
      expect(events[0].date).to eq(Date.new(2026, 12, 9))
    end

    it "handles missing time gracefully" do
      html_no_time = <<~HTML
        <ul class="list-unstyled">
          <li class="tn-prod-list-item">
            <h4 class="tn-prod-list-item__property tn-prod-list-item__property--heading">
              <a href="https://tickets.austintheatre.org/99999">No Time Event</a>
            </h4>
            <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list">
              <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="99999">
                <a href="https://tickets.austintheatre.org/99999/99999" class="tn-prod-list-item__perf-anchor">
                  <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--datetime">
                    <span class="tn-prod-list-item__perf-date">Friday, December 25, 2026</span>
                  </span>
                  <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--title">
                    <span class="tn-performance-title">No Time Event</span>
                  </span>
                  <span class="tn-prod-list-item__perf-property tn-prod-list-item__perf-property--action">
                    <span class="tn-prod-list-item__perf-action">Purchase</span>
                  </span>
                </a>
              </li>
            </ul>
          </li>
        </ul>
      HTML
      events = scraper.parse_response(html_no_time)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Time Event")
      expect(events[0].date).to eq(Date.new(2026, 12, 25))
      expect(events[0].time).to eq("")
    end

    it "returns empty array for empty HTML" do
      events = scraper.parse_response("<html><body></body></html>")
      expect(events).to be_empty
    end

    it "returns empty array for nil input" do
      events = scraper.parse_response(nil)
      expect(events).to be_empty
    end

    it "skips events without a title" do
      html_no_title = <<~HTML
        <ul class="list-unstyled">
          <li class="tn-prod-list-item">
            <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list">
              <li class="tn-prod-list-item__perf-list-item">
                <a href="https://tickets.austintheatre.org/88888/88888" class="tn-prod-list-item__perf-anchor">
                  <span class="tn-prod-list-item__perf-date">Dec 25, 2026</span>
                </a>
              </li>
            </ul>
          </li>
        </ul>
      HTML
      events = scraper.parse_response(html_no_title)
      expect(events).to be_empty
    end
  end

  describe "#events" do
    it "returns an array of Event objects" do
      stub_request(:get, "https://tickets.austintheatre.org/events")
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, "https://tickets.austintheatre.org/events")
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, "https://tickets.austintheatre.org/events")
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, "https://tickets.austintheatre.org/events")
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 500 gracefully" do
      stub_request(:get, "https://tickets.austintheatre.org/events")
        .to_return(status: 500)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end
  end

  describe "#extract_product_id" do
    it "extracts product ID from full ticket URL" do
      href = "https://tickets.austintheatre.org/14376/14377"
      expect(scraper.send(:extract_product_id, href)).to eq("14376")
    end

    it "extracts product ID from event URL" do
      href = "https://tickets.austintheatre.org/14096"
      expect(scraper.send(:extract_product_id, href)).to eq("14096")
    end

    it "returns nil for nil input" do
      expect(scraper.send(:extract_product_id, nil)).to be_nil
    end

    it "returns nil for invalid URL" do
      href = "https://example.com/14376"
      expect(scraper.send(:extract_product_id, href)).to be_nil
    end
  end
end
