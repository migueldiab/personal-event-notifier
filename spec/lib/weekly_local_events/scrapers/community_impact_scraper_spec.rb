# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/community_impact_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::CommunityImpactScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(3) }
  let(:config_with_range) do
    { name: "community_impact", base_url: "https://communityimpact.com",
      date_range: date_range, user_agent: "TestBot/1.0" }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_json_ld) do
    <<~JSON
      {
        "@type": "CollectionPage",
        "@id": "https://communityimpact.com/austin/calendar/",
        "url": "https://communityimpact.com/austin/calendar/",
        "name": "Austin Events",
        "description": "Local events happening across Austin.",
        "inLanguage": "en-US",
        "mainEntity": {
          "@type": "ItemList",
          "itemListOrder": "https://schema.org/ItemListOrderAscending",
          "numberOfItems": 3,
          "itemListElement": [
            {
              "@type": "ListItem",
              "position": 1,
              "url": "https://communityimpact.com/austin/calendar/meet-megan-jaster-austin-artist-of-the-month/",
              "item": {
                "@type": "Event",
                "name": "Meet Megan Jaster · Austin Artist of the Month",
                "startDate": "2026-12-01T19:00:00.000Z",
                "endDate": "2026-12-01T21:00:00.000Z",
                "eventStatus": "https://schema.org/EventScheduled",
                "description": "Austin painter Megan Jaster is November's Austin Artist of the Month at Unchained.Art Contemporary Gallery.",
                "location": {
                  "@type": "Place",
                  "name": "Unchained.Art Contemporary Gallery",
                  "address": "311 West 7th Street, Suite 307, Austin, TX 78701"
                },
                "keywords": "Arts"
              }
            },
            {
              "@type": "ListItem",
              "position": 2,
              "url": "https://communityimpact.com/austin/calendar/live-jazz-night/",
              "item": {
                "@type": "Event",
                "name": "Live Jazz Night",
                "startDate": "2026-12-02T20:00:00.000Z",
                "endDate": "2026-12-02T23:00:00.000Z",
                "description": "An evening of live jazz featuring local artists.",
                "location": {
                  "@type": "Place",
                  "name": "The Continental Club",
                  "address": "1315 S Congress Ave, Austin, TX 78704"
                },
                "offers": {
                  "@type": "Offer",
                  "price": "15.00",
                  "priceCurrency": "USD"
                },
                "keywords": "Music"
              }
            },
            {
              "@type": "ListItem",
              "position": 3,
              "url": "https://communityimpact.com/austin/calendar/free-open-mic/",
              "item": {
                "@type": "Event",
                "name": "Free Open Mic Night",
                "startDate": "2026-12-03T19:00:00.000Z",
                "endDate": "2026-12-03T22:00:00.000Z",
                "description": "Open mic night for local performers.",
                "location": {
                  "@type": "Place",
                  "name": "Bathtub Row",
                  "address": "1417 S Congress Ave, Austin, TX 78704"
                },
                "offers": {
                  "@type": "Offer",
                  "price": "0",
                  "priceCurrency": "USD"
                },
                "keywords": "Music"
              }
            }
          ]
        }
      }
    JSON
  end

  let(:sample_json_ld_multi_day) do
    <<~JSON
      {
        "@type": "CollectionPage",
        "mainEntity": {
          "@type": "ItemList",
          "itemListElement": [
            {
              "@type": "ListItem",
              "position": 1,
              "url": "https://communityimpact.com/austin/calendar/holiday-lights/",
              "item": {
                "@type": "Event",
                "name": "Holiday Lights Festival",
                "startDate": "2026-12-10T00:00:00.000Z",
                "endDate": "2026-12-24T23:59:59.999Z",
                "description": "A month-long holiday lights display.",
                "location": {
                  "@type": "Place",
                  "name": "Zilker Park",
                  "address": "2100 Barton Springs Rd, Austin, TX 78746"
                }
              }
            }
          ]
        }
      }
    JSON
  end

  let(:sample_json_ld_no_venue) do
    <<~JSON
      {
        "@type": "CollectionPage",
        "mainEntity": {
          "@type": "ItemList",
          "itemListElement": [
            {
              "@type": "ListItem",
              "position": 1,
              "url": "https://communityimpact.com/austin/calendar/virtual-event/",
              "item": {
                "@type": "Event",
                "name": "Virtual Workshop",
                "startDate": "2026-12-05T14:00:00.000Z",
                "endDate": "2026-12-05T16:00:00.000Z",
                "description": "An online workshop."
              }
            }
          ]
        }
      }
    JSON
  end

  describe "#initialize" do
    it "sets the name to community_impact" do
      expect(scraper.name).to eq("community_impact")
    end

    it "sets the base_url to the Community Impact URL" do
      expect(scraper.base_url).to eq("https://communityimpact.com")
    end

    it "sets a proper user agent" do
      expect(scraper.user_agent).to include("WeeklyLocalEvents")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end
  end

  describe "#parse_response" do
    it "parses events from JSON-LD structured data" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events).to be_an(Array)
      expect(events.size).to eq(3)
    end

    it "extracts title from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].title).to eq("Meet Megan Jaster · Austin Artist of the Month")
      expect(events[1].title).to eq("Live Jazz Night")
      expect(events[2].title).to eq("Free Open Mic Night")
    end

    it "extracts date from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].date).to eq(Date.new(2026, 12, 1))
      expect(events[1].date).to eq(Date.new(2026, 12, 2))
      expect(events[2].date).to eq(Date.new(2026, 12, 3))
    end

    it "extracts time from events (converting UTC to CST)" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      # 19:00 UTC = 13:00 CST
      expect(events[0].time).to eq("13:00")
      # 20:00 UTC = 14:00 CST
      expect(events[1].time).to eq("14:00")
    end

    it "extracts venue from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].venue.name).to eq("Unchained.Art Contemporary Gallery")
      expect(events[0].venue.city).to eq("Austin")
      expect(events[0].venue.state).to eq("TX")
      expect(events[0].venue.zip).to eq("78701")
    end

    it "extracts price from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].price).to eq("")
      expect(events[1].price).to eq("$15.00 USD")
      expect(events[1].price_cents).to eq(1500)
      expect(events[2].price).to eq("$0 USD")
      expect(events[2].price_cents).to eq(0)
    end

    it "extracts URL from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].url).to eq("https://communityimpact.com/austin/calendar/meet-megan-jaster-austin-artist-of-the-month/")
      expect(events[1].url).to eq("https://communityimpact.com/austin/calendar/live-jazz-night/")
    end

    it "extracts description from events" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].description).to eq("Austin painter Megan Jaster is November's Austin Artist of the Month at Unchained.Art Contemporary Gallery.")
    end

    it "sets source to community_impact" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events[0].source).to eq("community_impact")
    end

    it "handles multi-day events (uses start date)" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld_multi_day}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Holiday Lights Festival")
      expect(events[0].date).to eq(Date.new(2026, 12, 10))
    end

    it "handles events without a venue" do
      html = "<html><head><script type=\"application/ld+json\">#{sample_json_ld_no_venue}</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("Virtual Workshop")
      expect(events[0].venue).to be_nil
    end

    it "handles missing time gracefully" do
      html_no_time = <<~HTML
        <html><head><script type="application/ld+json">
        {
          "@type": "CollectionPage",
          "mainEntity": {
            "@type": "ItemList",
            "itemListElement": [
              {
                "@type": "ListItem",
                "item": {
                  "@type": "Event",
                  "name": "No Time Event",
                  "startDate": "2026-12-05"
                }
              }
            ]
          }
        }
        </script></head><body></body></html>
      HTML
      events = scraper.parse_response(html_no_time)
      expect(events.size).to eq(1)
      expect(events[0].title).to eq("No Time Event")
      # Event normalizes nil time to "" (ActiveModel behavior)
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

    it "returns empty array for invalid JSON-LD" do
      html = "<html><head><script type=\"application/ld+json\">{invalid json</script></head><body></body></html>"
      events = scraper.parse_response(html)
      expect(events).to be_empty
    end

    it "skips events without a name" do
      html = <<~HTML
        <html><head><script type="application/ld+json">
        {
          "@type": "CollectionPage",
          "mainEntity": {
            "@type": "ItemList",
            "itemListElement": [
              {
                "@type": "ListItem",
                "item": {
                  "@type": "Event",
                  "name": ""
                }
              }
            ]
          }
        }
        </script></head><body></body></html>
      HTML
      events = scraper.parse_response(html)
      expect(events).to be_empty
    end
  end

  describe "#events" do
    it "returns an array of Event objects" do
      stub_request(:get, %r{https://communityimpact.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}})
        .to_return(status: 200, body: "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>", headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, %r{https://communityimpact.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}})
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, %r{https://communityimpact.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}})
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, %r{https://communityimpact.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}})
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles pagination across multiple pages" do
      stub_request(:get, %r{https://communityimpact.com/austin/calendar/\?from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}&page=\d+})
        .to_return(status: 200, body: "<html><head><script type=\"application/ld+json\">#{sample_json_ld}</script></head><body></body></html>", headers: { "Content-Type" => "text/html" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end
  end

  describe "#build_calendar_url" do
    it "builds correct URL for a given date" do
      date = Date.new(2026, 12, 1)
      url = scraper.send(:build_calendar_url, date, 1)
      expect(url).to eq("https://communityimpact.com/austin/calendar/?from=2026-12-01&to=2026-12-01")
    end

    it "adds page parameter for pagination" do
      date = Date.new(2026, 12, 1)
      url = scraper.send(:build_calendar_url, date, 3)
      expect(url).to eq("https://communityimpact.com/austin/calendar/?from=2026-12-01&to=2026-12-01&page=3")
    end
  end

  describe "#parse_iso_date" do
    it "parses ISO 8601 date string" do
      date = scraper.send(:parse_iso_date, "2026-12-01T19:00:00.000Z")
      expect(date).to eq(Date.new(2026, 12, 1))
    end

    it "handles nil input" do
      expect(scraper.send(:parse_iso_date, nil)).to be_nil
    end

    it "handles empty string input" do
      expect(scraper.send(:parse_iso_date, "")).to be_nil
    end

    it "handles invalid date string" do
      expect(scraper.send(:parse_iso_date, "not-a-date")).to be_nil
    end
  end

  describe "#extract_time_from_date_range" do
    it "extracts time from ISO date string" do
      event_data = { "startDate" => "2026-12-01T19:00:00.000Z" }
      time = scraper.send(:extract_time_from_date_range, event_data)
      expect(time).to eq("13:00")
    end

    it "handles nil startDate" do
      event_data = {}
      expect(scraper.send(:extract_time_from_date_range, event_data)).to be_nil
    end

    it "converts midnight UTC to 6 PM CST previous day" do
      event_data = { "startDate" => "2026-12-01T00:00:00.000Z" }
      time = scraper.send(:extract_time_from_date_range, event_data)
      expect(time).to eq("18:00")
    end

    it "handles noon UTC" do
      event_data = { "startDate" => "2026-12-01T12:00:00.000Z" }
      time = scraper.send(:extract_time_from_date_range, event_data)
      expect(time).to eq("06:00")
    end
  end

  describe "#parse_address" do
    it "parses full address with city, state, zip" do
      result = scraper.send(:parse_address, "311 West 7th Street, Suite 307, Austin, TX 78701")
      expect(result[:address]).to eq("311 West 7th Street, Suite 307")
      expect(result[:city]).to eq("Austin")
      expect(result[:state]).to eq("TX")
      expect(result[:zip]).to eq("78701")
    end

    it "handles address without city/state/zip" do
      result = scraper.send(:parse_address, "123 Main Street")
      expect(result[:address]).to eq("123 Main Street")
      expect(result[:city]).to be_empty
    end

    it "handles nil input" do
      result = scraper.send(:parse_address, nil)
      expect(result[:address]).to be_empty
    end
  end

  describe "#extract_price" do
    it "extracts price from offers" do
      event_data = { "offers" => { "price" => "25.00", "priceCurrency" => "USD" } }
      price = scraper.send(:extract_price, event_data)
      expect(price).to eq("$25.00 USD")
    end

    it "handles missing offers" do
      event_data = {}
      expect(scraper.send(:extract_price, event_data)).to be_nil
    end

    it "handles nil price" do
      event_data = { "offers" => {} }
      expect(scraper.send(:extract_price, event_data)).to be_nil
    end
  end

  describe "#resolve_event_url" do
    it "returns absolute URLs as-is" do
      url = scraper.send(:resolve_event_url, "https://communityimpact.com/austin/calendar/test/")
      expect(url).to eq("https://communityimpact.com/austin/calendar/test/")
    end

    it "makes relative URLs absolute" do
      url = scraper.send(:resolve_event_url, "/austin/calendar/test/")
      expect(url).to eq("https://communityimpact.com/austin/calendar/test/")
    end

    it "handles nil input" do
      expect(scraper.send(:resolve_event_url, nil)).to be_nil
    end

    it "handles empty string" do
      expect(scraper.send(:resolve_event_url, "")).to be_nil
    end
  end
end
