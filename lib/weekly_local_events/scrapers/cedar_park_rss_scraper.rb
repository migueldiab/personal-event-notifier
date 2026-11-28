# frozen_string_literal: true

require "cgi"
require "net/http"
require "nokogiri"
require "time"
require "tzinfo"
require "uri"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for the City of Cedar Park's public CivicEngage calendar RSS feed.
    #
    # The feed is the primary authorized live route (HTTP 200, no credentials).
    # iCalendar and API paths on the same host are Cloudflare-blocked and are
    # deliberately not used here. Each item carries event dates, times and
    # location in namespaced calendarEvent fields; pubDate is only the time the
    # item was published and is never used as the event start.
    #
    # Feed: https://www.cedarparktexas.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml
    # Recon: docs/cedar_park_recon.md
    class CedarParkRssScraper < BaseScraper
      SOURCE_NAME = "cedar_park_rss".freeze
      BASE_URL = "https://www.cedarparktexas.gov".freeze
      FEED_URL = "#{BASE_URL}/RSSFeed.aspx?ModID=58&CID=All-calendar.xml".freeze
      DEFAULT_VENUE = "Cedar Park, TX".freeze
      TIMEZONE = TZInfo::Timezone.get("America/Chicago")
      NAMESPACES = {
        "calendarEvent" => "https://www.cedarparktexas.gov/Calendar.aspx",
      }.freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config.dup : {}
        cfg[:name] = SOURCE_NAME
        cfg[:base_url] = BASE_URL
        super(cfg)
      end

      # Fetch the live feed and parse every item into an Event.
      #
      # @return [Array<Event>]
      def events
        parse_response(fetch_feed)
      rescue ScraperError, Timeout::Error, SocketError, IOError => e
        log_error "RSS fetch failed: #{e.class} - #{e.message}"
        []
      end

      # Parse a feed body (or parsed document) into Event instances.
      #
      # @param xml [String, Nokogiri::XML::Document, nil] raw feed or document
      # @return [Array<Event>]
      def parse_response(xml)
        return [] if xml.nil? || xml.to_s.strip.empty?

        doc = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml.to_s)
        doc.xpath("//item").filter_map { |item| parse_item(item) }
      end

      # Stable dedupe key derived from the calendar event id in the item URL.
      #
      # @param event [Event]
      # @return [String, nil] nil when the URL has no EID
      def dedupe_key(event)
        eid = eid_from_url(event&.url)
        "#{SOURCE_NAME}:#{eid}" if eid
      end

      # Resolve an event's wall-clock start to an instant in America/Chicago.
      # The feed supplies local times with no offset, so no UTC conversion of
      # the date itself is applied (that would shift midnight to the prior day).
      #
      # @param event [Event]
      # @return [Time, nil]
      def starts_at(event)
        return nil unless event&.date

        hour, minute = (event.begin_time || "00:00").split(":").map(&:to_i)
        TIMEZONE.local_time(event.date.year, event.date.month, event.date.day, hour, minute, 0)
      end

      private

      # Fetch raw XML. BaseScraper#fetch parses responses as HTML5, which
      # corrupts RSS <link> elements, so the body is read directly here.
      #
      # @return [String]
      def fetch_feed
        uri = URI(FEED_URL)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "application/rss+xml, application/xml, text/xml"

        response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: config.request_timeout,
          read_timeout: config.request_timeout
        ) { |http| http.request(request) }

        case response
        when Net::HTTPSuccess
          response.body.to_s
        when Net::HTTPTooManyRequests
          raise RateLimitError, "Rate limited: #{FEED_URL}"
        when Net::HTTPNotFound
          raise NotFoundError, "Not found: #{FEED_URL}"
        else
          raise ScraperError, "HTTP #{response.code}: #{FEED_URL}"
        end
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
        tags << "cancelled" if title.match?(/\ACANCELLED:/i)
        start_time, finish_time = time_range(item)

        Event.from_hash(
          title: title,
          date: date,
          time: start_time,
          begin_time: start_time,
          end_time: finish_time,
          venue: event_venue(item),
          price: nil,
          price_cents: nil,
          url: url,
          source: SOURCE_NAME,
          description: description(item),
          tags: tags
        )
      rescue EventParseError, VenueParseError, ArgumentError
        nil
      end

      # The item link is already absolute in the feed. Relative links are
      # resolved against the city host for robustness.
      #
      # @return [String, nil]
      def absolute_link(link)
        return nil if link.empty?
        return link if link.match?(%r{\Ahttps?://})
        return "#{BASE_URL}#{link}" if link.start_with?("/")

        nil
      end

      # Event start date comes from calendarEvent:EventDates (a local calendar
      # date in America/Chicago), never from pubDate (publication time).
      #
      # @return [Date, nil]
      def event_date(item)
        value = namespaced_text(item, "EventDates")
        value = description_field(item, "Event dates?:") if value.empty?
        first = value.split(/\s*(?:-|–|—|\bto\b)\s*/).first.to_s.strip
        normalize_date(first)
      end

      # @return [Array<String, nil>] start and end in 24-hour format
      def time_range(item)
        value = namespaced_text(item, "EventTimes")
        value = description_field(item, "Event Time:") if value.empty?
        parts = value.split(/\s*(?:-|–|—|\bto\b)\s*/).map { |part| normalize_time(part) }
        [parts.first, parts.last]
      end

      # @return [Venue]
      def event_venue(item)
        location = namespaced_text(item, "Location")
        location = description_field(item, "Location:") if location.empty?
        location = location.gsub(%r{<br\s*/?>}i, ", ").gsub(/\s+/, " ").strip
        name = location.empty? ? DEFAULT_VENUE : location

        Venue.new(
          name: name,
          city: city_from(name),
          state: state_from(name),
          zip: zip_from(name)
        )
      end

      # @return [String, nil]
      def city_from(location)
        match = location.match(/\A(.+),\s*[A-Z]{2}\s+\d{5}\z/)
        match && match[1]
      end

      # @return [String, nil]
      def state_from(location)
        location[/(?:,\s*|\b)([A-Z]{2})\s+\d{5}\z/, 1]
      end

      # @return [String, nil]
      def zip_from(location)
        location[/([A-Z]{2})\s+(\d{5})\z/, 2]
      end

      # @return [String] plain-text title or description field
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

      # Fallback for older feeds that only put the value in <description>.
      # @return [String]
      def description_field(item, label)
        match = description(item).match(/#{label}\s*:?\s*(.+?)(?:,?\s*(?:Event Time:|Location:|$))/i)
        match ? match[1].strip : ""
      end

      # @return [String, nil] numeric calendar event id
      def eid_from_url(url)
        url.to_s[/[?&]EID=(\d+)/i, 1]
      end
    end
  end
end
