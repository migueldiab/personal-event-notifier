# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for eventbrite.com Austin events.
    #
    # Fetches the Austin events page for each date in the configured date range,
    # parses event listings from the HTML, and returns Event instances.
    #
    # HTML structure (Eventbrite Austin events page):
    #   <section class="discover-vertical-event-card">
    #     <div class="event-card event-card__vertical ...">
    #       <a class="event-card-link" href="https://www.eventbrite.com/e/...">
    #         <h3 class="... event-card__clamp-line--two">Event Title</h3>
    #       </a>
    #       <p class="... Typography_body-md-bold__10ijx">Sat, Dec 5 • 5:30 PM</p>
    #       <p class="... event-card__clamp-line--one">Venue Name</p>
    #       <div class="DiscoverVerticalEventCard-module__priceWrapper___usWo6">
    #         <!-- Price (JS-rendered, may be skeleton) -->
    #       </div>
    #     </div>
    #   </section>
    #
    # Structured data (JSON-LD) is also available in the page for descriptions.
    #
    # Pagination: Eventbrite uses "Load More" buttons for infinite scroll.
    # The "Load More" button has class "eds-btn--button eds-btn--neutral"
    # with text "Load more".
    class EventbriteAustinScraper < BaseScraper
      BASE_URL = "https://www.eventbrite.com".freeze
      EVENTS_PATH = "/d/tx--austin/events/".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "eventbrite_austin"
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

          events = scrape_page(build_events_url(date))
          all_events.concat(events)
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

      # Build the full events URL for a given date.
      #
      # @param date [Date] the date to fetch
      # @return [String]
      def build_events_url(date)
        "#{EVENTS_PATH}?date=#{date.strftime('%Y-%m-%d')}"
      end

      # Parse events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        event_nodes = doc.css("section.discover-vertical-event-card")
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
        category = extract_category(node)
        image_url = extract_image_url(node)

        price_cents = price ? normalize_price(price) : nil

        event_hash = {
          title: title,
          date: date || Date.today,
          time: time,
          venue: venue,
          price: price,
          price_cents: price_cents,
          url: url,
          source: "eventbrite_austin",
          description: description,
          image_url: image_url,
          category: category,
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
        title_el = node.at_css("h3.event-card__clamp-line--two")
        return title_el.text.strip if title_el

        # Fallback: any h3 within the card
        title_el = node.at_css("h3")
        return title_el.text.strip if title_el

        ""
      end

      # Extract the event date from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(node)
        # Try the date/time paragraph: "Sat, Dec 5 • 5:30 PM"
        date_time_el = node.at_css("p.Typography_body-md-bold__10ijx")
        return nil unless date_time_el

        text = date_time_el.text.strip
        # Extract date portion before the bullet separator
        date_str = text.split("•").first.strip
        normalize_date(date_str)
      end

      # Extract the event time from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_time(node)
        # Try the date/time paragraph: "Sat, Dec 5 • 5:30 PM"
        date_time_el = node.at_css("p.Typography_body-md-bold__10ijx")
        return nil unless date_time_el

        text = date_time_el.text.strip
        # Extract time portion after the bullet separator
        parts = text.split("•")
        return nil if parts.length < 2

        time_str = parts[1].strip
        normalize_time(time_str)
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
        venue_el = node.at_css("p.event-card__clamp-line--one")
        return venue_el.text.strip if venue_el

        # Fallback: any p with location-like text
        venue_el = node.at_css("p.Typography_body-md__10ijx")
        return venue_el.text.strip if venue_el

        ""
      end

      # Extract the price from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_price(node)
        # Eventbrite renders prices via JS, so they may not be in the initial HTML.
        # Check the price wrapper for actual text (not skeleton).
        price_el = node.at_css("div.DiscoverVerticalEventCard-module__priceWrapper___usWo6")
        return nil unless price_el

        # Skip if it's a loading skeleton
        return nil if price_el.at_css(".shimmer-effect")

        text = price_el.text.strip
        return nil if text.empty?

        text
      end

      # Extract the event URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_url(node)
        link_el = node.at_css("a.event-card-link")
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

      # Extract the event description from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(node)
        # Eventbrite doesn't include descriptions in the card HTML.
        # We could fetch the event page for details, but that's expensive.
        # Return nil for now.
        nil
      end

      # Extract the event category from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_category(node)
        card = node.at_css("div.event-card")
        return nil unless card

        category = card["data-event-category"]
        return nil unless category

        # Convert "food-and-drink" to "Food and drink"
        parts = category.split("-")
        parts.map.with_index { |part, i| i == 0 ? part.capitalize : part }.join(" ")
      end

      # Extract the event image URL from a node.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_image_url(node)
        img_el = node.at_css("img.event-card-image")
        return nil unless img_el

        src = img_el["src"]
        return nil unless src

        # Use the largest available image
        srcSet = img_el["srcSet"]
        if srcSet
          # Parse srcSet for the largest image
          largest = srcSet.split(",").map(&:strip).sort_by do |part|
            part.match(/\s*(\d+)w\s*$/)&.[](1)&.to_i || 0
          end.last
          return largest.split(/\s+/).first if largest
        end

        src
      end

      # Check if the page has a "Load More" button (infinite scroll).
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Boolean]
      def has_load_more?(doc)
        load_more = doc.at_css("button.eds-btn--button.eds-btn--neutral")
        return false unless load_more
        load_more.text.include?("Load more")
      end
    end
  end
end
