# frozen_string_literal: true

require "date"
require "json"
require "time"
require "weekly_local_events/eventbrite_api_client"

module WeeklyLocalEvents
  module Scrapers
    # Scrapes Eventbrite events through the authenticated v3 API.
    #
    # Iterates over the validated venue/organization endpoints produced by the
    # source-discovery tasks, follows ?page=N pagination, enriches each event
    # with ticket-class pricing and venue address, and persists the structured
    # result through an EventStore.
    #
    # API quirk: the events endpoints reject `page_size`/`page_number` with
    # HTTP 400; `?page=N` is the only supported pagination parameter.
    class EventbriteScraper
      class Error < StandardError; end
      class TokenExpired < Error; end
      class NoVenuesFound < Error; end

      DEFAULT_MAX_PAGES = 10
      SOURCE_WORKFLOW = "Discover Austin venue/organizer IDs via the public Eventbrite " \
                        "Austin pages, validate them against /v3/venues/{id}/events/ or " \
                        "/v3/organizers/{id}/events/, then persist them as source entries.".freeze

      attr_reader :max_pages, :max_detail_events

      # @param api_client [EventbriteApiClient] rate-limited API client
      # @param sources [Array<Hash>, String, nil] source entries or path to a JSON artifact
      # @param store [EventStore, nil] optional persistence layer
      # @param max_pages [Integer] page cap per source
      # @param max_detail_events [Integer, nil] cap on detail calls per source
      def initialize(api_client:, sources: nil, store: nil,
                     max_pages: DEFAULT_MAX_PAGES, max_detail_events: nil)
        @api_client = api_client
        @sources = sources
        @store = store
        @max_pages = max_pages.to_i
        @max_detail_events = max_detail_events
        @venue_cache = {}
      end

      # Fetch, normalize and optionally persist events.
      #
      # @param sources [Array<Hash>, String, nil] override constructor sources
      # @param max_venues [Integer, nil] limit how many sources are scraped
      # @param date_range [Range<Date>, nil] optional start-date filter
      # @return [Array<Hash>] structured event hashes
      def fetch_events(sources: @sources, max_venues: nil, date_range: nil)
        entries = load_sources(sources)
        raise NoVenuesFound, "No venue/organization sources available. #{SOURCE_WORKFLOW}" if entries.empty?

        selected = max_venues ? entries.first(max_venues.to_i) : entries
        events = []
        seen = {}

        selected.each do |source|
          fetch_source_events(source).each do |event|
            next if seen[event[:id]]
            next unless in_range?(event, date_range)

            seen[event[:id]] = true
            events << event
          end
        end

        store&.write(events)
        events
      rescue EventbriteApiClient::AuthenticationError => e
        raise TokenExpired, "Eventbrite token expired or unauthorized: #{e.message}"
      end

      private

      attr_reader :api_client, :store

      def load_sources(input)
        case input
        when Array
          input
        when String
          data = JSON.parse(File.read(input, encoding: "UTF-8"))
          data.is_a?(Array) ? data : (data["entries"] || data["sources"] || [])
        when nil
          []
        else
          []
        end
      end

      def fetch_source_events(source)
        endpoint = source["endpoint"] || source[:endpoint]
        return [] if endpoint.to_s.empty?

        listed = collect_pages(endpoint)
        detail_budget = max_detail_events ? listed.first(max_detail_events.to_i) : listed
        detail_budget.filter_map { |event| normalize_event(event, source, fetch_detail(event)) }
      end

      # Follow ?page=N pagination until the API says there are no more items.
      def collect_pages(endpoint)
        events = []
        seen_ids = {}
        (1..max_pages).each do |page|
          body = api_client.get(endpoint, query: { page: page })
          page_events = body.is_a?(Hash) ? (body["events"] || []) : []
          break if page_events.empty?

          page_events.each do |event|
            id = event["id"].to_s
            next if id.empty? || seen_ids[id]

            seen_ids[id] = true
            events << event
          end

          pagination = body["pagination"] || {}
          break unless pagination["has_more_items"]
        end
        events
      end

      def fetch_detail(listed_event)
        id = listed_event["id"].to_s
        return nil if id.empty?

        api_client.get("/v3/events/#{id}/", query: { expand: "ticket_classes" })
      rescue EventbriteApiClient::NotFoundError
        nil
      end

      def fetch_venue(venue_id)
        return nil if venue_id.to_s.empty?
        return @venue_cache[venue_id] if @venue_cache.key?(venue_id)

        @venue_cache[venue_id] = api_client.get("/v3/venues/#{venue_id}/", query: {})
      rescue EventbriteApiClient::NotFoundError
        @venue_cache[venue_id] = nil
      end

      def normalize_event(listed, source, detail)
        data = detail.is_a?(Hash) ? detail : listed
        venue = fetch_venue(listed["venue_id"] || data["venue_id"])
        price = price_fields(detail)

        {
          id: data["id"].to_s,
          title: text_of(data, "name"),
          start_date: data.dig("start", "local"),
          end_date: data.dig("end", "local"),
          start_timezone: data.dig("start", "timezone"),
          venue_id: data["venue_id"].to_s,
          venue_name: venue&.dig("name"),
          venue_address: venue&.dig("address", "localized_address_display"),
          ticket_url: data["url"],
          description: data.dig("description", "text"),
          price: price[:display],
          price_cents: price[:cents],
          currency: price[:currency],
          is_free: price[:free],
          source: "eventbrite_api",
          source_type: source["type"] || source[:type],
          source_id: (source["id"] || source[:id]).to_s,
          scraped_at: Time.now.utc.iso8601
        }
      end

      def price_fields(detail)
        classes = detail.is_a?(Hash) ? detail["ticket_classes"] : nil
        return { display: nil, cents: nil, currency: nil, free: nil } unless classes.is_a?(Array)

        visible = classes.reject { |ticket_class| ticket_class["hidden_currently"] }
        return { display: nil, cents: nil, currency: nil, free: nil } if visible.empty?

        paid = visible.reject { |ticket_class| ticket_class["free"] || ticket_class.dig("cost", "value").to_i.zero? }
        chosen = (paid.empty? ? visible : paid).min_by { |ticket_class| ticket_class.dig("cost", "value").to_i }
        cost = chosen["cost"].is_a?(Hash) ? chosen["cost"] : {}
        cents = cost["value"].to_i
        free = chosen["free"] || cents.zero?
        {
          display: free ? "Free" : (cost["display"] || format_cents(cents)),
          cents: cents,
          currency: cost["currency"] || detail["currency"],
          free: free
        }
      end

      def format_cents(cents)
        "$%.2f" % (cents / 100.0)
      end

      def text_of(hash, key)
        value = hash[key]
        value.is_a?(Hash) ? value["text"] : value
      end

      def in_range?(event, date_range)
        return true unless date_range
        return true unless event[:start_date]

        date = Date.parse(event[:start_date])
        date_range.cover?(date)
      rescue ArgumentError
        true
      end
    end
  end
end
