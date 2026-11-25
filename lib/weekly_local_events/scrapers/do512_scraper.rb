# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for do512.com/events.
    #
    # Fetches the events page for each date in the configured date range,
    # parses event listings from the HTML, and returns Event instances.
    #
    # HTML structure (Do512 events page):
    #   <div class="ds-listing event-card ds-event-category-live-music">
    #     <a class="ds-listing-event-title url summary" href="/events/2026/11/25/...">
    #       <span class="ds-byline">Resound Presents:</span>
    #       <span class="ds-listing-event-title-text">Event Title</span>
    #     </a>
    #     <div class="ds-venue-name">
    #       <a itemprop="url"><span itemprop="name">Venue Name</span></a>
    #       <span itemprop="address"><meta itemprop="streetAddress">...</meta></span>
    #     </div>
    #     <div class="ds-event-time dtstart">7:00PM (doors)</div>
    #     <meta itemprop="startDate" datetime="2026-11-25T19:00">
    #     <li class="ds-listing-soldout"><span>Free</span></li>
    #   </div>
    #
    # Pagination: <div class="ds-paging"><a href="/?page=2" class="ds-next-page">Next Page</a></div>
    class Do512Scraper < BaseScraper
      BASE_URL = "https://www.do512.com".freeze
      EVENTS_PATH = "/events".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "do512"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        cfg[:rate_limit_delay] = 3.0
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
            url = build_events_url(date, page)
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
      # @param html [String, Nokogiri::HTML::Document] the HTML to parse
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil?
        doc = html.is_a?(String) ? parse_html(html) : html
        events_from_doc(doc)
      end

      private

      # Build the full events URL for a given date and page.
      #
      # @param date [Date] the date to fetch
      # @param page [Integer] page number (1-indexed)
      # @return [String]
      def build_events_url(date, page)
        path = "#{EVENTS_PATH}/?date=#{date.strftime('%Y-%m-%d')}"
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

      # Parse events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        event_nodes = doc.css(".event-card").reject { |n| n.css("> .event-card").any? }
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
        time = extract_time(node)
        venue = extract_venue(node)
        price = extract_price(node)
        url = extract_url(node)
        description = extract_description(node)

        price_cents = price ? normalize_price(price) : nil

        event_hash = {
          title: title,
          date: date || Date.today,
          time: time,
          venue: venue,
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
        title_el = node.at_css(".ds-listing-event-title-text")
        return title_el.text.strip if title_el

        # Fallback: any title-like anchor
        title_el = node.at_css(".ds-listing-event-title")
        return title_el.text.strip if title_el

        ""
      end

      # Extract the event date from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(node)
        # Try meta itemprop="startDate"
        meta_el = node.at_css('meta[itemprop="startDate"]')
        return normalize_date(meta_el["datetime"]) if meta_el

        # Try the URL path: /events/YYYY/MM/DD/...
        permalink = node["data-permalink"]
        if permalink && permalink =~ %r{/events/(\d{4})/(\d{2})/(\d{2})/}
          return Date.new($1.to_i, $2.to_i, $3.to_i)
        end

        nil
      end

      # Extract the event time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_time(node)
        time_el = node.at_css(".ds-event-time")
        return nil unless time_el

        text = time_el.text.strip.gsub(/\s*\(doors\)\s*/i, "").strip
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
        venue_el = node.at_css(".ds-venue-name a span[itemprop='name']")
        return venue_el.text.strip if venue_el

        # Fallback: any venue name span
        venue_el = node.at_css(".ds-venue-name a")
        return venue_el.text.strip if venue_el

        ""
      end

      # Extract the price from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        # Check for "Free" in soldout banner
        free_el = node.at_css(".ds-listing-soldout span")
        if free_el
          text = free_el.text.strip
          return "Free" if text.downcase == "free"
        end

        nil
      end

      # Extract the event URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        # Try the main event anchor
        link_el = node.at_css(".ds-listing-event-title")
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
        time_el = node.at_css(".ds-event-time")
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
        byline_el = node.at_css(".ds-byline")
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
    end
  end
end
