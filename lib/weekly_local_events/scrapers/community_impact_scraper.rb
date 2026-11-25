# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for communityimpact.com/austin/calendar/
    #
    # Fetches the events calendar page and parses JSON-LD structured data
    # (schema.org Event items) embedded in the HTML.
    #
    # HTML structure (JSON-LD):
    #   <script type="application/ld+json">
    #   {
    #     "@type": "CollectionPage",
    #     "mainEntity": {
    #       "@type": "ItemList",
    #       "itemListElement": [
    #         {
    #           "@type": "ListItem",
    #           "item": {
    #             "@type": "Event",
    #             "name": "Event Title",
    #             "startDate": "2026-12-01T19:00:00.000Z",
    #             "endDate": "2026-12-01T21:00:00.000Z",
    #             "description": "Event description text...",
    #             "location": {
    #               "@type": "Place",
    #               "name": "Venue Name",
    #               "address": "123 Main St, Austin, TX 78701"
    #             },
    #             "offers": {
    #               "@type": "Offer",
    #               "price": "15.00",
    #               "priceCurrency": "USD"
    #             }
    #           }
    #         }
    #       ]
    #     }
    #   }
    #   </script>
    #
    # Pagination: /austin/calendar/?from=YYYY-MM-DD&to=YYYY-MM-DD&page=N
    class CommunityImpactScraper < BaseScraper
      BASE_URL = "https://communityimpact.com".freeze
      CALENDAR_PATH = "/austin/calendar/".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "community_impact"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        cfg[:rate_limit_delay] = 2.5
        super(cfg)
      end

      # Fetch all events for the configured date range.
      #
      # @return [Array<Event>]
      def events
        all_events = []
        date_range.start_date.to_date.downto(date_range.end_date.to_date) do |date|
          next if date > Date.today

          page = 1
          loop do
            url = build_calendar_url(date, page)
            events = scrape_page(url)
            break if events.empty?

            all_events.concat(events)
            page += 1
            break unless has_next_page?(url, page)
          end
        end
        all_events
      end

      # Parse an HTML document into Event instances.
      #
      # Extracts JSON-LD structured data from <script type="application/ld+json"> tags
      # and converts schema.org Event items into Event instances.
      #
      # @param html [String, Nokogiri::HTML::Document] the HTML to parse
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil?
        doc = html.is_a?(String) ? parse_html(html) : html
        events_from_json_ld(doc)
      end

      private

      # Build the full calendar URL for a given date and page.
      #
      # @param date [Date] the date to fetch
      # @param page [Integer] page number (1-indexed)
      # @return [String]
      def build_calendar_url(date, page)
        path = "#{CALENDAR_PATH}?from=#{date.strftime('%Y-%m-%d')}&to=#{date.strftime('%Y-%m-%d')}"
        path += "&page=#{page}" if page > 1
        build_url(path)
      end

      # Check if the next page has events (pagination guard).
      #
      # @param current_url [String] the current page URL
      # @param next_page [Integer] the next page number to try
      # @return [Boolean]
      def has_next_page?(current_url, next_page)
        next_page <= 5
      end

      # Parse events from JSON-LD structured data in the HTML.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_json_ld(doc)
        json_ld_scripts = doc.css("script[type='application/ld+json']")
        return [] if json_ld_scripts.empty?

        events = []
        json_ld_scripts.each do |s|
          next unless s.text.strip.length > 100
          begin
            data = JSON.parse(s.text)
            events_from_collection(data) do |event_data, parent_url|
              events << [event_data, parent_url]
            end
          rescue JSON::ParserError
            next
          end
        end

        # Convert raw event hashes to Event instances
        events.map { |event_data, parent_url| parse_event_node(event_data, parent_url) }.compact
      end

      # Extract events from a CollectionPage's mainEntity (ItemList).
      #
      # The URL is at the ListItem level, not inside the Event object.
      #
      # @param data [Hash] the parsed JSON-LD data
      # @yield [Hash, String] each event hash and its parent ListItem URL
      # @return [Array<Hash>]
      def events_from_collection(data)
        results = []
        # Navigate to the CollectionPage's mainEntity
        if data.is_a?(Hash)
          main_entity = data["mainEntity"]
          if main_entity.is_a?(Hash) && main_entity["@type"] == "ItemList"
            items = main_entity["itemListElement"] || []
            items.each do |item|
              next unless item.is_a?(Hash)
              event_data = item["item"]
              next unless event_data.is_a?(Hash) && event_data["@type"] == "Event"
              parent_url = item["url"]
              results << [event_data, parent_url]
            end
          end
        end
        results.each { |e, url| yield e, url }
        results
      end

      # Parse a single Event hash from JSON-LD into an Event instance.
      #
      # @param event_data [Hash] JSON-LD Event data
      # @param parent_url [String, nil] URL from the parent ListItem
      # @return [Event, nil]
      def parse_event_node(event_data, parent_url = nil)
        name = event_data["name"]
        return nil if name.to_s.strip.empty?

        start_date = parse_iso_date(event_data["startDate"])
        end_date = parse_iso_date(event_data["endDate"])
        date = start_date || end_date || Date.today

        time = extract_time_from_date_range(event_data)
        venue = extract_venue(event_data)
        price = extract_price(event_data)
        url = parent_url || resolve_event_url(event_data["url"])
        description = event_data["description"]&.to_s&.strip

        # Handle multi-day events: use start date
        price_cents = price ? normalize_price(price) : nil

        event_hash = {
          title: name.strip,
          date: date,
          time: time,
          venue: venue,
          price: price,
          price_cents: price_cents,
          url: url,
          source: "community_impact",
          description: description,
        }

        Event.from_hash(event_hash)
      rescue EventParseError
        nil
      end

      # Parse an ISO 8601 date string into a Date object.
      #
      # @param date_string [String, nil] ISO 8601 date string
      # @return [Date, nil]
      def parse_iso_date(date_string)
        return nil if date_string.nil? || date_string.to_s.strip.empty?

        s = date_string.to_s.strip

        # Try ISO format: 2026-12-01T19:00:00.000Z
        begin
          # Strip timezone info for Date.parse
          date_part = s.split("T").first
          return Date.parse(date_part)
        rescue ArgumentError, TypeError
          return nil
        end
      end

      # Extract a time string from the event's date range.
      #
      # @param event_data [Hash] JSON-LD Event data
      # @return [String, nil]
      def extract_time_from_date_range(event_data)
        start = event_data["startDate"]
        return nil unless start

        # Try to extract time from ISO string: "2026-12-01T19:00:00.000Z"
        if start =~ /T(\d{2}):(\d{2})/
          hours = $1.to_i
          minutes = $2.to_i
          # Convert from UTC to CST (UTC-6) for display
          hours = (hours - 6) % 24
          format("%02d:%02d", hours, minutes)
        end
      end

      # Extract the venue from JSON-LD Event data.
      #
      # @param event_data [Hash] JSON-LD Event data
      # @return [Venue, nil]
      def extract_venue(event_data)
        location = event_data["location"]
        return nil unless location.is_a?(Hash)

        name = location["name"]
        return nil if name.to_s.strip.empty?

        address = location["address"]
        address_parts = parse_address(address)

        Venue.from_hash({
          name: name.strip,
          address: address_parts[:address],
          city: address_parts[:city],
          state: address_parts[:state],
          zip: address_parts[:zip],
        })
      end

      # Parse a full address string into components.
      #
      # @param address [String, nil] full address string
      # @return [Hash] parsed address components
      def parse_address(address)
        return { address: "", city: "", state: "", zip: "" } unless address

        s = address.to_s.strip
        return { address: s, city: "", state: "", zip: "" } if s.empty?

        # Try to extract city, state, zip from the address
        # Pattern: "123 Main St, Austin, TX 78701"
        match = s.match(/^(.+),\s*([A-Z][a-z]+),\s*([A-Z]{2})\s*(\d{5})$/)
        if match
          {
            address: match[1],
            city: match[2],
            state: match[3],
            zip: match[4],
          }
        else
          {
            address: s,
            city: "",
            state: "",
            zip: "",
          }
        end
      end

      # Extract the price from JSON-LD Event data.
      #
      # @param event_data [Hash] JSON-LD Event data
      # @return [String, nil]
      def extract_price(event_data)
        offers = event_data["offers"]
        return nil unless offers.is_a?(Hash)

        price = offers["price"]
        return nil if price.to_s.strip.empty?

        currency = offers["priceCurrency"] || "USD"
        "$#{price} #{currency}"
      end

      # Extract the event URL from JSON-LD Event data.
      #
      # @param url [String, nil] the event URL
      # @return [String, nil]
      def resolve_event_url(url)
        return nil unless url
        url = url.to_s.strip
        return nil if url.empty? || url.start_with?("#", "javascript:")

        # Make absolute if relative
        return url if url.start_with?("http://", "https://")
        "#{BASE_URL}#{url}"
      end
    end
  end
end
