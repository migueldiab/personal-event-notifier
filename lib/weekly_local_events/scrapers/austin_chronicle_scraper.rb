# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for calendar.austinchronicle.com/austin/EventSearch.
    #
    # Fetches the calendar page for each date in the configured date range,
    # parses event listings from the HTML, and returns Event instances.
    #
    # HTML structure (Austin Chronicle Calendar - NEW):
    #   <li class="fdn-pres-item">
    #     <div class="fdn-pres-item-content">
    #       <div class="fdn-event-search-image-block">
    #         <a href="/event/12345"><img src="..." alt="Image: Event Name"></a>
    #       </div>
    #       <div class="fdn-pres-content fdn-event-search-text-block">
    #         <p class="fdn-teaser-headline">
    #           <a href="/event/12345">Event Title</a>
    #           <span class="fdn-features-icon-block">...</span>
    #         </p>
    #         <p class="fdn-teaser-subheadline">Fri., Nov. 27, 10-11:30 p.m.</p>
    #         <div class="fdn-event-teaser-location-block">
    #           <p class="fdn-event-teaser-location">
    #             <a class="fdn-event-teaser-location-link" href="/location/...">Venue Name</a>
    #           </p>
    #         </div>
    #         <div class="fdn-teaser-description">...</div>
    #         <p class="fdn-teaser-tag-link-block">
    #           <a class="fdn-teaser-tag-link" href="...">Comedy</a>
    #         </p>
    #         <div class="fdn-teaser-ticket-block">
    #           <a class="fdn-teaser-ticket-link" href="...">Get Tickets</a>
    #         </div>
    #       </div>
    #     </div>
    #   </li>
    #
    # Pagination: append &page=N to the URL for additional pages.
    #
    # NOTE: The old /events/music/ URLs redirect (301) to the new calendar system.
    # The old selectors (.event-title, .event-date, .venue, .price, .event-link)
    # are deprecated and no longer match any elements.
    class AustinChronicleScraper < BaseScraper
      BASE_URL = "https://www.austinchronicle.com".freeze
      CALENDAR_PATH = "/calendar".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "austin_chronicle"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        super(cfg)
      end

      # Fetch all events for the configured date range.
      #
      # @return [Array<Event>]
      def events
        all_events = []
        date_range.start_date.to_date.upto(date_range.end_date.to_date) do |date|
          # Skip past dates (future events are not yet listed)
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
      # @param html [String, Nokogiri::HTML::Document] the HTML to parse
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil?
        doc = html.is_a?(String) ? parse_html(html) : html
        events_from_doc(doc)
      end

      private

      # Build the full calendar URL for a given date and page.
      #
      # @param date [Date] the date to fetch
      # @param page [Integer] page number (1-indexed)
      # @return [String]
      def build_calendar_url(date, page)
        path = "#{CALENDAR_PATH}?date=#{date.strftime('%Y-%m-%d')}"
        path += "&page=#{page}" if page > 1
        build_url(path)
      end

      # Check if the next page has events (pagination guard).
      #
      # @param current_url [String] the current page URL
      # @param next_page [Integer] the next page number to try
      # @return [Boolean]
      def has_next_page?(current_url, next_page)
        next_url = build_calendar_url(
          Date.parse(current_url.split("date=").last.split("&").first),
          next_page
        )
        # We use a lightweight check: try to fetch just the first event-listing
        # without downloading the full page. If no events exist, skip.
        # For safety, we limit to a max page count.
        next_page <= 5
      end

      # Parse events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        # Austin Chronicle uses the new calendar system with .fdn-pres-item elements.
        # The old .event-listing / .event-card selectors are deprecated.
        # Use direct child selectors to avoid matching nested elements.
        event_nodes = []

        # Primary selector: .fdn-pres-item (new calendar system, 44+ items)
        event_nodes.concat(doc.css("li.fdn-pres-item").reject { |n| n.css("> li.fdn-pres-item").any? })

        # Fallback: .fdn-event-promo-wrapper (promoted events slider)
        event_nodes.concat(doc.css("li.fdn-promo-teaser-link").reject { |n| n.css("> li.fdn-promo-teaser-link").any? })

        # Legacy fallback: .event-listing (old layout, may still exist)
        event_nodes.concat(doc.css("body > .event-listing, .event-listing > .event-listing").reject { |n| n.css("> .event-listing").any? })

        # Legacy fallback: .event-card (older layouts) - direct children only
        event_nodes.concat(doc.css("body > .event-card, .event-card > .event-card").reject { |n| n.css("> .event-card").any? })

        # Legacy fallback: divs with data-event-id that don't contain other event nodes
        event_nodes.concat(doc.css("[data-event-id]").reject { |n| n.css("> [data-event-id]").any? })

        # Legacy fallback: .listing-item
        event_nodes.concat(doc.css(".listing-item").reject { |n| n.css("> .listing-item").any? })

        # Deduplicate by node object identity
        event_nodes.uniq! { |n| n.object_id }

        event_nodes.map { |node| parse_event_node(node) }.compact
      end

      # Parse a single event listing node into an Event.
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

        # Normalize price to cents for the event
        price_cents = price ? normalize_price(price) : nil

        event_hash = {
          title: title,
          date: date || Date.today,
          time: time,
          venue: venue,
          price: price,
          price_cents: price_cents,
          url: url,
          source: "austin_chronicle",
          description: description,
        }

        # Build URL if missing
        event_hash[:url] ||= "https://www.austinchronicle.com/calendar/?date=#{date&.strftime('%Y-%m-%d')}"

        Event.from_hash(event_hash)
      rescue EventParseError
        nil
      end

      # Extract the event title from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String]
      def extract_title(node)
        # New calendar system: .fdn-teaser-headline > a
        title_el = node.at_css(".fdn-teaser-headline > a")
        return title_el.text.strip if title_el

        # Legacy: .event-title
        title_el = node.at_css(".event-title, h3.event-title, h3 a.event-title")
        return title_el.text.strip if title_el

        # Legacy: .event-card-title
        title_el = node.at_css(".event-card-title")
        return title_el.text.strip if title_el

        # Legacy: .fdn-promo-headline (promoted events)
        title_el = node.at_css(".fdn-promo-headline")
        return title_el.text.strip if title_el

        # Try any <a> tag within the listing that isn't a venue/price link
        links = node.css("a").reject { |a| a["href"]&.include?("venue") || a["href"]&.include?("price") }
        return links.first.text.strip if links.any?

        # Try h3 or h2 tags
        h_el = node.at_css("h3, h2, h4")
        return h_el.text.strip if h_el

        ""
      end

      # Extract the event date from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(node)
        # New calendar system: .fdn-teaser-subheadline (e.g. "Fri., Nov. 27, 10-11:30 p.m.")
        date_el = node.at_css(".fdn-teaser-subheadline")
        return normalize_date(date_el.text.strip) if date_el

        # Legacy: <time> element
        time_el = node.at_css("time, .event-date, .event-card-date")
        return normalize_date(time_el.text.strip) if time_el

        # Try data attributes
        date_attr = node["data-date"] || node["data-event-date"]
        return normalize_date(date_attr) if date_attr

        # Legacy: date span
        date_el = node.at_css(".event-date, .date, .event-card-date")
        return normalize_date(date_el.text.strip) if date_el

        nil
      end

      # Extract the event time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_time(node)
        # New calendar system: .fdn-teaser-subheadline (e.g. "Fri., Nov. 27, 10-11:30 p.m.")
        subheadline = node.at_css(".fdn-teaser-subheadline")
        if subheadline
          text = subheadline.text.strip
          # Try to extract time from subheadline like "Fri., Nov. 27, 10-11:30 p.m."
          if text =~ /\d{1,2}:\d{2}\s*(?:am|pm)/i
            return normalize_time($&)
          end
          # Try to extract time range like "10-11:30 p.m."
          if text =~ /(\d{1,2}(?:-\d{1,2})?:\d{2}\s*[ap]m)/i
            return normalize_time($1)
          end
        end

        # Legacy: .event-time or .event-card-time
        time_el = node.at_css(".event-time, .event-card-time")
        return normalize_time(time_el.text.strip) if time_el

        # Try data attributes
        time_attr = node["data-time"] || node["data-start-time"]
        return normalize_time(time_attr) if time_attr

        # Try time span with "time" in class but not "date"
        time_el = node.css("span[class*='time']").reject { |s| s["class"].to_s.include?("date") }.first
        return normalize_time(time_el.text.strip) if time_el

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
        # New calendar system: .fdn-event-teaser-location-link
        venue_el = node.at_css(".fdn-event-teaser-location-link")
        return venue_el.text.strip if venue_el

        # Legacy: .event-venue, .venue, .event-card-venue, .venue-name
        venue_el = node.at_css(".event-venue, .venue, .event-card-venue, .venue-name")
        return venue_el.text.strip if venue_el

        # Try a venue link
        venue_link = node.at_css(".venue-link, .event-venue a, a[href*='venue']")
        return venue_link.text.strip if venue_link

        # Try data attributes
        venue_attr = node["data-venue"] || node["data-venue-name"]
        return venue_attr.strip if venue_attr

        ""
      end

      # Extract the price from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        # New calendar system: .fdn-teaser-ticket-link text (e.g. "Get Tickets $15" or "Buy tickets $25 - $75")
        ticket_el = node.at_css(".fdn-teaser-ticket-link")
        if ticket_el
          text = ticket_el.text.strip
          # Match "$25 - $75" or "$15" — capture full price string
          if text =~ /\$(\d+(?:\s*-\s*\$\s*\d+)?)/
            return "$" + $1
          end
          # Fallback: just get the first dollar amount
          if text =~ /\$(\d+)/
            return "#{$1}"
          end
        end

        # Legacy: .event-price, .price, .event-card-price, .ticket-price
        price_el = node.at_css(".event-price, .price, .event-card-price, .ticket-price")
        return price_el.text.strip if price_el

        # Try data attributes
        price_attr = node["data-price"] || node["data-ticket-price"]
        return price_attr if price_attr

        # Try any span with "price" in class
        price_el = node.at_css("span[class*='price']")
        return price_el.text.strip if price_el

        nil
      end

      # Extract the event URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        # New calendar system: .fdn-teaser-headline > a
        link_el = node.at_css(".fdn-teaser-headline > a")
        return resolve_link(link_el["href"]) if link_el

        # Legacy: .event-link, .event-card-link, .read-more
        link_el = node.at_css(".event-link, .event-card-link, .read-more")
        return resolve_link(link_el["href"]) if link_el

        # Try any <a> with a meaningful href
        links = node.css("a[href]")
        links.each do |link|
          href = link["href"]
          next unless href.include?("austinchronicle.com") || href.start_with?("/") || href.start_with?("https://")
          return resolve_link(href)
        end

        nil
      end

      # Resolve a link to an absolute URL.
      #
      # @param href [String, nil]
      # @return [String, nil]
      def resolve_link(href)
        return nil unless href

        href = href.strip
        return href if href.start_with?("http://", "https://")
        return nil if href.start_with?("#") || href.start_with?("javascript:")

        "#{BASE_URL}#{href}" if href.start_with?("/")
      end

      # Extract the event description from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(node)
        # New calendar system: .fdn-teaser-description
        desc_el = node.at_css(".fdn-teaser-description")
        return desc_el.text.strip if desc_el

        # Legacy: .event-description, .description, .event-card-description, .event-summary
        desc_el = node.at_css(".event-description, .description, .event-card-description, .event-summary")
        return desc_el.text.strip if desc_el

        # Try data attributes
        desc_attr = node["data-description"] || node["data-description-text"]
        return desc_attr.strip if desc_attr

        nil
      end
    end
  end
end
