# frozen_string_literal: true

require "cgi"
require "date"
require "nokogiri"
require "set"
require "time"
require "tzinfo"
require "uri"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Live Cedar Park events source backed by the city's public CivicEngage RSS
    # feed. The feed is the authorized live route (HTTP 200, no credentials);
    # the HTML calendar and API paths on the same host are Cloudflare-blocked
    # and are covered by CedarParkCalendarScraper's archived-snapshot fallback.
    #
    # Every request goes through BaseScraper#http_get so the configured headers,
    # cookies, user agent and timeouts apply. The response body is parsed as XML
    # (BaseScraper#fetch parses as HTML5, which corrupts RSS <link> elements).
    #
    # Feed: https://www.cedarparktexas.gov/RSSFeed.aspx?CID=All-calendar.xml&ModID=58
    # Recon: docs/cedar_park_recon.md
    class CedarParkScraper < BaseScraper
      SOURCE_NAME = "cedar_park".freeze
      BASE_URL = "https://www.cedarparktexas.gov".freeze
      EVENTS_PATH = "/RSSFeed.aspx?CID=All-calendar.xml&ModID=58".freeze
      FEED_URL = "#{BASE_URL}#{EVENTS_PATH}".freeze

      DEFAULT_VENUE_NAME = "Cedar Park Parks & Recreation".freeze
      DEFAULT_VENUE_ADDRESS = "1435 Main Street".freeze
      DEFAULT_VENUE_CITY = "Cedar Park".freeze
      DEFAULT_VENUE_STATE = "TX".freeze
      DEFAULT_VENUE_ZIP = "78613".freeze

      TIMEZONE = TZInfo::Timezone.get("America/Chicago")
      NAMESPACES = {
        "calendarEvent" => "https://www.cedarparktexas.gov/Calendar.aspx",
      }.freeze

      RANGE_SEPARATOR = /\s*(?:-|–|—|\bto\b)\s*/i.freeze
      CANCELLED_PREFIX = /\ACANCELLED:/i.freeze
      STREET_LOCATION = /\A(.+?),\s*([^,]+),\s*([A-Z]{2})\s+(\d{5})\z/.freeze
      NEXT_PAGE_XPATH = "//*[local-name()='link' and @rel='next']/@href".freeze
      MAX_PAGES = 10

      attr_reader :default_venue

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config.dup : {}
        cfg[:name] = SOURCE_NAME
        cfg[:base_url] = BASE_URL
        super(cfg)
        @config = config if defined?(WeeklyLocalEvents::Config) && config.is_a?(WeeklyLocalEvents::Config)
        @default_venue = Venue.new(
          name: DEFAULT_VENUE_NAME,
          address: DEFAULT_VENUE_ADDRESS,
          city: DEFAULT_VENUE_CITY,
          state: DEFAULT_VENUE_STATE,
          zip: DEFAULT_VENUE_ZIP
        )
      end

      # Fetch the live feed (and any advertised next pages) and parse every
      # usable item into an Event. Repeated EIDs are emitted only once.
      #
      # @return [Array<Event>]
      def events
        collected = []
        seen = Set.new
        visited = Set.new
        url = FEED_URL

        while url && visited.size < MAX_PAGES && !visited.include?(url)
          visited << url
          body = fetch_feed(url)
          break if body.to_s.strip.empty?

          doc = parse_feed(body)
          parse_response(doc).each do |event|
            key = dedupe_key(event)
            next if key && seen.include?(key)

            seen.add(key) if key
            collected << event
          end

          url = next_page_url(doc, url)
        end
        collected
      rescue RateLimitError, NotFoundError, ScraperError, Timeout::Error, SocketError, IOError => e
        log_error "Cedar Park feed fetch failed: #{e.class} - #{e.message}"
        collected
      end

      # Parse a feed body (or an already-parsed document) into Event instances.
      # Items without a usable title, absolute URL or date are skipped.
      #
      # @param xml [String, Nokogiri::XML::Document, nil] raw feed or document
      # @return [Array<Event>]
      def parse_response(xml)
        return [] if xml.nil? || xml.to_s.strip.empty?

        doc = if xml.is_a?(Nokogiri::XML::Document) || xml.is_a?(Nokogiri::HTML::Document)
                xml
              else
                Nokogiri::XML(xml.to_s)
              end
        doc.xpath("//item").filter_map { |item| parse_item(item) }
      end

      # Stable dedupe key derived from the calendar event id in the item URL.
      #
      # @param event [Event, nil]
      # @return [String, nil] nil when the URL has no EID
      def dedupe_key(event)
        eid = eid_from_url(event&.url)
        "#{SOURCE_NAME}:#{eid}" if eid
      end

      # Resolve an event's wall-clock start to an instant in America/Chicago.
      # The feed supplies local times with no offset, so no UTC conversion of
      # the date itself is applied (that would shift midnight to the prior day).
      #
      # @param event [Event, nil]
      # @return [Time, nil]
      def starts_at(event)
        return nil unless event&.date

        hour, minute = (event.begin_time || event.time || "00:00").to_s.split(":").map(&:to_i)
        TIMEZONE.local_time(event.date.year, event.date.month, event.date.day, hour, minute, 0)
      end

      private

      # Fetch one page through BaseScraper's configured request pipeline.
      #
      # @param url [String] absolute feed URL
      # @return [String] raw XML body
      def fetch_feed(url)
        response = http_get(url, "Accept" => "application/rss+xml, application/xml, text/xml")

        case response
        when Net::HTTPSuccess
          response.body.to_s
        when Net::HTTPTooManyRequests
          raise RateLimitError, "Rate limited: #{url}"
        when Net::HTTPNotFound
          raise NotFoundError, "Not found: #{url}"
        else
          raise ScraperError, "HTTP #{response.code}: #{url}"
        end
      end

      # @param body [String, Nokogiri::XML::Document]
      # @return [Nokogiri::XML::Document]
      def parse_feed(body)
        body.is_a?(Nokogiri::XML::Document) ? body : Nokogiri::XML(body.to_s)
      end

      # The live feed does not advertise pagination, but honour an Atom
      # rel="next" link when a future feed does.
      #
      # @param doc [Nokogiri::XML::Document]
      # @param current_url [String]
      # @return [String, nil]
      def next_page_url(doc, current_url)
        href = doc.xpath(NEXT_PAGE_XPATH).map(&:value).find { |value| !value.to_s.strip.empty? }
        return nil if href.nil?

        resolved = absolute_link(href.strip)
        return nil if resolved.nil? || resolved == current_url

        resolved
      end

      # @param item [Nokogiri::XML::Element]
      # @return [Event, nil]
      def parse_item(item)
        title = text_of(item, "title")
        url = absolute_link(text_of(item, "link"))
        date = event_date(item)
        return nil if title.empty? || url.nil? || date.nil?

        eid = eid_from_url(url)
        tags = []
        tags << "eid:#{eid}" if eid
        tags << "cancelled" if title.match?(CANCELLED_PREFIX)
        start_time, finish_time = time_range(item)

        Event.from_hash(
          title: title,
          date: date,
          time: start_time,
          begin_time: start_time,
          end_time: finish_time,
          venue: event_venue(item),
          price: price(item),
          price_cents: price_cents(item),
          url: url,
          source: SOURCE_NAME,
          description: description(item),
          category: category(item),
          tags: tags
        )
      rescue EventParseError, VenueParseError, ArgumentError
        nil
      end

      # Event start comes from calendarEvent:EventDates, never from pubDate
      # (which is publication time). Multi-day ranges use the first date.
      #
      # @return [Date, nil]
      def event_date(item)
        value = namespaced_text(item, "EventDates")
        value = description_field(item, "Event dates?") if value.empty?
        normalize_date(value.split(RANGE_SEPARATOR).first.to_s.strip)
      end

      # @return [Array<String, nil>] start and end in 24-hour format
      def time_range(item)
        value = namespaced_text(item, "EventTimes")
        value = description_field(item, "Event Time") if value.empty?
        parts = value.split(RANGE_SEPARATOR).filter_map { |part| normalize_time(part) }
        [parts.first, parts.last]
      end

      # The feed's Location is usually a city/state line; use the city's Parks
      # & Recreation address in that case, but keep a real street address when
      # the feed supplies one.
      #
      # @return [Venue]
      def event_venue(item)
        location = namespaced_text(item, "Location")
        location = description_field(item, "Location") if location.empty?
        location = location.gsub(%r{<br\s*/?>}i, ", ").gsub(/\s+/, " ").strip
        return default_venue if location.empty?

        match = location.match(STREET_LOCATION)
        return default_venue unless match

        Venue.new(
          name: location,
          address: match[1].strip,
          city: match[2].strip,
          state: match[3].upcase,
          zip: match[4]
        )
      rescue VenueParseError
        default_venue
      end

      # @return [String, nil]
      def price(item)
        raw = text_of(item, "price")
        raw = description_field(item, "Price") if raw.empty?
        raw.to_s.strip.empty? ? nil : raw
      end

      # @return [Integer, nil]
      def price_cents(item)
        raw = price(item)
        raw ? normalize_price(raw) : nil
      end

      # @return [String, nil]
      def category(item)
        text = text_of(item, "category")
        text.empty? ? nil : text
      end

      # @return [String]
      def text_of(item, name)
        node = item.at_xpath(name)
        node ? node.text.strip : ""
      end

      # @return [String] text from a namespaced calendarEvent field
      def namespaced_text(item, field)
        node = item.at_xpath("calendarEvent:#{field}", NAMESPACES)
        node ? node.text.strip : ""
      end

      # @return [String] cleaned HTML description
      def description(item)
        raw = text_of(item, "description")
        text = CGI.unescapeHTML(raw).gsub(%r{<br\s*/?>}i, ", ").gsub(/<[^>]+>/, " ")
        text.gsub(/\s+/, " ").strip
      end

      # Fallback for older feeds that only put a value in <description>.
      #
      # @return [String]
      def description_field(item, label)
        pattern = /#{Regexp.escape(label)}\s*:?\s*(.+?)(?:,?\s*(?:Event Time:|Location:|$))/i
        match = description(item).match(pattern)
        match ? match[1].strip : ""
      end

      # @return [String, nil]
      def absolute_link(link)
        return nil if link.to_s.strip.empty?
        return link if link.match?(%r{\Ahttps?://})
        return "#{BASE_URL}#{link}" if link.start_with?("/")

        nil
      end

      # @return [String, nil] numeric calendar event id
      def eid_from_url(url)
        url.to_s[/[?&]EID=(\d+)/i, 1]
      end
    end
  end
end
