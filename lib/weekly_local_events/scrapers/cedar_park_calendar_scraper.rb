# frozen_string_literal: true

require "date"
require "nokogiri"
require "time"
require "tzinfo"
require "uri"
require "weekly_local_events/archived_snapshot_fetcher"
require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"

module WeeklyLocalEvents
  module Scrapers
    # Parses the CivicEngage month grid from a validated Wayback snapshot.
    #
    # This is the historical-coverage fallback only: the live calendar HTML is
    # Cloudflare-blocked, and the primary live route is CedarParkRssScraper.
    # Multi-day events repeat under one EID, so parsing deduplicates on EID.
    # startDate values are naive America/Chicago wall-clock times.
    #
    # Recon: docs/cedar_park_recon.md
    class CedarParkCalendarScraper < BaseScraper
      SOURCE_NAME = "cedar_park_calendar".freeze
      BASE_URL = "https://www.cedarparktexas.gov".freeze
      CALENDAR_URL = "#{BASE_URL}/calendar.aspx".freeze
      TIMEZONE = TZInfo::Timezone.get("America/Chicago")
      EVENT_SELECTOR = 'div[itemscope][itemtype="http://schema.org/Event"]'.freeze

      # @param config [Config, Hash, nil] scraper configuration
      # @param fetcher [#fetch] injectable ArchivedSnapshotFetcher-compatible client
      def initialize(config = nil, fetcher: nil)
        cfg = config.is_a?(Hash) ? config.dup : {}
        cfg[:name] = SOURCE_NAME
        cfg[:base_url] = BASE_URL
        super(cfg)
        @fetcher = fetcher || ArchivedSnapshotFetcher.new
      end

      # Fetch a validated archived snapshot and parse its events.
      #
      # @return [Array<Event>] empty when no genuine snapshot is available
      def events
        snapshot = @fetcher.fetch(CALENDAR_URL)
        return [] unless snapshot

        parse_response(snapshot.body)
      rescue StandardError => e
        log_error "Archived calendar fetch failed: #{e.class} - #{e.message}"
        []
      end

      # Parse calendar HTML into one Event per EID, in document order.
      #
      # @param html [String, Nokogiri::HTML::Document, nil] raw HTML or document
      # @return [Array<Event>]
      def parse_response(html)
        return [] if html.nil? || html.to_s.strip.empty?
        return [] unless ArchivedSnapshotFetcher.valid_body?(html.to_s, original_url: CALENDAR_URL)

        doc = html.is_a?(Nokogiri::HTML::Document) ? html : Nokogiri::HTML5.parse(html.to_s, encoding: "UTF-8")
        seen = {}
        doc.css(EVENT_SELECTOR).filter_map do |node|
          event = parse_event(node)
          key = event && dedupe_key(event)
          next if key.nil? || seen.key?(key)

          seen[key] = true
          event
        end
      end

      # Stable dedupe key derived from the EID in the detail URL.
      #
      # @param event [Event, nil]
      # @return [String, nil]
      def dedupe_key(event)
        eid = event&.url.to_s[/[?&]EID=(\d+)/i, 1]
        "#{SOURCE_NAME}:#{eid}" if eid
      end

      # The fixture's naive start as written on the page (no offset).
      #
      # @param event [Event, nil]
      # @return [String, nil]
      def iso_start(event)
        return nil unless event&.date && event.begin_time

        "#{event.date.strftime('%Y-%m-%d')}T#{event.begin_time}:00"
      end

      # Resolve a naive wall-clock start to an instant in America/Chicago.
      #
      # @param event [Event, nil]
      # @return [Time, nil]
      def starts_at(event)
        return nil unless event&.date

        hour, minute = (event.begin_time || event.time || "00:00").to_s.split(":").map(&:to_i)
        TIMEZONE.local_time(event.date.year, event.date.month, event.date.day, hour, minute, 0)
      end

      private

      # @param node [Nokogiri::XML::Element] microdata event container
      # @return [Event, nil]
      def parse_event(node)
        item = node.ancestors.find { |ancestor| ancestor["class"].to_s.split.include?("monthItem") }
        href = item&.at_css('a.button[href*="EID="]')&.[]("href")
        title = node_text(node, 'span[itemprop="name"]')
        raw_start = node_text(node, 'span[itemprop="startDate"]')
        return nil if href.nil? || href.empty? || title.empty? || raw_start.empty?

        date, begin_time = parse_start(raw_start)
        return nil unless date

        url = absolute_link(href)
        eid = href[/[?&]EID=(\d+)/i, 1]
        tags = []
        tags << "eid:#{eid}" if eid

        Event.from_hash(
          title: title,
          date: date,
          time: begin_time,
          begin_time: begin_time,
          end_time: end_time(item),
          venue: parse_venue(node),
          description: node_text(node, 'p[itemprop="description"]'),
          price: nil,
          price_cents: nil,
          url: url,
          source: SOURCE_NAME,
          category: parse_category(item),
          tags: tags
        )
      rescue EventParseError, VenueParseError, ArgumentError
        nil
      end

      # @return [Array(Date, String)]
      def parse_start(raw_start)
        stamp = Time.strptime(raw_start, "%Y-%m-%dT%H:%M:%S")
        [Date.new(stamp.year, stamp.month, stamp.day), format("%02d:%02d", stamp.hour, stamp.min)]
      rescue ArgumentError
        [nil, nil]
      end

      # @return [String, nil] end time from the human-readable date line
      def end_time(item)
        date_line = item&.at_css(".subHeader .date")&.text.to_s
        range = date_line.split(",").last.to_s
        parts = range.split(/\s*(?:-|–|—)\s*/).map { |part| normalize_time(part.gsub(/[\s\u2009\u202f]+/, " ").strip) }
        parts.last unless parts.length < 2
      end

      # @return [String]
      def parse_category(item)
        label = item&.at_css("a > span.visuallyHidden")&.text.to_s
        label.sub(/\ACategory:\s*/, "").strip
      end

      # @return [Venue]
      def parse_venue(node)
        place = node.at_css('span[itemprop="location"]')
        Venue.new(
          name: node_text(place, 'span[itemprop="name"]'),
          address: node_text(place, 'span[itemprop="streetAddress"]'),
          city: node_text(place, 'span[itemprop="addressLocality"]'),
          state: node_text(place, 'span[itemprop="addressRegion"]'),
          zip: node_text(place, 'span[itemprop="postalCode"]')
        )
      end

      # @return [String]
      def node_text(parent, selector)
        parent ? parent.at_css(selector)&.text.to_s.strip : ""
      end

      # @return [String, nil]
      def absolute_link(href)
        return nil if href.to_s.empty?
        return href if href.match?(%r{\Ahttps?://})

        URI.join("#{BASE_URL}/", href).to_s
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
