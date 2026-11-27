# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "weekly_local_events/eventbrite_api_client"
require "weekly_local_events/event_store"
require "weekly_local_events/scrapers/eventbrite_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::EventbriteScraper do
  let(:api_client) { instance_double(WeeklyLocalEvents::EventbriteApiClient) }
  let(:store) { instance_double(WeeklyLocalEvents::EventStore, write: nil) }
  let(:sources) do
    [
      { "type" => "venue", "id" => "100", "endpoint" => "/v3/venues/100/events/" },
      { "type" => "organization", "id" => "200", "endpoint" => "/v3/organizers/200/events/" }
    ]
  end
  let(:scraper) do
    described_class.new(api_client: api_client, sources: sources, store: store, max_pages: 3)
  end

  def list_event(id, name, venue_id = "55")
    {
      "id" => id,
      "name" => { "text" => name },
      "start" => { "local" => "2026-12-05T17:30:00", "utc" => "2026-12-05T23:30:00Z", "timezone" => "America/Chicago" },
      "end" => { "local" => "2026-12-05T20:30:00", "utc" => "2026-12-06T02:30:00Z", "timezone" => "America/Chicago" },
      "venue_id" => venue_id,
      "url" => "https://www.eventbrite.com/e/#{name.downcase.tr(' ', '-')}-tickets-#{id}"
    }
  end

  let(:detail_event) do
    {
      "id" => "1",
      "name" => { "text" => "Wine Tasting" },
      "start" => { "local" => "2026-12-05T17:30:00", "timezone" => "America/Chicago" },
      "end" => { "local" => "2026-12-05T20:30:00", "timezone" => "America/Chicago" },
      "venue_id" => "55",
      "url" => "https://www.eventbrite.com/e/wine-tasting-tickets-1",
      "description" => { "text" => "Taste local wines" },
      "ticket_classes" => [
        { "name" => "General", "cost" => { "value" => 2000, "currency" => "USD", "display" => "$20.00" },
          "free" => false, "hidden_currently" => false, "on_sale_status" => "ON_SALE" },
        { "name" => "VIP", "cost" => { "value" => 7500, "currency" => "USD", "display" => "$75.00" },
          "free" => false, "hidden_currently" => false, "on_sale_status" => "ON_SALE" }
      ]
    }
  end

  let(:venue_detail) do
    {
      "id" => "55",
      "name" => "Central Market",
      "address" => {
        "address_1" => "4001 N Lamar Blvd",
        "city" => "Austin",
        "region" => "TX",
        "postal_code" => "78756",
        "localized_address_display" => "4001 N Lamar Blvd, Austin, TX 78756"
      }
    }
  end

  def stub_api(pages:, details: {}, venues: {})
    listed_events = pages.values.flat_map do |by_page|
      by_page.values.flat_map { |body| body["events"] || [] }
    end
    allow(api_client).to receive(:get) do |path, query:|
      if query[:expand] == "ticket_classes"
        id = path[%r{/v3/events/(\d+)/}, 1]
        listed = listed_events.find { |event| event["id"] == id } || {}
        details.fetch(path, detail_event).merge(
          "id" => id,
          "name" => listed["name"] || detail_event["name"],
          "start" => listed["start"] || detail_event["start"],
          "end" => listed["end"] || detail_event["end"],
          "url" => listed["url"] || detail_event["url"],
          "venue_id" => listed["venue_id"] || detail_event["venue_id"]
        )
      elsif path.start_with?("/v3/venues/") && !path.include?("/events/")
        venues.fetch(path, venue_detail)
      else
        page = query[:page].to_i
        pages.fetch(path, {}).fetch(page, { "events" => [], "pagination" => { "has_more_items" => false } })
      end
    end
  end

  describe "#fetch_events" do
    it "raises NoVenuesFound when no sources are configured" do
      empty = described_class.new(api_client: api_client, sources: [])
      expect { empty.fetch_events }.to raise_error(described_class::NoVenuesFound, /venue/i)
    end

    it "paginates with ?page=N until has_more_items is false" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting")],
                   "pagination" => { "has_more_items" => true } },
            2 => { "events" => [list_event("2", "Jazz Night")],
                   "pagination" => { "has_more_items" => false } }
          }
        }
      )

      events = scraper.fetch_events(max_venues: 1)
      expect(events.map { |e| e[:title] }).to eq(["Wine Tasting", "Jazz Night"])
      expect(api_client).to have_received(:get)
        .with("/v3/venues/100/events/", query: { page: 1 }).once
      expect(api_client).to have_received(:get)
        .with("/v3/venues/100/events/", query: { page: 2 }).once
    end

    it "stops at max_pages" do
      always_more = { "events" => [list_event("3", "More")], "pagination" => { "has_more_items" => true } }
      pages = (1..4).to_h { |page| [page, always_more] }
      stub_api(pages: { "/v3/venues/100/events/" => pages })

      events = scraper.fetch_events(max_venues: 1)
      expect(events.length).to eq(1)
      expect(api_client).to have_received(:get)
        .with("/v3/venues/100/events/", query: { page: 3 }).once
      expect(api_client).to have_received(:get)
        .with("/v3/venues/100/events/", query: { page: 4 }).exactly(0).times
    end

    it "extracts title, dates, venue address, ticket URL and price" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting")],
                   "pagination" => { "has_more_items" => false } }
          }
        }
      )

      event = scraper.fetch_events(max_venues: 1).first
      expect(event).to include(
        id: "1",
        title: "Wine Tasting",
        start_date: "2026-12-05T17:30:00",
        end_date: "2026-12-05T20:30:00",
        venue_name: "Central Market",
        venue_address: "4001 N Lamar Blvd, Austin, TX 78756",
        ticket_url: "https://www.eventbrite.com/e/wine-tasting-tickets-1",
        price: "$20.00",
        price_cents: 2000,
        currency: "USD",
        source: "eventbrite_api"
      )
    end

    it "requests event details with the ticket_classes expansion" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting")],
                   "pagination" => { "has_more_items" => false } }
          }
        }
      )

      scraper.fetch_events(max_venues: 1)
      expect(api_client).to have_received(:get)
        .with("/v3/events/1/", query: { expand: "ticket_classes" }).once
    end

    it "caches venue lookups for events at the same venue" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting"), list_event("2", "Jazz Night")],
                   "pagination" => { "has_more_items" => false } }
          }
        },
        details: {
          "/v3/events/1/" => detail_event,
          "/v3/events/2/" => detail_event.merge("id" => "2")
        }
      )

      scraper.fetch_events(max_venues: 1)
      expect(api_client).to have_received(:get)
        .with("/v3/venues/55/", query: {}).once
    end

    it "keeps an event when the detail endpoint returns 404" do
      allow(api_client).to receive(:get) do |path, query:|
        if path == "/v3/events/1/" && query[:expand] == "ticket_classes"
          raise WeeklyLocalEvents::EventbriteApiClient::NotFoundError
        elsif query[:expand] == "ticket_classes"
          detail_event
        elsif path.start_with?("/v3/venues/") && !path.include?("/events/")
          venue_detail
        else
          { "events" => [list_event("1", "Wine Tasting")],
            "pagination" => { "has_more_items" => false } }
        end
      end

      events = scraper.fetch_events(max_venues: 1)
      expect(events.length).to eq(1)
      expect(events.first[:price]).to be_nil
      expect(events.first[:venue_name]).to eq("Central Market")
    end

    it "translates authentication errors into TokenExpired" do
      allow(api_client).to receive(:get)
        .and_raise(WeeklyLocalEvents::EventbriteApiClient::AuthenticationError)

      expect { scraper.fetch_events(max_venues: 1) }
        .to raise_error(described_class::TokenExpired, /token/i)
    end

    it "persists the structured events through the store" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting")],
                   "pagination" => { "has_more_items" => false } }
          }
        }
      )

      events = scraper.fetch_events(max_venues: 1)
      expect(store).to have_received(:write).with(events).once
    end

    it "filters events to the requested date range" do
      stub_api(
        pages: {
          "/v3/venues/100/events/" => {
            1 => { "events" => [list_event("1", "Wine Tasting")],
                   "pagination" => { "has_more_items" => false } }
          }
        }
      )
      out_of_range = Date.new(2027, 1, 1)..Date.new(2027, 1, 31)

      expect(scraper.fetch_events(max_venues: 1, date_range: out_of_range)).to be_empty
    end

    it "loads sources from a JSON artifact path" do
      path = File.join(Dir.mktmpdir, "sources.json")
      File.write(path, JSON.generate("entries" => sources))
      from_file = described_class.new(api_client: api_client, sources: path, store: store)
      stub_api(pages: {})

      expect { from_file.fetch_events(max_venues: 1) }.not_to raise_error
      FileUtils.remove_entry(File.dirname(path))
    end
  end
end
