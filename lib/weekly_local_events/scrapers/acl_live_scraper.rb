# frozen_string_literal: true

require "json"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for acllive.com (Austin City Limits Live at The Moody Theater).
    #
    # Fetches the events page and individual event pages to extract
    # concert listings. The site is a JavaScript SPA, so we parse
    # the text content from the HTTP response body.
    #
    # Events page: https://www.acllive.com/events
    # Individual event pages: https://www.acllive.com/event/YYYY-MM-DD-title-at-HH-PM
    #
    # HTML structure (from web extraction):
    #   <h3>Event Title</h3>
    #   <span class="event-date">Nov 27, 2026</span>
    #   <span class="event-venue">ACL Live at The Moody Theater</span>
    #   <a href="/event/2026-11-27-title-at-8-pm">Get Tickets</a>
    class ACLLiveScraper < BaseScraper
      BASE_URL = "https://www.acllive.com".freeze
      EVENTS_PATH = "/events".freeze
      VENUE_NAME = "ACL Live at The Moody Theater".freeze
      EVENTS_PER_PAGE = 12
      MAX_PAGES = 10
      AJAX_QUERY = "category=0&venue=0&team=0&exclude=&per_page=12&came_from_page=event-list-page".freeze
      VENUE_NAMES = {
        "2" => "ACL Live at The Moody Theater",
        "3" => "ACL Live at 3TEN",
        "4" => "Austin PBS Tapings",
      }.freeze
      VENUE_CATEGORIES = {
        "2" => "ACL Live",
        "3" => "3TEN ACL Live",
        "4" => "Austin PBS Tapings",
      }.freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "acl_live"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        cfg[:rate_limit_delay] = 3.0
        cfg[:date_range_days] = 30
        super(cfg)
      end

      # Fetch all events, following the site's AJAX "load more" pagination.
      #
      # @return [Array<Event>]
      def events
        page = fetch_events_page
        return [] unless page

        collected = parse_response(page)
        seen = {}
        collected.each { |event| remember_event(event, seen) }
        offset = EVENTS_PER_PAGE

        MAX_PAGES.times do
          fragment = fetch_ajax_page(offset)
          break if fragment.nil? || fragment.strip.empty?

          batch = parse_response(fragment)
          break if batch.empty?

          batch.each do |event|
            collected << event if remember_event(event, seen)
          end

          sleep(rate_limit_delay)
          offset += EVENTS_PER_PAGE
        end

        collected
      end

      # Parse an HTML document into Event instances.
      #
      # @param html [String, Nokogiri::HTML::Document] the HTML to parse
      # @param fetch_details [Boolean] whether to fetch event page details
      # @return [Array<Event>]
      def parse_response(html, fetch_details: false)
        return [] if html.nil?
        doc = html.is_a?(String) ? parse_html(html) : html
        events_from_doc(doc, fetch_details: fetch_details)
      end

      # Parse the JSON-wrapped HTML fragment returned by the AJAX endpoint.
      #
      # @param body [String] raw JSON response body
      # @return [Array<Event>]
      def parse_ajax_response(body)
        return [] if body.nil? || body.to_s.strip.empty?

        payload = JSON.parse(body.to_s)
        return [] unless payload.is_a?(String)

        parse_response(payload)
      rescue JSON::ParserError => e
        log_warn "Invalid AJAX payload: #{e.message}"
        []
      end

      private

      # Parse events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @param fetch_details [Boolean] whether to fetch event page details
      # @return [Array<Event>]
      def events_from_doc(doc, fetch_details: false)
        # Current live markup: div.eventItem.entry cards with data-venue attributes.
        events = events_from_live_cards(doc, fetch_details: fetch_details)
        return events unless events.empty?

        # Legacy structured markup (kept for older fixtures/integrations).
        events = events_from_css(doc, fetch_details: fetch_details)
        return events unless events.empty?

        # Fallback: parse text content for SPA-style pages
        parse_events_from_text(doc.text)
      end

      # Parse events using Nokogiri CSS selectors.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @param fetch_details [Boolean] whether to fetch event page details
      # @return [Array<Event>]
      def events_from_css(doc, fetch_details: false)
        events = []

        # Find date elements (e.g., <span class="event-date"> or similar)
        date_elements = doc.css("span.event-date, span.date, h1.event-date, .event-date")

        # If no specific date elements found, look for any date-like text
        if date_elements.empty?
          # Try to find date patterns in heading or paragraph tags
          doc.css("p, h2, h3, h4").each do |el|
            text = el.text.strip
            if text =~ /\A(\w{3,4}\s+\d{1,2},?\s+\d{4})\z/
              date_elements << el
              date_elements.last[:date_str] = $1
            end
          end
        end

        # Group events by date elements
        date_elements.each do |date_el|
          # Extract date string from the element text
          date_str = date_el.text.strip
          date_str = nil if date_str.empty?

          # Find the associated event card (next sibling or parent)
          card = find_event_card(date_el)
          next unless card

          event = parse_event_node(card, date_str, fetch_details: fetch_details)
          events << event if event
        end

        events
      end

      # Find the event card associated with a date element.
      #
      # @param date_el [Nokogiri::XML::Element]
      # @return [Nokogiri::XML::Element, nil]
      def find_event_card(date_el)
        # Try parent
        parent = date_el.parent
        return parent if parent.is_a?(Nokogiri::XML::Element)

        # Try next sibling
        sibling = date_el.next_sibling
        sibling = sibling.next_sibling while sibling && !sibling.is_a?(Nokogiri::XML::Element)
        sibling
      end

      # Parse a single event card node into an Event.
      #
      # @param node [Nokogiri::XML::Element]
      # @param date_str [String, nil] the date string
      # @param fetch_details [Boolean] whether to fetch event page details
      # @return [Event, nil]
      def parse_event_node(node, date_str, fetch_details: false)
        title = extract_title(node)
        return nil if title.to_s.strip.empty?

        venue = extract_venue(node)
        date = date_str ? normalize_date(date_str) : nil
        time = extract_time(node)
        url = extract_url(node)

        description = nil
        price = nil
        if fetch_details && url
          description = fetch_event_description(url)
          price = fetch_event_price(url)
        end

        Event.from_hash({
          title: title,
          date: date || Date.today,
          time: time,
          venue: venue,
          price: price,
          url: url,
          source: "acl_live",
          description: description,
        })
      rescue EventParseError
        nil
      end

      # Extract the event title from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String]
      def extract_title(node)
        # Look for h3 tag
        h3 = node.at_css("h3")
        return h3.text.strip if h3

        # Look for the main title element
        title = node.at_css("h1, h2, .event-title, .title")
        return title.text.strip if title

        # Fallback: look for text that looks like a title
        node.text.lines.map(&:strip).reject(&:empty?).each do |line|
          next if line =~ /\A\w{3,4}\s+\d{1,2},?\s+\d{4}\z/
          next if line =~ /\AACL Live at/i
          next if line =~ /\A(3TEN|Address|Contact|Get Tickets|Showtimes)\b/i
          next if line =~ /\d{1,2}:\d{2}\s*(?:AM|PM)/i
          next if line =~ /\A\d{4}-\d{2}-\d{2}-/
          return line if line.length > 3
        end

        ""
      end

      # Extract the venue from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Venue, nil]
      def extract_venue(node)
        # Look for venue in h4 or span tags
        venue_el = node.at_css("h4, .venue, .event-venue, span.event-venue")
        if venue_el
          name = venue_el.text.strip
          return Venue.from_hash(name: name) if name
        end

        # Look for "ACL Live at" pattern
        text = node.text
        if text =~ /ACL Live at (The Moody Theater|3TEN)/
          return Venue.from_hash(name: "ACL Live at #{$1}")
        end

        # Default venue
        Venue.from_hash(name: VENUE_NAME)
      end

      # Extract the event time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_time(node)
        # Look for time in span or time tags
        time_el = node.at_css("span.event-time, .time, .event-time, time")
        return nil unless time_el

        text = time_el.text.strip
        return nil if text.empty?

        # Try to parse the time
        if text =~ /(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))/i
          return normalize_time($1.strip)
        end

        # Look for "at 8 PM" pattern in the node text
        if node.text =~ /at\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm))/i
          return normalize_time($1.strip)
        end

        nil
      end

      # Extract the event URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        # Look for "Get Tickets" or event link
        link_el = node.at_css("a[href*='/event/'], .get-tickets, a.get-tickets")
        return nil unless link_el

        href = link_el["href"]
        return nil unless href

        # Resolve relative URLs
        if href.start_with?("/")
          "#{BASE_URL}#{href}"
        elsif href.start_with?("http://", "https://")
          href
        else
          nil
        end
      end

      # Parse event cards from the page text content (SPA fallback).
      #
      # @param text [String] the page text content
      # @return [Array<Event>]
      def parse_events_from_text(text)
        events = []

        # ACL Live events page structure (from web extraction):
        # Each event block has:
        #   - Date (e.g., "Nov 27, 2026")
        #   - Venue (e.g., "ACL Live at The Moody Theater" or "ACL Live at 3TEN")
        #   - Title (h3 tag text)
        #   - Link to event page (href="/event/...")

        # Split text into event blocks by date markers
        date_pattern = /(\w{3,4}\s+\d{1,2},?\s+\d{4})/

        # Find all date positions
        positions = []
        text.each_line do |line|
          if match = line.match(date_pattern)
            positions << { line: line.strip, date_str: match[1], index: text.index(match[1]) }
          end
        end

        return events if positions.empty?

        # Parse each event block
        positions.each_with_index do |pos, i|
          start_idx = pos[:index]
          end_idx = i < positions.length - 1 ? positions[i + 1][:index] : text.length
          block_text = text[start_idx...end_idx]

          next unless block_text

          event = parse_event_block_from_text(block_text, pos[:date_str])
          events << event if event
        end

        events
      end

      # Parse a single event block from text content.
      #
      # @param block_text [String] text of the event block
      # @param date_str [String] the date string for this event
      # @return [Event, nil]
      def parse_event_block_from_text(block_text, date_str)
        title = extract_title_from_text(block_text)
        return nil if title.to_s.strip.empty?

        venue = extract_venue_from_text(block_text)
        date = normalize_date(date_str)
        time = extract_time_from_text(block_text)

        # URL is not available in text-only extraction
        # (it's inside <a href="..."> tags which get stripped)
        Event.from_hash({
          title: title,
          date: date || Date.today,
          time: time,
          venue: venue,
          url: nil,
          source: "acl_live",
        })
      rescue EventParseError
        nil
      end

      # Extract the event title from text content.
      #
      # @param text [String]
      # @return [String]
      def extract_title_from_text(text)
        lines = text.lines.map(&:strip).reject(&:empty?)

        lines.each do |line|
          next if line =~ /\A\w{3,4}\s+\d{1,2},?\s+\d{4}\z/  # date pattern
          next if line =~ /\AACL Live at/i  # venue pattern
          next if line =~ /\A(3TEN|Address|Contact|Get Tickets|Showtimes)\b/i
          next if line =~ /\d{1,2}:\d{2}\s*(?:AM|PM)/i  # time pattern
          next if line =~ /\A\d{4}-\d{2}-\d{2}-/  # URL-like pattern
          next if line.length < 3  # too short to be a title
          return line
        end

        ""
      end

      # Extract the venue from text content.
      #
      # @param text [String]
      # @return [Venue, nil]
      def extract_venue_from_text(text)
        if text =~ /ACL Live at (The Moody Theater|3TEN)/
          return Venue.from_hash(name: "ACL Live at #{$1}")
        end

        Venue.from_hash(name: VENUE_NAME)
      end

      # Extract the event time from text content.
      #
      # @param text [String]
      # @return [String, nil]
      def extract_time_from_text(text)
        # Look for time patterns in the text
        if text =~ /(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))/i
          time_str = $1.strip
          return normalize_time(time_str)
        end

        # Look for "at 8 PM" pattern
        if text =~ /at\s+(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm))/i
          time_str = $1.strip
          return normalize_time(time_str)
        end

        nil
      end

      # Fetch and parse the description from an individual event page.
      #
      # @param url [String] the event page URL
      # @return [String, nil]
      def fetch_event_description(url)
        return nil unless url

        begin
          html = fetch(url)
          doc = html.is_a?(String) ? parse_html(html) : html
          extract_description_from_page(doc)
        rescue StandardError
          nil
        end
      end

      # Extract description from an individual event page.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [String, nil]
      def extract_description_from_page(doc)
        paragraphs = doc.css("p")
        paragraphs.each do |p|
          text = p.text.strip
          next if text.empty?
          next if text =~ /\A(3TEN|Address|Contact|Get Tickets|Showtimes|On Sale|Get Tickets|Directions|Parking|Seating Chart)\b/i
          return text if text.length > 20
        end

        nil
      end

      # Fetch and parse the price from an individual event page.
      #
      # @param url [String] the event page URL
      # @return [String, nil]
      def fetch_event_price(url)
        return nil unless url

        begin
          html = fetch(url)
          doc = html.is_a?(String) ? parse_html(html) : html
          extract_price_from_page(doc)
        rescue StandardError
          nil
        end
      end

      # Extract price from an individual event page.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [String, nil]
      def extract_price_from_page(doc)
        price_patterns = [
          /(Tickets?\s+)?from\s+\$[\d.]+/i,
          /\$[\d.]+\s*-\s*\$[\d.]+/i,
          /\$[\d.]+/,
        ]

        doc.text.each_line do |line|
          text = line.strip
          price_patterns.each do |pattern|
            return $&.strip if text =~ pattern
          end
        end

        nil
      end

      # Fetch the first events page, logging and swallowing transport errors.
      #
      # @return [Nokogiri::HTML::Document, nil]
      def fetch_events_page
        url = build_url(EVENTS_PATH)
        fetch(url)
      rescue StandardError => e
        log_error "Error scraping #{url}: #{e.class} - #{e.message}"
        nil
      end

      # Fetch one AJAX page. Non-2xx responses and malformed JSON stop
      # pagination gracefully instead of raising.
      def fetch_ajax_page(offset)
        url = ajax_url(offset)
        response = http_get(
          url,
          "Accept" => "application/json",
          "X-Requested-With" => "XMLHttpRequest",
        )
        return nil unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body.to_s)
        payload.is_a?(String) ? payload : ""
      rescue JSON::ParserError => e
        log_warn "Invalid AJAX response from #{url}: #{e.message}"
        nil
      rescue StandardError => e
        log_warn "AJAX page #{offset} failed: #{e.class} - #{e.message}"
        nil
      end

      def ajax_url(offset)
        "#{BASE_URL}/events/events_ajax/#{offset}?#{AJAX_QUERY}"
      end

      # The same show can reappear when the listing changes between requests.
      def remember_event(event, seen)
        key = if event.url.to_s.empty?
                [event.title, event.date, event.venue&.name]
              else
                event.url
              end
        return false if seen.key?(key)

        seen[key] = true
        true
      end

      # Parse the server-rendered cards used by the live /events page and the
      # AJAX fragments. Verified against the 2026-11-27 capture.
      def events_from_live_cards(doc, fetch_details: false)
        doc.css("div.eventItem.entry").filter_map do |card|
          # The search overlay ships a Vue <template> carrying the same classes.
          next if card.ancestors.any? { |ancestor| ancestor.name == "template" }

          parse_live_card(card, fetch_details: fetch_details)
        end
      end

      def parse_live_card(card, fetch_details: false)
        title = card.at_css("h3.title a")&.text.to_s.strip
        url = live_url(card)
        return nil if title.to_s.empty? || url.empty?

        date = live_date(card)
        return nil unless date

        description = nil
        price = nil
        if fetch_details
          description = fetch_event_description(url)
          price = fetch_event_price(url)
        end

        Event.from_hash({
          title: title,
          date: date,
          time: time_from_slug(url),
          venue: live_venue(card),
          price: price,
          url: url,
          source: "acl_live",
          category: VENUE_CATEGORIES[card["data-venue"].to_s],
          description: description,
        })
      rescue EventParseError
        nil
      end

      def live_url(card)
        href = card.at_css("h3.title a[href]")&.[]("href").to_s
        return "" if href.empty? || href.start_with?("{{")

        href.start_with?("/") ? "#{BASE_URL}#{href}" : href
      end

      def live_date(card)
        raw = card.at_css(".date .m-date__singleDate")&.text.to_s.gsub(/\s+/, " ").strip
        slug_date = live_url(card)[%r{/event/(\d{4}-\d{2}-\d{2})-}, 1].to_s
        normalize_date(raw) || normalize_date(slug_date)
      end

      def live_venue(card)
        name = card.at_css(".info .location")&.text.to_s.gsub(/\s+/, " ").strip
        name = VENUE_NAMES[card["data-venue"].to_s].to_s if name.empty? || name.start_with?("{{")
        Venue.from_hash(name: name.empty? ? VENUE_NAME : name)
      end

      # ACL Live encodes the start time in the canonical URL slug, e.g.
      # /event/2026-12-06-echos-at-7-30-pm -> 19:30.
      def time_from_slug(url)
        match = url.to_s.match(/at-(\d{1,2})(?:-(\d{2}))?-(am|pm)\z/i)
        return nil unless match

        hour = match[1].to_i
        minutes = match[2].to_i
        period = match[3].upcase
        hour = 0 if hour == 12 && period == "AM"
        hour += 12 if period == "PM" && hour != 12
        format("%02d:%02d", hour, minutes)
      end
    end
  end
end
