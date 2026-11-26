# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # RSS fallback scraper for The Austin Chronicle.
    #
    # Fetches the main WordPress RSS feed and parses each <item> into an Event.
    # Since the RSS feed is a blog feed (not a dedicated events feed), it provides:
    #   - title, date, description, link, categories (mapped to tags)
    #   - NO venue, price, or time (these are nil)
    #
    # This is intended as a fallback when the HTML scraper fails or is blocked.
    #
    # RSS URL: https://www.austinchronicle.com/rss/chronic.xml
    #
    # Usage:
    #   scraper = AustinChronicleRSSScraper.new(config)
    #   events = scraper.events
    #
    class AustinChronicleRSSScraper < BaseScraper
      BASE_URL = "https://www.austinchronicle.com".freeze
      RSS_URL = "https://www.austinchronicle.com/rss/chronic.xml".freeze

      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "austin_chronicle_rss"
        cfg[:base_url] = BASE_URL
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        super(cfg)
      end

      # Fetch all RSS items for the configured date range.
      #
      # @return [Array<Event>]
      def events
        fetch_rss
      rescue NotFoundError, RateLimitError, ScraperError => e
        log_error "RSS fetch failed: #{e.class} - #{e.message}"
        []
      rescue StandardError => e
        log_error "RSS fetch unexpected error: #{e.class} - #{e.message}"
        []
      end

      # Parse an XML document into Event instances.
      #
      # @param xml [String, Nokogiri::XML::Document] the XML to parse
      # @return [Array<Event>]
      def parse_response(xml)
        return [] if xml.nil?
        doc = xml.is_a?(String) ? parse_xml(xml) : xml
        events_from_doc(doc)
      end

      private

      # Fetch the RSS feed XML and parse it.
      #
      # @return [Array<Event>]
      def fetch_rss
        xml = fetch(RSS_URL)
        parse_response(xml)
      end

      # Parse raw XML string into a Nokogiri XML document.
      #
      # @param body [String] raw XML
      # @return [Nokogiri::XML::Document]
      def parse_xml(body)
        require "nokogiri"
        Nokogiri::XML(body)
      rescue LoadError
        require "nokogiri"
        Nokogiri::XML(body)
      end

      # Namespace map for XPath queries on RSS documents.
      #
      # @return [Hash]
      NAMESPACES = {
        "dc" => "http://purl.org/dc/elements/1.1/",
        "content" => "http://purl.org/rss/1.0/modules/content/",
        "atom" => "http://www.w3.org/2005/Atom",
      }.freeze

      # Execute an XPath query with RSS namespace support.
      #
      # @param node [Nokogiri::XML::Node] the context node
      # @param xpath [String] the XPath expression
      # @return [Nokogiri::XML::NodeSet]
      def xpath(node, xpath)
        node.xpath(xpath, NAMESPACES)
      end

      # Parse RSS items from a Nokogiri document.
      #
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Event>]
      def events_from_doc(doc)
        items = doc.xpath("//item")
        items.map { |item| parse_rss_item(item) }.compact
      end

      # Parse a single RSS <item> into an Event.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [Event, nil]
      def parse_rss_item(item)
        title = extract_title(item)
        return nil if title.to_s.strip.empty?

        date = extract_date(item)
        description = extract_description(item)
        link = extract_link(item)
        categories = extract_categories(item)
        creator = extract_creator(item)

        # RSS feed does not contain venue or price information
        venue = nil
        price = nil

        event_hash = {
          title: title,
          date: date || Date.today,
          time: nil,
          venue: venue,
          price: price,
          price_cents: nil,
          url: link,
          source: "austin_chronicle_rss",
          description: description,
          category: categories.first,
          tags: categories,
        }

        Event.from_hash(event_hash)
      rescue EventParseError
        nil
      end

      # Extract the event title from an RSS item.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [String]
      def extract_title(item)
        title_el = item.at_xpath("title")
        return title_el.text.strip if title_el
        ""
      end

      # Extract the event date from an RSS item's pubDate.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [Date, nil]
      def extract_date(item)
        pubdate_el = item.at_xpath("pubDate")
        return nil unless pubdate_el

        date_text = pubdate_el.text.strip
        # RSS pubDate format: "Wed, 25 Nov 2026 19:48:52 +0000"
        begin
          return Date.parse(date_text)
        rescue ArgumentError, TypeError
          return nil
        end
      end

      # Extract the description (stripped of HTML tags).
      #
      # @param item [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_description(item)
        desc_el = item.at_xpath("description")
        return nil unless desc_el

        text = desc_el.text.strip
        # Strip HTML tags for clean text
        text.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end

      # Extract the item link.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_link(item)
        link_el = item.at_xpath("link")
        return nil unless link_el

        link = link_el.text.strip
        return nil if link.empty?
        return link if link.start_with?("http://", "https://")
        "#{BASE_URL}#{link}" if link.start_with?("/")
      end

      # Extract category tags from the item.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [Array<String>]
      def extract_categories(item)
        categories = []
        xpath(item, "category").each do |cat_el|
          text = cat_el.text.strip
          categories << text unless text.empty?
        end
        categories
      end

      # Extract the author/creator from the item.
      #
      # @param item [Nokogiri::XML::Element]
      # @return [String, nil]
      def extract_creator(item)
        creator_el = xpath(item, "dc:creator").first
        return nil unless creator_el
        creator_el.text.strip
      end
    end
  end
end
