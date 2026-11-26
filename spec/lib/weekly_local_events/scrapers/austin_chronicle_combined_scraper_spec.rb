# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/austin_chronicle_combined_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::AustinChronicleCombinedScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(1) }
  let(:config_with_range) do
    { name: "austin_chronicle_combined", base_url: "https://www.austinchronicle.com",
      date_range: date_range, user_agent: "TestBot/1.0" }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_html) do
    <<~HTML
      <li class="fdn-pres-item uk-child-width-1-1@show-grid">
        <div class="fdn-pres-item-content">
          <div class="fdn-event-search-image-block uk-width-1-3 uk-width-1-3@m uk-width-1-5@show-list">
            <a href="/event/14538326"><img src="..." alt="Image: Live Jazz Night" width="400" height="400"></a>
          </div>
          <div class="fdn-pres-content uk-flex-1 uk-padding-xsmall-right fdn-event-search-text-block">
            <div class="uk-flex uk-flex-center@show-grid">
              <p class="fdn-teaser-headline uk-margin-remove@show-grid">
                <a href="/event/14538326">Live Jazz Night</a>
              </p>
            </div>
            <p class="fdn-teaser-subheadline">Fri., Dec 1, 8:00 PM</p>
            <div class="uk-margin-small fdn-event-teaser-location-block">
              <p class="fdn-event-teaser-location uk-margin-remove">
                <a class="fdn-event-teaser-location-link" href="/location/continental-club-11834712">The Continental Club</a>
              </p>
            </div>
            <div class="fdn-teaser-description uk-text-break">An evening of live jazz featuring local artists.</div>
            <p class="fdn-teaser-tag-link-block fdn-teaser-infoline uk-text-break uk-margin-xsmall-top">
              <a class="fdn-teaser-tag-link" href="?eventCategory=12198149">Jazz</a>
            </p>
            <div class="fdn-pres-details-split fdn-teaser-infoline uk-flex uk-flex-middle uk-margin-remove-bottom fdn-teaser-ticket-block uk-flex-wrap">
              <a class="fdn-teaser-ticket-link uk-flex uk-flex-middle uk-margin-small-right" href="https://coldtowne.com/tickets">Get Tickets $15</a>
            </div>
          </div>
        </div>
      </li>
    HTML
  end

  let(:sample_rss) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"
           xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>The Austin Chronicle</title>
          <link>https://www.austinchronicle.com/</link>
          <description>The Austin Chronicle is an independent, locally owned and operated alternative newsweekly.</description>
          <lastBuildDate>Wed, 25 Nov 2026 19:48:52 +0000</lastBuildDate>
          <language>en-US</language>
          <item>
            <title>Live Jazz Night at Continental Club</title>
            <link>https://www.austinchronicle.com/music/live-jazz-night-continental-club/</link>
            <pubDate>Wed, 25 Nov 2026 19:48:52 +0000</pubDate>
            <dc:creator><![CDATA[John Smith]]></dc:creator>
            <category><![CDATA[Music]]></category>
            <category><![CDATA[Jazz]]></category>
            <description><![CDATA[<p>An evening of live jazz featuring local artists at the Continental Club.</p><p>Doors at 8pm.</p>]]></description>
          </item>
        </channel>
      </rss>
    XML
  end

  describe "#initialize" do
    it "sets the name to austin_chronicle_combined" do
      expect(scraper.name).to eq("austin_chronicle_combined")
    end

    it "sets the base_url to the Austin Chronicle URL" do
      expect(scraper.base_url).to eq("https://www.austinchronicle.com")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end
  end

  describe "#scrape" do
    context "when HTML scraper succeeds" do
      let(:empty_html) { "<html><body></body></html>" }

      before do
        # Stub page 2+ to return empty (scraping stops after first page)
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}&page=\d+})
          .to_return(status: 200, body: empty_html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}$})
          .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })
        # Stub RSS to prevent fallback from attempting real network call
        stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
          .to_return(status: 200, body: sample_rss, headers: { "Content-Type" => "application/rss+xml" })
      end

      it "uses HTML results and skips RSS" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events.size).to eq(1)
        expect(events[0].title).to eq("Live Jazz Night")
        expect(events[0].source).to eq("austin_chronicle")
      end

      it "returns events with correct venue" do
        events = scraper_with_range.scrape
        expect(events[0].venue.name).to eq("The Continental Club")
      end

      it "returns events with correct price" do
        events = scraper_with_range.scrape
        expect(events[0].price).to eq("$15")
      end
    end

    context "when HTML scraper fails" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_raise(Errno::ECONNREFUSED)
        # Stub fetch_raw on the RSS scraper class (affects all instances)
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return(sample_rss)
      end

      it "falls back to RSS" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events.size).to eq(1)
        expect(events[0].title).to eq("Live Jazz Night at Continental Club")
        expect(events[0].source).to eq("austin_chronicle_rss")
      end

      it "sets venue to placeholder for RSS events" do
        events = scraper_with_range.scrape
        expect(events[0].venue.name).to eq("The Austin Chronicle (RSS)")
      end

      it "sets price to nil for RSS events" do
        events = scraper_with_range.scrape
        expect(events[0].price).to eq("")
      end
    end

    context "when HTML scraper returns no events" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_return(status: 200, body: "<html><body></body></html>", headers: { "Content-Type" => "text/html" })
        # Stub fetch_raw on the RSS scraper class
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return(sample_rss)
      end

      it "falls back to RSS" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events.size).to eq(1)
        expect(events[0].source).to eq("austin_chronicle_rss")
      end
    end

    context "when both HTML and RSS fail" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_raise(Errno::ECONNREFUSED)
        # Stub fetch_raw to raise an error
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_raise(Errno::ECONNREFUSED)
      end

      it "returns empty array" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events).to be_empty
      end
    end

    context "when HTML scraper raises HTTP 404" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_return(status: 404)
        # Stub fetch_raw on the RSS scraper class
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return(sample_rss)
      end

      it "falls back to RSS" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events.size).to eq(1)
        expect(events[0].source).to eq("austin_chronicle_rss")
      end
    end

    context "when HTML scraper raises HTTP 429" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_return(status: 429)
        # Stub fetch_raw on the RSS scraper class
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return(sample_rss)
      end

      it "falls back to RSS" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events.size).to eq(1)
        expect(events[0].source).to eq("austin_chronicle_rss")
      end
    end

    context "when both scrapers return no events" do
      before do
        stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
          .to_return(status: 200, body: "<html><body></body></html>")
        # Stub fetch_raw to return empty RSS
        allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return("<rss><channel><title>Empty</title></channel></rss>")
      end

      it "returns empty array" do
        events = scraper_with_range.scrape
        expect(events).to be_an(Array)
        expect(events).to be_empty
      end
    end
  end

  describe "shared event schema" do
    before do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })
      # Stub fetch_raw on the RSS scraper class for fallback tests
      allow_any_instance_of(WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper).to receive(:fetch_raw).and_return(sample_rss)
    end

    it "HTML and RSS events share the same Event class" do
      # HTML events
      html_events = scraper_with_range.scrape
      expect(html_events.first).to be_a(WeeklyLocalEvents::Event)

      # RSS events (trigger fallback by making HTML return empty)
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
        .to_return(status: 200, body: "<html><body></body></html>")
      rss_events = scraper_with_range.scrape
      expect(rss_events.first).to be_a(WeeklyLocalEvents::Event)
    end

    it "both event types have consistent attributes" do
      # HTML event
      html_events = scraper_with_range.scrape
      html_event = html_events.first

      # Reset stubs for RSS
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
        .to_return(status: 200, body: "<html><body></body></html>")
      rss_events = scraper_with_range.scrape
      rss_event = rss_events.first

      # Both should have title, date, url, source
      expect(html_event).to respond_to(:title, :date, :url, :source)
      expect(rss_event).to respond_to(:title, :date, :url, :source)

      # Both should be valid
      expect(html_event).to be_valid
      expect(rss_event).to be_valid
    end

    it "both event types can be serialized to hash" do
      # HTML event
      html_events = scraper_with_range.scrape
      html_hash = html_events.first.to_hash

      # RSS event
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}(&|$)})
        .to_return(status: 200, body: "<html><body></body></html>")
      rss_events = scraper_with_range.scrape
      rss_hash = rss_events.first.to_hash

      # Both should have the same keys
      expect(html_hash.keys).to eq(rss_hash.keys)
    end
  end

  describe "pagination" do
    let(:sample_html_page2) do
      <<~HTML
        <li class="fdn-pres-item uk-child-width-1-1@show-grid">
          <div class="fdn-pres-item-content">
            <div class="fdn-event-search-image-block uk-width-1-3 uk-width-1-3@m uk-width-1-5@show-list">
              <a href="/event/14538327"><img src="..." alt="Image: Second Event" width="400" height="400"></a>
            </div>
            <div class="fdn-pres-content uk-flex-1 uk-padding-xsmall-right fdn-event-search-text-block">
              <p class="fdn-teaser-headline uk-margin-remove@show-grid">
                <a href="/event/14538327">Second Event</a>
              </p>
              <p class="fdn-teaser-subheadline">Sat., Dec 2, 9:00 PM</p>
              <div class="fdn-event-teaser-location-block">
                <p class="fdn-event-teaser-location uk-margin-remove">
                  <a class="fdn-event-teaser-location-link" href="/location/some-venue">Some Venue</a>
                </p>
              </div>
              <div class="fdn-teaser-description uk-text-break">A second event on page 2.</div>
            </div>
          </div>
        </li>
      HTML
    end

    it "scrapes multiple pages from HTML" do
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}$})
        .to_return(status: 200, body: sample_html, headers: { "Content-Type" => "text/html" })
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}&page=2})
        .to_return(status: 200, body: sample_html_page2, headers: { "Content-Type" => "text/html" })
      stub_request(:get, %r{https://www.austinchronicle.com/calendar\?date=\d{4}-\d{2}-\d{2}&page=3})
        .to_return(status: 200, body: "<html><body></body></html>", headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.scrape
      expect(events.size).to eq(2)
      expect(events.map(&:title)).to include("Live Jazz Night", "Second Event")
    end
  end
end
