# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Scraper for Paramount Theatre Austin events.
    #
    # Scrapes the ticketing site at tickets.austintheatre.org/events/
    # which lists all events across venues: The Paramount Theatre,
    # The State Theatre, and Texas Spirit Theater.
    #
    # IMPORTANT: Do NOT confuse with paramounttheatre.org (Austin, MN).
    # The Austin, TX Paramount Theatre uses tickets.austintheatre.org
    # for its ticketing platform.
    #
    # HTML structure (tickets.austintheatre.org/events):
    #   <li data-tn-prod-season-no="14376" class="tn-prod-list-item">
    #     <h4 class="tn-prod-list-item__property tn-prod-list-item__property--heading">
    #       <a href="https://tickets.austintheatre.org/14376">BLACK FRIDAY TEXAS SHOWDOWN</a>
    #     </h4>
    #     <ul class="list-unstyled tn-prod-list-item__property tn-prod-list-item__property--perf-list">
    #       <li class="tn-prod-list-item__perf-list-item" data-tn-performance-no="14377">
    #         <a href="https://tickets.austintheatre.org/14376/14377" class="tn-prod-list-item__perf-anchor">
    #           <span class="tn-prod-list-item__perf-date">Friday, November 27, 2026</span>
    #           <span class="tn-prod-list-item__perf-time">6:30PM</span>
    #           <span class="tn-performance-title">Black Friday Texas Showdown</span>
    #           <span class="tn-prod-list-item__perf-action">Purchase</span>
    #         </a>
    #       </li>
    #     </ul>
    #     <div class="tn-prod-list-item__property--img-container">
    #       <a href="https://tickets.austintheatre.org/14376">
    #         <img alt="" src="https://paramount-theatre.s3.us-east-2.amazonaws.com/...">
    #       </a>
    #     </div>
    #   </li>
    #
    # Rate limit: ~10 requests/minute recommended
    class ParamountAustinScraper < BaseScraper
      BASE_URL = "https://tickets.austintheatre.org".freeze
      EVENTS_PATH = "/events".freeze
      VENUE_NAME = "Paramount Theatre (Austin, TX)".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "paramount_austin"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        cfg[:max_retries] = cfg[:max_retries] || 3
        cfg[:rate_limit_delay] = cfg[:rate_limit_delay] || 6.0
        super(cfg)
      end

      # Fetch all events for the configured date range.
      #
      # @return [Array<Event>]
      def events
        scrape_page(EVENTS_PATH)
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

      # Parse all events from a Nokogiri document.
      #
      # @param doc [Nokogiri::HTML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        doc.css("li.tn-prod-list-item").flat_map do |node|
          parse_event_node(node) || []
        end
      end

      # Parse a single event listing node into an Event.
      #
      # @param node [Nokogiri::XML::Element]
      # @return [Event, nil]
      def parse_event_node(node)
        # Extract the product ID from the heading link
        heading_link = node.at_css(".tn-prod-list-item__property--heading a")
        return nil unless heading_link

        product_id = extract_product_id(heading_link["href"])
        return nil if product_id.nil?

        # Parse all performances under this event
        performances = node.css("li.tn-prod-list-item__perf-list-item")
        return nil if performances.empty?

        performances.map do |perf_node|
          parse_performance(perf_node, product_id, heading_link.text.strip)
        end
      end

      # Parse a single performance node into an Event.
      #
      # @param perf_node [Nokogiri::XML::Element]
      # @param product_id [String] the parent event product ID
      # @param title [String] the event title from the parent
      # @return [Event, nil]
      def parse_performance(perf_node, product_id, title)
        anchor = perf_node.at_css(".tn-prod-list-item__perf-anchor")
        return nil unless anchor

        perf_date = perf_node.at_css(".tn-prod-list-item__perf-date")
        perf_time = perf_node.at_css(".tn-prod-list-item__perf-time")
        perf_title = perf_node.at_css(".tn-performance-title")

        date = normalize_date(perf_date&.text&.strip) if perf_date
        time = normalize_time(perf_time&.text&.strip) if perf_time

        # Use the performance title if available, otherwise fall back to parent title
        event_title = perf_title&.text&.strip || title

        # Build the ticket URL (product/performance format)
        perf_id = perf_node["data-tn-performance-no"]
        ticket_url = if perf_id
          "#{BASE_URL}/#{product_id}/#{perf_id}"
        else
          "#{BASE_URL}/#{product_id}"
        end

        # Build the event detail URL
        event_url = "#{BASE_URL}/#{product_id}"

        venue = Venue.from_hash({ name: VENUE_NAME })

        # Extract image URL if available
        img_node = perf_node.at_css("img") ||
                   perf_node.ancestors("li.tn-prod-list-item").first&.at_css(".tn-prod-list-item__property--img-container img")
        image_url = img_node&.at_css("img")&.[]("src")

        event_hash = {
          title: event_title,
          date: date,
          time: time,
          venue: venue,
          url: ticket_url,
          source: "paramount_austin",
          description: extract_description(perf_node, anchor),
          image_url: image_url,
        }

        Event.from_hash(event_hash)
      rescue EventParseError
        nil
      end

      # Extract description from a performance node.
      #
      # @param perf_node [Nokogiri::XML::Element]
      # @param anchor [Nokogiri::XML::Element] the anchor element
      # @return [String, nil]
      def extract_description(perf_node, anchor)
        # Try to get description from the anchor's text content
        # (sometimes descriptions are embedded in the link text)
        return nil
      end

      # Extract the product ID from a URL like "https://tickets.austintheatre.org/14376".
      #
      # @param href [String, nil]
      # @return [String, nil]
      def extract_product_id(href)
        return nil unless href

        href = href.strip
        return nil unless href.include?(BASE_URL)

        # Match the product ID pattern: /{digits} or /{digits}/{digits}
        match = href.match(%r{#{BASE_URL}/(\d+)(?:/\d+)?})
        match ? match[1] : nil
      end
    end
  end
end
