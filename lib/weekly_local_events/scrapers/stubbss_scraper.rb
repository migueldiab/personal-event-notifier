# frozen_string_literal: true

require 'weekly_local_events/version'
require 'weekly_local_events/base_scraper'
require 'weekly_local_events/event'
require 'weekly_local_events/venue'
require 'date'
require 'net/http'
require 'time'
require 'uri'

module WeeklyLocalEvents
  module Scrapers
    # Scraper for Stubb's Bar-B-Q events.
    #
    # Fetches https://www.stubbsaustin.com/events/, parses event cards and
    # follows "next page" links until no further page is advertised. All
    # network access goes through BaseScraper#fetch, which supplies the
    # configured rate limiting and retry/backoff behaviour.
    #
    # Expected card markup (field order is irrelevant):
    #   <div class="event-card">
    #     <h3><a href="/events/2026-12-01-jazz-night">Jazz Night</a></h3>
    #     <time datetime="2026-12-01T19:30:00">December 1, 2026</time>
    #     <span class="time">7:30 PM</span>
    #     <span class="venue">Stubb's Bar-B-Q</span>
    #     <span class="price">$25</span>
    #     <p class="description">An evening of jazz.</p>
    #   </div>
    #
    # Pagination is discovered from links such as
    #   <a class="next" href="/events/?page=2">Next</a>
    #
    # Usage:
    #   scraper = StubbssScraper.new(rate_limit_delay: 2.0)
    #   scraper.events # => [Event, ...]
    class StubbssScraper < BaseScraper
      BASE_URL = 'https://www.stubbsaustin.com'
      EVENTS_PATH = '/events/'
      SOURCE_NAME = 'stubbss'
      DEFAULT_USER_AGENT = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)".freeze
      DEFAULT_RATE_LIMIT_DELAY = 2.0
      DEFAULT_MAX_PAGES = 50

      # Ordered from most specific to most general; the first selector that
      # yields any cards wins, which avoids treating layout wrappers as events.
      CARD_SELECTORS = [
        'div.event-card, div.event-item, div.event-entry, div.event-listing',
        "div[class*='event-card'], div[class*='event-item']",
        "div[class*='event']"
      ].freeze

      TITLE_SELECTORS = [
        'h3 a',
        'h3',
        'a.event-title',
        "a[class*='event-title']",
        "a[class*='title']"
      ].freeze

      DATE_SELECTORS = [
        "span[class*='date']",
        '.event-date',
        'time[datetime]',
        'time'
      ].freeze

      TIME_SELECTORS = [
        "span[class*='time']",
        '.event-time',
        'time[datetime]',
        'time'
      ].freeze

      VENUE_SELECTOR = 'span.venue'
      PRICE_SELECTOR = 'span.price'
      DESCRIPTION_SELECTORS = [
        'p.description',
        'div.description',
        'span.description',
        "[class*='description']"
      ].freeze

      NEXT_PAGE_SELECTORS = [
        "link[rel='next'][href]",
        "a[rel='next'][href]",
        'a.next[href]',
        "a[class*='next'][href]",
        "a[class*='pagination'][href]"
      ].freeze

      GENERIC_LINK_TEXT = /\A(?:get\s*tickets?|buy\s*tickets?|tickets?|more\s*info|details?|read\s*more|rsvp)\b/i
      NEXT_LINK_TEXT = /\A(?:next|›|»|&raquo;)\z/i
      TIME_PATTERN = /(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)/
      TRAILING_TIME_PATTERN = /\s+(?:at|@)\s*\d{1,2}:\d{2}.*\z/i

      # @param config [Config, Hash, nil] scraper configuration
      # @option config [Float] :rate_limit_delay delay between requests (default 2.0)
      # @option config [Integer] :max_retries retries per request (default 3)
      # @option config [Integer] :max_pages hard cap on paginated pages (default 50)
      def initialize(config = nil)
        super(normalize_config(config))
        @max_pages = max_pages_from(config).to_i

        # Preserve an explicitly supplied Config so its logger is honoured.
        @config = config if defined?(WeeklyLocalEvents::Config) && config.is_a?(WeeklyLocalEvents::Config)
      end

      # Scrape every advertised page and return all discovered events.
      #
      # Network failures are logged as warnings and produce an empty array
      # rather than raising, so a single broken page cannot abort a pipeline.
      #
      # @return [Array<Event>]
      def events
        collected = []
        visited = Set.new
        url = build_url(EVENTS_PATH)

        while url && visited.size < @max_pages
          break if visited.include?(url)

          visited << url
          doc = fetch_page(url)
          break unless doc

          page_events = parse_response(doc)
          log_warn "No event cards found on #{url}" if page_events.empty?
          collected.concat(page_events)

          url = next_page_url(doc, url)
        end

        collected
      rescue StandardError => e
        log_warn "Failed to scrape events: #{e.class} - #{e.message}"
        []
      end

      # Parse an HTML string or Nokogiri document into Event instances.
      #
      # @param html [String, Nokogiri::HTML::Document, nil]
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil?

        doc = html.is_a?(String) ? parse_html(html) : html
        event_cards(doc).map { |node| parse_event_node(node) }.compact
      end

      private

      # main's BaseScraper has no warn helper; keep warning logs scoped here.
      def log_warn(msg)
        config.logger&.warn("[#{name}] #{msg}")
      end

      # Build a normalized options hash for BaseScraper without mutating the
      # caller's configuration.
      #
      # @param config [Config, Hash, nil]
      # @return [Hash]
      def normalize_config(config)
        cfg = config.is_a?(Hash) ? config.dup : {}
        cfg[:name] = SOURCE_NAME
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = cfg[:user_agent] || cfg[:useragent] || DEFAULT_USER_AGENT
        cfg[:rate_limit_delay] = delay_from(cfg)
        cfg[:max_retries] = (cfg[:max_retries] || 3).to_i
        cfg
      end

      # @param cfg [Hash]
      # @return [Float]
      def delay_from(cfg)
        (cfg[:rate_limit_delay] || cfg[:request_delay] || DEFAULT_RATE_LIMIT_DELAY).to_f
      end

      # @param config [Config, Hash, nil]
      # @return [Integer]
      def max_pages_from(config)
        return DEFAULT_MAX_PAGES unless config.is_a?(Hash)

        config[:max_pages] || DEFAULT_MAX_PAGES
      end

      # Fetch one page using BaseScraper's rate-limited fetch.
      #
      # @param url [String]
      # @return [Nokogiri::HTML::Document, nil]
      def fetch_page(url)
        fetch(url)
      rescue StandardError => e
        log_warn "Failed to fetch #{url}: #{e.class} - #{e.message}"
        nil
      end

      # Select the most specific card nodes available on the page.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Nokogiri::XML::Element>]
      def event_cards(doc)
        CARD_SELECTORS.each do |selector|
          nodes = doc.css(selector).reject { |node| node.at_css(selector) }
          return nodes unless nodes.empty?
        end
        []
      end

      # Convert a single card node into an Event. Missing fields are passed
      # through as nil; Event normalizes optional nils to empty strings.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Event, nil]
      def parse_event_node(node)
        title = extract_title(node)
        return nil if title.to_s.strip.empty?

        time = extract_time(node)
        Event.from_hash(
          title: title,
          date: extract_date(node),
          time: time,
          venue: extract_venue(node),
          price: extract_price(node),
          url: extract_url(node),
          source: SOURCE_NAME,
          description: extract_description(node)
        )
      rescue EventParseError, VenueParseError => e
        log_warn "Skipping invalid event card: #{e.message}"
        nil
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_title(node)
        TITLE_SELECTORS.each do |selector|
          text = node.at_css(selector)&.text&.strip
          return text unless text.to_s.empty?
        end

        node.css('a[href]').each do |link|
          text = link.text.strip
          next if text.empty? || text.match?(GENERIC_LINK_TEXT)

          return text
        end

        nil
      end

      # @param node [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(node)
        candidate_texts(node, DATE_SELECTORS).each do |raw|
          next if raw.to_s.strip.empty?

          cleaned = raw.to_s.strip.sub(TRAILING_TIME_PATTERN, '')
          next if cleaned.strip.empty?

          date = normalize_date(cleaned)
          return date if date
        end
        nil
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_time(node)
        candidate_texts(node, TIME_SELECTORS).each do |raw|
          match = raw.to_s.match(TIME_PATTERN)
          next unless match

          candidate = match[1].sub(/:\d{2}\z/, '').strip
          normalized = normalize_time(candidate)
          return normalized unless normalized.to_s.empty?
        end
        nil
      end

      # Collect raw text candidates from CSS selectors plus the datetime
      # attribute split into its date and time components.
      #
      # @param node [Nokogiri::XML::Element]
      # @param selectors [Array<String>]
      # @return [Array<String>]
      def candidate_texts(node, selectors)
        candidates = []
        selectors.each do |selector|
          node.css(selector).each { |el| candidates << el.text.strip }
        end

        node.css('time[datetime]').each do |el|
          datetime = el['datetime'].to_s.strip
          next if datetime.empty?

          date_part, time_part = datetime.split('T', 2)
          candidates << date_part
          candidates << time_part
        end

        candidates.compact
      end

      # @param node [Nokogiri::XML::Element]
      # @return [Venue, nil]
      def extract_venue(node)
        name = node.at_css(VENUE_SELECTOR)&.text&.strip
        return nil if name.to_s.empty?

        Venue.from_hash(name: name)
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        price = node.at_css(PRICE_SELECTOR)&.text&.strip
        price.to_s.empty? ? nil : price
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(node)
        DESCRIPTION_SELECTORS.each do |selector|
          text = node.at_css(selector)&.text&.strip
          return text unless text.to_s.empty?
        end
        nil
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        link = node.at_css("h3 a[href], a.event-title[href], a[class*='title'][href]")
        href = link && link['href']

        href = node.css('a[href]').map { |a| a['href'] }.find { |candidate| link_href?(candidate) } if href.to_s.empty?

        resolve_link(href)
      end

      # @param href [String, nil]
      # @return [Boolean]
      def link_href?(href)
        !href.to_s.strip.empty? && !href.start_with?('#', 'javascript:', 'mailto:')
      end

      # Resolve a possibly relative href against the configured base URL.
      #
      # @param href [String, nil]
      # @return [String, nil]
      def resolve_link(href)
        return nil if href.to_s.strip.empty?

        href = href.strip
        return nil if href.start_with?('#', 'javascript:', 'mailto:')
        return href if href.start_with?('http://', 'https://')

        "#{BASE_URL}#{'/' unless href.start_with?('/')}#{href}"
      end

      # Find the URL of the next page, if one is advertised.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @param current_url [String]
      # @return [String, nil]
      def next_page_url(doc, current_url)
        link = next_link_element(doc)
        return nil unless link

        resolved = resolve_link(link['href'])
        return nil if resolved == current_url

        resolved
      rescue StandardError => e
        log_warn "Failed to resolve next page after #{current_url}: #{e.class} - #{e.message}"
        nil
      end

      # Locate an explicit next-page link, falling back to link text.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Nokogiri::XML::Element, nil]
      def next_link_element(doc)
        selector = NEXT_PAGE_SELECTORS.find { |candidate| doc.at_css(candidate) }
        return doc.at_css(selector) if selector

        doc.css('a[href]').find do |link|
          link.text.strip.match?(NEXT_LINK_TEXT) && link_href?(link['href'])
        end
      end
    end
  end
end
