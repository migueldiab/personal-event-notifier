# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"
require "json"
require "date"
require "time"
require "net/http"
require "uri"
require "securerandom"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for do512.com/events with page-based pagination.
    #
    # Fetches /events?page=N, parses event listings from the HTML,
    # and returns Event instances with all required fields.
    #
    # HTML structure (DoStuff Media DOM):
    #   <div class="ds-listing event-card ds-event-category-live-music"
    #        data-permalink="/events/2026/11/20/slug">
    #     <a class="ds-listing-event-title url summary" href="/events/...">
    #       <span class="ds-byline">Resound Presents:</span>
    #       <span class="ds-listing-event-title-text">Event Title</span>
    #     </a>
    #     <div class="ds-venue-name" itemprop="location">
    #       <a itemprop="url"><span itemprop="name">Venue Name</span></a>
    #     </div>
    #     <div class="ds-event-time dtstart">7:00PM (doors)</div>
    #     <meta itemprop="startDate" datetime="2026-11-20T19:00">
    #     <ul class="ds-listing-banners">
    #       <li class="ds-listing-soldout"><span>Free</span></li>
    #     </ul>
    #     <div class="ds-btn-container-buy-tix">
    #       <a class="ds-btn ds-btn-large ds-buy-tix" href="https://...">Buy</a>
    #     </div>
    #   </div>
    #
    # Pagination: <div class="slick-nasty slick-initialized slick-slider">
    #   <button class="slick-next" aria-label="next">Next</button>
    # </div>
    #
    # Anti-bot: Cloudflare blocks headless fetches (0-byte response).
    # Uses randomized User-Agent and respects rate limits.
    #
    # Usage:
    #   scraper = Do512Scraper.new(pages: 3)
    #   events = scraper.events
    #   scraper.export_jsonl("data/do512_raw.jsonl")
    class Do512Scraper < BaseScraper
      BASE_URL = "https://www.do512.com".freeze
      EVENTS_PATH = "/events".freeze

      # DoStuff Media class prefixes
      CARD_SELECTOR = "div.ds-listing.event-card".freeze
      TITLE_SELECTOR = "a.ds-listing-event-title".freeze
      TITLE_TEXT_SELECTOR = "span.ds-listing-event-title-text".freeze
      DATE_DISPLAY_SELECTOR = "div.ds-event-time.dtstart".freeze
      DATE_ISO_SELECTOR = 'meta[itemprop="startDate"]'.freeze
      VENUE_SELECTOR = "div.ds-venue-name a".freeze
      VENUE_NAME_SELECTOR = 'span[itemprop="name"]'.freeze
      TICKET_SELECTOR = "div.ds-btn-container-buy-tix a.ds-btn.ds-buy-tix".freeze
      TICKET_URL_META_SELECTOR = 'meta[itemprop="url"]'.freeze
      FREE_BANNER_SELECTOR = "li.ds-listing-soldout span".freeze
      CATEGORY_CLASS_SELECTOR = /ds-event-category-(\S+)/.freeze
      BYLINE_SELECTOR = "span.ds-byline".freeze
      SELLER_SELECTOR = "a.ds-listing-seller".freeze

      # Random User-Agent pool for anti-bot evasion
      USER_AGENTS = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
        "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)",
      ].freeze

      # @param config [Config, Hash, nil] scraper configuration
      # @option config [Integer] :pages Number of pages to scrape (default: 5)
      # @option config [Float] :rate_limit_delay Rate limit between requests in seconds (default: 6.0 = ~10 req/min)
      # @option config [Integer] :max_retries Max retries per request (default: 3)
      # @option config [Integer] :max_pages Max pages to attempt (default: 10)
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "do512"
        cfg[:base_url] = BASE_URL
        cfg[:rate_limit_delay] = cfg[:rate_limit_delay] || cfg[:request_delay] || 6.0
        cfg[:max_retries] = cfg[:max_retries] || 3
        cfg[:user_agent] = random_user_agent
        super(cfg)
        @pages = cfg[:pages] || 5
        @max_pages = cfg[:max_pages] || 10
        @events = []
        @pages_scraped = 0
      end

      # Fetch all events up to the configured page count.
      #
      # @return [Array<Event>]
      def events
        @events = []
        @pages_scraped = 0

        page = 1
        loop do
          break if page > @pages
          break if page > @max_pages

          url = build_events_url(page)
          events = scrape_page(url)
          @pages_scraped += 1

          break if events.empty?

          @events.concat(events)
          page += 1
        end

        @events
      end

      # Parse an HTML document into Event instances.
      #
      # @param html [String, Nokogiri::HTML::Document] the HTML to parse
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil?
        doc = html.is_a?(String) ? parse_html(html) : html
        events_from_doc(doc)
      end

      # Export all scraped events as JSONL to the given file path.
      #
      # Each line is a JSON object representing one event.
      # Creates parent directories if they don't exist.
      #
      # @param path [String] output file path (e.g., "data/do512_raw.jsonl")
      # @return [Integer] number of lines written
      def export_jsonl(path)
        events_to_export = @events.any? ? @events : events
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) if dir != "." && !File.exist?(dir)

        File.open(path, "w") do |f|
          events_to_export.each do |event|
            # JSONL requires exactly one JSON object per line.
            f.puts(event.to_jsonl)
          end
        end

        events_to_export.size
      end

      # @return [Integer] number of pages successfully scraped
      attr_reader :pages_scraped

      # NOTE: no attr_reader for @events here — it would override the #events
      # scraping method defined above and make scraping a no-op.

      # @return [String] the last User-Agent used
      attr_reader :last_user_agent

      private

      # Build the full events URL for a given page number.
      #
      # @param page [Integer] page number (1-indexed)
      # @return [String]
      def build_events_url(page)
        path = "#{EVENTS_PATH}"
        path += "/?page=#{page}" if page > 1
        build_url(path)
      end

      # Perform the actual HTTP request with anti-bot measures.
      #
      # @param uri [URI] the URI to fetch
      # @return [Net::HTTPResponse]
      def perform_request(uri)
        require "net/http"

        # Rotate User-Agent for anti-bot evasion
        @last_user_agent = random_user_agent

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = @last_user_agent
        request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        request["Accept-Language"] = "en-US,en;q=0.9"
        request["Accept-Encoding"] = "gzip, deflate"
        request["Connection"] = "keep-alive"
        request["Upgrade-Insecure-Requests"] = "1"

        # Set cookies from config
        unless cookies.empty?
          cookie_str = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
          request["Cookie"] = cookie_str
        end

        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          read_timeout: config.request_timeout,
          open_timeout: config.request_timeout,
        ) do |http|
          http.request(request)
        end
      end

      # Fetch a page with 403/429 retry logic.
      #
      # @param url [String] the URL to fetch
      # @return [Nokogiri::HTML::Document]
      def fetch_with_retry(url)
        last_error = nil

        @max_retries.times do |attempt|
          begin
            uri = URI(url)
            response = perform_request(uri)

            case response
            when Net::HTTPSuccess
              return parse_html(response.body)
            when Net::HTTPForbidden
              log_warn "HTTP 403 for #{url} (attempt #{attempt + 1}/#{@max_retries})"
              last_error = "HTTP 403"
            when Net::HTTPTooManyRequests
              log_warn "HTTP 429 for #{url} (attempt #{attempt + 1}/#{@max_retries})"
              last_error = "HTTP 429"
            when Net::HTTPNotFound
              return nil # No more events on this page
            else
              log_warn "HTTP #{response.code} for #{url} (attempt #{attempt + 1}/#{@max_retries})"
              last_error = "HTTP #{response.code}"
            end
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
            log_warn "Network error for #{url} (attempt #{attempt + 1}/#{@max_retries}): #{e.class}"
            last_error = e.message
          rescue StandardError => e
            log_warn "Error for #{url} (attempt #{attempt + 1}/#{@max_retries}): #{e.class} - #{e.message}"
            last_error = e.message
          end

          # Exponential backoff with jitter for retries
          if attempt < @max_retries - 1
            backoff = (2**attempt) * rate_limit_delay
            jitter = rand(0.5..1.5)
            sleep(backoff * jitter)
          end
        end

        log_error "Failed to fetch #{url} after #{@max_retries} attempts: #{last_error}"
        nil
      end

      # Scrape a single page: fetch, parse, and return events.
      #
      # @param url [String] the page URL
      # @return [Array<Event>]
      def scrape_page(url)
        html = fetch_with_retry(url)
        return [] unless html

        parse_response(html)
      rescue StandardError => e
        log_error "Error scraping #{url}: #{e.class} - #{e.message}"
        []
      end

      # Parse events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        event_nodes = doc.css(CARD_SELECTOR).reject { |n| n.css("> #{CARD_SELECTOR}").any? }
        event_nodes.map { |node| parse_event_node(node) }.compact
      end

      # Parse a single event card node into an Event.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Event, nil]
      def parse_event_node(node)
        title = extract_title(node)
        return nil if title.to_s.strip.empty?

        date = extract_date(node)
        begin_time = extract_begin_time(node)
        end_time = extract_end_time(node)
        venue = extract_venue(node)
        artists = extract_artists(node)
        category = extract_category(node)
        is_free = extract_is_free(node)
        sold_out = extract_sold_out(node)
        buy_url = extract_buy_url(node)
        description = extract_description(node)

        price = is_free ? "Free" : extract_price(node)
        price_cents = price ? normalize_price(price) : nil

        # Build URL from data-permalink or the title anchor
        url = extract_url(node)

        event_hash = {
          title: title,
          date: date || Date.today,
          time: begin_time,
          begin_time: begin_time,
          end_time: end_time,
          venue: venue,
          artists: artists,
          category: category,
          is_free: is_free,
          sold_out: sold_out,
          buy_url: buy_url,
          price: price,
          price_cents: price_cents,
          url: url,
          source: "do512",
          description: description,
        }

        Event.from_hash(event_hash)
      rescue EventParseError
        nil
      end

      # Extract the event title from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String]
      def extract_title(node)
        title_el = node.at_css(TITLE_TEXT_SELECTOR)
        return title_el.text.strip if title_el

        title_el = node.at_css(TITLE_SELECTOR)
        return title_el.text.strip if title_el

        ""
      end

      # Extract the event date from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(node)
        # Try meta itemprop="startDate"
        meta_el = node.at_css(DATE_ISO_SELECTOR)
        return normalize_date(meta_el["datetime"]) if meta_el

        # Try the URL path: /events/YYYY/MM/DD/...
        permalink = node["data-permalink"]
        if permalink && permalink =~ %r{/events/(\d{4})/(\d{2})/(\d{2})/}
          return Date.new($1.to_i, $2.to_i, $3.to_i)
        end

        nil
      end

      # Extract the begin time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_begin_time(node)
        time_el = node.at_css(DATE_DISPLAY_SELECTOR)
        return nil unless time_el

        text = time_el.text.strip.gsub(/\s*\(doors\)\s*/i, "").strip
        return normalize_time(text) if text.length > 0

        nil
      end

      # Extract the end time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_end_time(node)
        # Try to find a second time element (some events have end times)
        time_elements = node.css(DATE_DISPLAY_SELECTOR)
        return nil if time_elements.size < 2

        text = time_elements[1].text.strip
        return normalize_time(text) if text.length > 0

        nil
      end

      # Extract the venue from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Venue, nil]
      def extract_venue(node)
        venue_text = extract_venue_text(node)
        return nil if venue_text.to_s.strip.empty?

        Venue.from_hash({ name: venue_text.strip })
      end

      # Extract venue text from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String]
      def extract_venue_text(node)
        venue_el = node.at_css("div.ds-venue-name span[itemprop='name']")
        return venue_el.text.strip if venue_el

        venue_el = node.at_css("div.ds-venue-name a")
        return venue_el.text.strip if venue_el

        ""
      end

      # Extract artists from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Array<String>, nil]
      def extract_artists(node)
        artists = []

        # Try .ds-byline for artist names
        byline_el = node.at_css(BYLINE_SELECTOR)
        if byline_el
          text = byline_el.text.strip
          artists << text if text.length > 2
        end

        # Try .ds-listing-seller for ticket seller/organizer
        seller_el = node.at_css(SELLER_SELECTOR)
        if seller_el
          text = seller_el.text.strip
          artists << text if text.length > 2
        end

        return artists.empty? ? nil : artists
      end

      # Extract the category from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_category(node)
        # Category is embedded in the class: ds-event-category-{slug}
        classes = node["class"]
        return nil unless classes

        match = classes.match(CATEGORY_CLASS_SELECTOR)
        return nil unless match

        # Convert slug to readable format: "variety-other" -> "Variety: Other"
        slug = match[1]
        slug.tr("-", " ").split.map(&:capitalize).join(": ")
      end

      # Extract is_free indicator from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Boolean]
      def extract_is_free(node)
        # Primary: check for free banner
        free_el = node.at_css(FREE_BANNER_SELECTOR)
        if free_el
          text = free_el.text.strip
          return true if text.downcase == "free"
        end

        # Fallback: absence of ticket container means free
        ticket_container = node.at_css("div.ds-btn-container-buy-tix")
        return true if ticket_container.nil?

        false
      end

      # Extract sold_out indicator from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Boolean]
      def extract_sold_out(node)
        # Check for sold-out banner
        soldout_el = node.css(".ds-listing-soldout")
        return false if soldout_el.empty?

        # If it has a "Free" span, it's free (not sold out)
        free_span = soldout_el.first.at_css("span")
        return false if free_span && free_span.text.strip.downcase == "free"

        # Check for explicit sold-out indicators
        soldout_text = soldout_el.map(&:text).join(" ").downcase
        return true if soldout_text.include?("sold out") || soldout_text.include?("sold-out")

        false
      end

      # Extract the buy/ticket URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_buy_url(node)
        # Try the ticket button
        ticket_el = node.at_css(TICKET_SELECTOR)
        if ticket_el
          href = ticket_el["href"]
          return resolve_link(href) if href
        end

        # Try the meta itemprop="url" within ticket container
        meta_el = node.at_css("div.ds-btn-container-buy-tix meta[itemprop='url']")
        if meta_el
          content = meta_el["content"]
          return content if content
        end

        nil
      end

      # Extract the price from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        # Check for "Free" in soldout banner
        free_el = node.at_css(FREE_BANNER_SELECTOR)
        if free_el
          text = free_el.text.strip
          return "Free" if text.downcase == "free"
        end

        # Check if ticket container exists (means it's paid)
        ticket_container = node.at_css("div.ds-btn-container-buy-tix")
        return nil unless ticket_container

        # Try to extract price from ticket button text or meta
        meta_el = ticket_container.at_css("meta[itemprop='url']")
        return nil unless meta_el

        # If we have a ticket URL but no explicit price, return nil
        # (price info would be on the ticket page, not the listing)
        nil
      end

      # Extract the event URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        # Try the main event anchor
        link_el = node.at_css(TITLE_SELECTOR)
        return resolve_link(link_el["href"]) if link_el

        # Try data-permalink
        permalink = node["data-permalink"]
        return "#{BASE_URL}#{permalink}" if permalink

        nil
      end

      # Extract the event description from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(node)
        # Get text after the time element (e.g., "Enter for a chance to win...")
        all_text = node.text.strip
        time_el = node.at_css(DATE_DISPLAY_SELECTOR)
        if time_el
          time_text = time_el.text.strip
          idx = all_text.index(time_text)
          if idx
            after_time = all_text[(idx + time_text.length)..-1]
            desc = after_time.gsub(/\s+/, " ").strip
            return desc if desc.length > 5
          end
        end

        # Try the byline as partial description
        byline_el = node.at_css(BYLINE_SELECTOR)
        return byline_el.text.strip if byline_el && byline_el.text.strip.length > 3

        nil
      end

      # Resolve a link to an absolute URL.
      #
      # @param href [String, nil]
      # @return [String, nil]
      def resolve_link(href)
        return nil unless href

        href = href.strip
        return nil if href.start_with?("#", "javascript:")
        return href if href.start_with?("http://", "https://")
        return "#{BASE_URL}#{href}" if href.start_with?("/")

        nil
      end

      # Select a random User-Agent from the pool.
      #
      # @return [String]
      def random_user_agent
        USER_AGENTS.sample
      end
    end
  end
end
