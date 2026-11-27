# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/community_impact_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::CommunityImpactScraper do
  subject(:scraper) { described_class.new(config) }

  let(:fixture_html) { File.read(File.expand_path("../fixtures/community_impact_calendar.html", __dir__)) }
  let(:config) do
    {
      date_range_days: 0,
      rate_limit_delay: 0,
      max_retries: 1,
      backoff_base: 0,
      jitter: 0,
    }
  end
  let(:today) { Date.today }
  let(:primary_url) { "https://communityimpact.com/austin/calendar/?from=#{today}&to=#{today}" }
  let(:primary_pattern) { %r{https://communityimpact\.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}} }
  let(:regional_pattern) { %r{https://(satxevents|dfwevents)\.communityimpact\.com/calendar/\?from=\d{4}-\d{2}-\d{2}} }
  let(:satx_pattern) { %r{https://satxevents\.communityimpact\.com/calendar/\?from=\d{4}-\d{2}-\d{2}} }
  let(:dfw_pattern) { %r{https://dfwevents\.communityimpact\.com/calendar/\?from=\d{4}-\d{2}-\d{2}} }
  let(:html_response) { { status: 200, body: fixture_html, headers: { "Content-Type" => "text/html" } } }

  describe "HTML fixture parsing" do
    let(:events) { scraper.parse_response(fixture_html) }

    it "extracts every JSON-LD event from the sample page" do
      expect(events.size).to eq(3)
      expect(events.map(&:title)).to eq(
        [
          "Meet Megan Jaster · Austin Artist of the Month",
          "Holiday Lights Festival",
          "Free Open Mic Night",
        ]
      )
    end

    it "populates the required fields for every extracted event" do
      events.each do |event|
        expect(event.title).not_to be_empty
        expect(event.date).to be_a(Date)
        expect(event.time).to be_a(String)
        expect(event.url).to start_with("https://communityimpact.com/")
        expect(event.source).to eq("community_impact")
      end
    end

    it "reads date, time, venue and description from the ListItem" do
      first = events.first

      expect(first.date).to eq(Date.new(2026, 11, 26))
      expect(first.time).to eq("12:00")
      expect(first.venue.name).to eq("Unchained.Art Contemporary Gallery")
      expect(first.venue.city).to eq("Austin")
      expect(first.venue.state).to eq("TX")
      expect(first.description).to start_with("Austin painter Megan Jaster")
    end

    it "normalizes an explicit schema.org offer into a price" do
      expect(events.last.price).to eq("$0 USD")
      expect(events.last.price_cents).to eq(0)
    end

    it "accepts an already parsed Nokogiri document" do
      document = Nokogiri::HTML5.parse(fixture_html, encoding: "UTF-8")

      expect(scraper.parse_response(document).size).to eq(3)
    end

    it "skips unrelated and malformed JSON-LD blocks without raising" do
      expect(fixture_html).to include('{"@type":"WebSite"}')

      expect { events }.not_to raise_error
      expect(events.size).to eq(3)
    end
  end

  describe "'Multiple showtimes' recurring events" do
    let(:events) { scraper.parse_response(fixture_html) }
    let(:recurring) { events.find { |event| event.title == "Holiday Lights Festival" } }

    it "keeps the literal card label out of the parsed event fields" do
      expect(fixture_html).to include("Multiple showtimes")

      expect(recurring.title).to eq("Holiday Lights Festival")
      expect(recurring.time).not_to eq("Multiple showtimes")
    end

    it "uses the JSON-LD start date and does not expand unavailable showtimes" do
      expect(events.size).to eq(3)
      expect(recurring.date).to eq(Date.new(2026, 11, 26))
      expect(recurring.time).to eq("18:00")
    end

    it "retains the multi-day run description and venue" do
      expect(recurring.description).to include("multiple showtimes")
      expect(recurring.venue.name).to eq("Zilker Park")
    end

    it "handles a recurring event whose JSON-LD has a date but no start time" do
      html = <<~HTML
        <html><head><script type="application/ld+json">
        {"@type":"CollectionPage","mainEntity":{"@type":"ItemList","itemListElement":[
          {"@type":"ListItem","url":"https://communityimpact.com/austin/calendar/all-day/",
           "item":{"@type":"Event","name":"All Day Recurrence","startDate":"2026-11-26","endDate":"2026-11-28"}}
        ]}}</script></head><body><span>Multiple showtimes</span></body></html>
      HTML

      parsed = scraper.parse_response(html)

      expect(parsed.size).to eq(1)
      expect(parsed.first.date).to eq(Date.new(2026, 11, 26))
      expect(parsed.first.time).to eq("")
    end
  end

  describe "rate limiting with stubbed HTTP" do
    it "consults the limiter before the HTTP request" do
      limiter = instance_double(WeeklyLocalEvents::RateLimiter, wait: nil)
      limited = described_class.new(config.merge(rate_limiter: limiter))
      stub_request(:get, primary_pattern).to_return(html_response)
      stub_request(:get, regional_pattern).to_return(status: 503)

      events = limited.events

      expect(events.size).to eq(3)
      expect(limiter).to have_received(:wait).once
    end

    it "paces consecutive requests with an injected clock instead of sleeping in real time" do
      now = [0.0]
      slept = []
      limiter = WeeklyLocalEvents::RateLimiter.new(
        requests_per_minute: 60,
        jitter: 0,
        clock: -> { now[0] },
        sleeper: lambda { |seconds|
          slept << seconds
          now[0] += seconds
        }
      )
      limited = described_class.new(config.merge(rate_limiter: limiter))
      stub_request(:get, primary_pattern).to_return(html_response)
      stub_request(:get, regional_pattern).to_return(status: 503)

      limited.scrape_page(primary_url)
      limited.scrape_page(primary_url)

      expect(slept.length).to eq(1)
      expect(slept.first).to be_within(0.001).of(1.0)
      expect(a_request(:get, primary_pattern)).to have_been_made.twice
    end
  end

  describe "fallback chain (primary → regional → headless)" do
    let(:headless) { instance_double(WeeklyLocalEvents::HeadlessBrowserFetcher, call: fixture_html) }
    let(:chain_scraper) { described_class.new(config.merge(headless_fetcher: headless)) }

    before do
      stub_request(:get, primary_pattern).to_return(status: 429)
      stub_request(:get, regional_pattern).to_return(status: 429)
    end

    it "tries the primary, both regional variants, then the headless browser in order" do
      events = chain_scraper.events

      expect(events.map(&:title)).to include("Meet Megan Jaster · Austin Artist of the Month")
      expect(a_request(:get, primary_pattern)).to have_been_made.once
      expect(a_request(:get, satx_pattern)).to have_been_made.once
      expect(a_request(:get, dfw_pattern)).to have_been_made.once
      expect(headless).to have_received(:call).with(
        primary_url,
        headers: WeeklyLocalEvents::HeadlessBrowserFetcher::STEALTH_HEADERS
      )
    end

    it "stops at the first regional variant that returns HTML" do
      stub_request(:get, satx_pattern).to_return(html_response)

      events = chain_scraper.events

      expect(events.size).to eq(3)
      expect(a_request(:get, dfw_pattern)).not_to have_been_made
      expect(headless).not_to have_received(:call)
    end

    it "returns no events without raising when every route fails" do
      allow(headless).to receive(:call).and_return(nil)

      expect { chain_scraper.events }.not_to raise_error
      expect(chain_scraper.events).to be_empty
    end

    it "stops the chain at a login wall without invoking headless" do
      stub_request(:get, primary_pattern)
        .to_return(status: 302, headers: { "Location" => "https://communityimpact.com/premium-signin" })

      expect(chain_scraper.events).to be_empty
      expect(a_request(:get, satx_pattern)).not_to have_been_made
      expect(headless).not_to have_received(:call)
    end
  end
end
