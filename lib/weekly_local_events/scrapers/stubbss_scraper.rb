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
    # Fetches https://stubbsaustin.com/concert-listings/, parses the
    # #tw-responsive event list and follows "next page" links until no
    # further page is advertised. All network access goes through
    # BaseScraper#fetch, which supplies the configured rate limiting and
    # retry/backoff behaviour.
    #
    # Expected card markup (field order is irrelevant):
    #   <div class="tw-plugin-upcoming-event-list">
    #     <div class="tw-section">
    #       <span class="tw-event-date">10/11</span>
    #       <div class="tw-name"><a href="/tm-event/gospel-brunch/">Gospel Brunch</a></div>
    #       <div class="tw-venue-details"></div>
    #       <span class="tw-event-time">Show: 10:30am</span>
    #       <span class="tw-price">$25</span>
    #       <a class="tw-buy-tix-btn" href="https://...">Buy Tickets</a>
    #       <div class="tw-age-restriction">All Ages</div>
    #     </div>
    #   </div>
    #
    # The listing only exposes month/day, so the year is inferred from
    # +reference_date+ (default: today); a month/day already past is treated
    # as belonging to the following year.
    #
    # Usage:
    #   scraper = StubbssScraper.new(rate_limit_delay: 2.0)
    #   scraper.events # => [Event, ...]
    class StubbssScraper < BaseScraper
      BASE_URL = 'https://stubbsaustin.com'
      EVENTS_PATH = '/concert-listings/'
      SOURCE_NAME = 'stubbss'
      DEFAULT_USER_AGENT = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)".freeze
      DEFAULT_RATE_LIMIT_DELAY = 2.0
      DEFAULT_MAX_PAGES = 50
      DEFAULT_VENUE_NAME = "Stubb's Bar-B-Q".freeze

      # The real page uses one div.tw-section per event. Generic leaf nodes
      # such as tw-event-date must never be treated as cards, so the broad
      # div[class*='event'] catch-all has been removed.
      CARD_SELECTORS = [
        'div.tw-plugin-upcoming-event-list div.tw-section',
        'div.event-card, div.event-item, div.event-entry, div.event-listing'
      ].freeze

      TITLE_SELECTORS = [
        'div.tw-name a',
        'div.tw-name',
        'h3 a',
        'h3',
        'a.event-title',
        "a[class*='event-title']",
        "a[class*='title']"
      ].freeze

      DATE_SELECTORS = [
        'span.tw-event-date',
        "span[class*='date']",
        '.event-date',
        'time[datetime]',
        'time'
      ].freeze

      TIME_SELECTORS = [
        'span.tw-event-time',
        "span[class*='time']",
        '.event-time',
        'time[datetime]',
        'time'
      ].freeze

      VENUE_SELECTORS = ['div.tw-venue-details', 'span.venue'].freeze
      PRICE_SELECTORS = ['span.tw-price', 'span.price'].freeze
      DETAIL_LINK_SELECTOR = 'div.tw-name a[href]'.freeze
      TICKET_LINK_SELECTOR = 'a.tw-buy-tix-btn[href]'.freeze
      AGE_SELECTOR = 'div.tw-age-restriction'.freeze
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
      MONTH_DAY_PATTERN = %r{\A(\d{1,2})/(\d{1,2})\z}
      TIME_PATTERN = /(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)/
      TRAILING_TIME_PATTERN = /\s+(?:at|@)\s*\d{1,2}:\d{2}.*\z/i

      # @param config [Config, Hash, nil] scraper configuration
      # @option config [Float] :rate_limit_delay delay between requests (default 2.0)
      # @option config [Integer] :max_retries retries per request (default 3)
      # @option config [Integer] :max_pages hard cap on paginated pages (default 50)
      # @option config [Date] :reference_date anchor for inferring the year
      #   of the listing's month/day dates (default: today)
      def initialize(config = nil)
        super(normalize_config(config))
        @max_pages = max_pages_from(config).to_i
        @reference_date = reference_date_from(config)

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

      # @param config [Config, Hash, nil]
      # @return [Date]
      def reference_date_from(config)
        raw = config.is_a?(Hash) ? config[:reference_date] : nil
        return Date.today unless raw.is_a?(Date)

        raw
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
          begin_time: time,
          venue: extract_venue(node),
          price: extract_price(node),
          url: extract_url(node),
          source: SOURCE_NAME,
          description: extract_description(node),
          tags: extract_tags(node)
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

          date = parse_listing_date(cleaned)
          return date if date
        end
        nil
      end

      # The listing emits only month/day (e.g. "11/1"). Infer the year from
      # the reference date, treating an already-past month/day as next year.
      # Full dates still go through BaseScraper#normalize_date.
      #
      # @param raw [String]
      # @return [Date, nil]
      def parse_listing_date(raw)
        match = raw.match(MONTH_DAY_PATTERN)
        return normalize_date(raw) unless match

        month = match[1].to_i
        day = match[2].to_i
        year = @reference_date.year
        begin
          candidate = Date.new(year, month, day)
        rescue ArgumentError
          return nil
        end
        return candidate unless candidate < @reference_date

        Date.new(year + 1, month, day)
      rescue ArgumentError
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

      # Stubb's is the venue itself; the listing's tw-venue-details field is
      # normally blank, so fall back to the canonical name.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Venue, nil]
      def extract_venue(node)
        name = VENUE_SELECTORS.filter_map { |selector| nonempty_text(node, selector) }.first
        Venue.from_hash(name: name || DEFAULT_VENUE_NAME)
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        price = PRICE_SELECTORS.filter_map { |selector| nonempty_text(node, selector) }.first
        price.to_s.empty? ? nil : price
      end

      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(node)
        DESCRIPTION_SELECTORS.each do |selector|
          text = nonempty_text(node, selector)
          return text if text
        end
        nil
      end

      # @param node [Nokogiri::XML::Element]
      # @return [Array<String>, nil]
      def extract_tags(node)
        age = nonempty_text(node, AGE_SELECTOR)
        age ? [age] : nil
      end

      def nonempty_text(node, selector)
        text = node.at_css(selector)&.text&.strip
        text.to_s.empty? ? nil : text
      end

      # Prefer the real /tm-event/ detail link; use the ticket CTA only when
      # the card has no detail anchor.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        href = node.at_css(DETAIL_LINK_SELECTOR)&.[]('href')
        href = node.at_css(TICKET_LINK_SELECTOR)&.[]('href') if href.to_s.empty?

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
