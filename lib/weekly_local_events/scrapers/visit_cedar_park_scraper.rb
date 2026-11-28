# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"
require "time"
require "tzinfo"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for the client-side Simpleview events widget on visitcedarparktexas.com.
    #
    # The public HTML is behind an Akamai wall, so events are read from the
    # Simpleview REST JSON endpoint discovered in docs/visit_cedar_park_recon.md.
    # A short-lived public token is fetched at runtime and never committed.
    #
    # Both requests use a browser-like User-Agent and the events Referer; the
    # RSpec suite stubs both URLs, so no live network access is required.
    class VisitCedarParkScraper < BaseScraper
      SOURCE_NAME = "visit_cedar_park".freeze
      BASE_URL = "https://visitcedarparktexas.com".freeze
      TOKEN_PATH = "/plugins/core/get_simple_token/".freeze
      EVENTS_PATH = "/includes/rest_v2/plugins_events_events_by_date/find/".freeze
      REFERER = "https://visitcedarparktexas.com/events/".freeze
      DEFAULT_VENUE = "Cedar Park, TX".freeze
      BROWSER_USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                           "(KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze
      DEFAULT_LIMIT = 30
      DEFAULT_MAX_PAGES = 5
      TIMEZONE = TZInfo::Timezone.get("America/Chicago")

      attr_reader :page_size, :max_pages

      # @param config [Config, Hash, nil] scraper configuration; a Hash may set
      #   :page_size, :max_pages, :user_agent and the usual BaseScraper options.
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config.dup : {}
        cfg[:name] = SOURCE_NAME
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] ||= BROWSER_USER_AGENT
        cfg[:headers] = (cfg[:headers] || {}).merge(
          "Referer" => REFERER,
          "Accept" => "application/json, text/plain, */*",
        )
        @page_size = (cfg.delete(:page_size) || DEFAULT_LIMIT).to_i
        @max_pages = (cfg.delete(:max_pages) || DEFAULT_MAX_PAGES).to_i
        super(cfg)
      end

      # Fetch the token and every page of upcoming events.
      #
      # @return [Array<Event>]
      def events
        token = fetch_token
        return [] if token.nil? || token.empty?

        collected = []
        skip = 0
        max_pages.times do
          payload = fetch_page(token, skip)
          break if payload.nil?

          batch = parse_response(payload)
          break if batch.empty?

          collected.concat(batch)
          skip += page_size
          break if skip >= payload.dig("docs", "count").to_i
        end
        collected
      end

      # Parse a Simpleview envelope (or its JSON string) into Event instances.
      #
      # @param payload [Hash, String, nil]
      # @return [Array<Event>]
      def parse_response(payload)
        data = payload.is_a?(String) ? parse_json(payload) : payload
        return [] unless data.is_a?(Hash)

        docs = data.dig("docs", "docs")
        return [] unless docs.is_a?(Array)

        docs.filter_map { |doc| parse_event(doc) }
      end

      private

      # Fetch the short-lived public token. A body that is not a token (for
      # example the site's "Invalid credentials" fake success) is rejected.
      #
      # @return [String, nil]
      def fetch_token
        response = request_with_retries("#{BASE_URL}#{TOKEN_PATH}", "Accept" => "text/plain")
        return nil unless response

        value = response.body.to_s.strip
        return nil if value.empty? || value.match?(/denied|invalid|just a moment/i)

        value
      end

      # Fetch one page of events for the given zero-based offset.
      #
      # @return [Hash, nil]
      def fetch_page(token, skip)
        response = request_with_retries(events_url(token, skip), "Accept" => "application/json")
        return nil unless response

        parse_json(response.body)
      end

      # Build the REST URL for one page. The filter/options object must be
      # URL-encoded as the value of the `json` query parameter.
      #
      # @return [String]
      def events_url(token, skip)
        filter = {
          "filter" => { "active" => true },
          "options" => {
            "limit" => page_size,
            "skip" => skip,
            "count" => true,
            "sort" => { "date" => 1, "rank" => 1, "title_sort" => 1 },
          },
        }
        uri = URI("#{BASE_URL}#{EVENTS_PATH}")
        uri.query = URI.encode_www_form("json" => JSON.generate(filter), "token" => token)
        uri.to_s
      end

      # Perform a request through BaseScraper#http_get with the configured
      # retries. Returns nil rather than raising so one blocked source cannot
      # abort the whole digest.
      #
      # @return [Net::HTTPResponse, nil]
      def request_with_retries(url, extra_headers = {})
        attempts = 0
        begin
          sleep(rate_limit_delay) if attempts.positive?
          response = http_get(url, extra_headers)
          return response if response.is_a?(Net::HTTPSuccess)

          raise ScraperError, "HTTP #{response.code}: #{url}"
        rescue StandardError => e
          attempts += 1
          if attempts < max_retries
            log_warn "Retrying #{url} after #{e.class}: #{e.message}"
            retry
          end
          log_error "Failed to fetch #{url}: #{e.class} - #{e.message}"
          nil
        end
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError, TypeError
        nil
      end

      # Convert one Simpleview document into an Event, or nil when it lacks a
      # usable date or URL.
      #
      # @return [Event, nil]
      def parse_event(doc)
        return nil unless doc.is_a?(Hash)

        title = event_title(doc)
        date = event_date(doc)
        url = event_url(doc)
        return nil if title.empty? || date.nil? || url.nil? || url.empty?

        Event.from_hash(event_hash(doc, title: title, date: date, url: url))
      rescue EventParseError, VenueParseError, ArgumentError
        nil
      end

      def event_title(doc)
        title = doc["title"].to_s.strip
        return title unless title.empty?

        doc["cms_title"].to_s.strip.sub(/\s*\(\d+\)\z/, "")
      end

      def event_hash(doc, title:, date:, url:)
        time = event_time(doc)
        {
          title: title,
          date: date,
          time: time,
          begin_time: time,
          venue: event_venue(doc),
          price: doc["admission"].to_s.strip,
          url: url,
          source: SOURCE_NAME,
          description: event_description(doc),
          image_url: event_image(doc),
          category: event_category(doc),
          buy_url: event_buy_url(doc, url),
        }
      end

      # The listing date is an end-of-local-day UTC instant (05:59:59Z), so it
      # must be converted to America/Chicago before taking the calendar date.
      #
      # @return [Date, nil]
      def event_date(doc)
        candidates = [doc["date"]]
        candidates << doc.dig("dates", "eventDate") if doc["dates"].is_a?(Hash)
        candidates << doc["nextDate"]
        candidates.compact.filter_map { |value| normalize_event_date(value) }.first
      end

      def normalize_event_date(value)
        text = value.to_s.strip
        return nil if text.empty?

        if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(text)
        else
          TIMEZONE.utc_to_local(Time.iso8601(text).utc).to_date
        end
      rescue ArgumentError, TypeError
        nil
      end

      def event_url(doc)
        candidate = doc["absoluteUrl"].to_s.strip
        candidate = doc["url"].to_s.strip if candidate.empty?
        return nil if candidate.empty?
        return candidate if candidate.match?(%r{\Ahttps?://})
        return "#{BASE_URL}#{candidate}" if candidate.start_with?("/")

        nil
      end

      def event_venue(doc)
        name = doc["location"].to_s.strip
        name = doc["hostname"].to_s.strip if name.empty?
        name = DEFAULT_VENUE if name.empty?

        Venue.new(
          name: name,
          address: doc["address1"],
          city: doc["city"],
          state: valid_state(doc["state"]),
          zip: doc["zip"],
          lat: coordinate(doc["latitude"]),
          lng: coordinate(doc["longitude"]),
        )
      end

      def valid_state(value)
        state = value.to_s.strip.upcase
        Venue::US_STATE_CODES.include?(state) ? state : "TX"
      end

      def coordinate(value)
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def event_time(doc)
        start_time = doc["startTime"].to_s.strip
        return normalize_time(start_time[0, 5]) unless start_time.empty?

        match = doc["times"].to_s.match(/(\d{1,2}:\d{2}\s*(?:AM|PM)?)/i)
        match ? normalize_time(match[1]) : nil
      end

      def event_description(doc)
        raw = doc["description"].to_s.strip
        raw = doc["teaser"].to_s.strip if raw.empty?
        return nil if raw.empty?

        text = CGI.unescapeHTML(Nokogiri::HTML5.fragment(raw).text)
        text.gsub(/\s+/, " ").strip
      end

      def event_category(doc)
        categories = doc["categories"].is_a?(Array) ? doc["categories"] : []
        primary_id = doc["primarycatid"] || doc["primaryCatId"]
        chosen = if primary_id
                   categories.find { |category| category["catId"].to_s == primary_id.to_s }
                 end
        (chosen || categories.first)&.[]("catName")
      end

      def event_image(doc)
        media = doc["media_raw"].is_a?(Array) ? doc["media_raw"] : doc["_media"]
        return nil unless media.is_a?(Array)

        media.first&.[]("mediaurl")
      end

      def event_buy_url(doc, canonical_url)
        link = doc["linkUrl"].to_s.strip
        return nil if link.empty? || link == canonical_url

        link
      end
    end
  end
end
