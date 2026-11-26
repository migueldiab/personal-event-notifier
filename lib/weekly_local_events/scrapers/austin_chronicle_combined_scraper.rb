# frozen_string_literal: true

require "weekly_local_events/base_scraper"
require "weekly_local_events/event"
require "weekly_local_events/venue"
require "weekly_local_events/scrapers/austin_chronicle_rss_scraper"

module WeeklyLocalEvents
  module Scrapers
    # Combined scraper for The Austin Chronicle that tries the HTML calendar
    # first, then falls back to the RSS feed if HTML scraping fails.
    #
    # This provides resilience: if the HTML structure changes or the site
    # is temporarily unavailable, the RSS feed serves as a reliable fallback.
    #
    # Usage:
    #   scraper = AustinChronicleCombinedScraper.new(config)
    #   events = scraper.scrape
    #
    class AustinChronicleCombinedScraper < BaseScraper
      # @param config [Config, Hash, nil] scraper configuration
      def initialize(config = nil)
        cfg = config.is_a?(Hash) ? config : {}
        cfg[:name] = "austin_chronicle_combined"
        cfg[:base_url] = "https://www.austinchronicle.com"
        cfg[:user_agent] = "WeeklyLocalEvents/#{VERSION} (https://github.com/madrax/weekly-local-events)"
        super(cfg)
      end

      # Scrape events: try HTML first, fall back to RSS.
      #
      # @return [Array<Event>]
      def scrape
        log_info "Trying HTML scraper for Austin Chronicle..."
        events = scrape_html

        if events.any?
          log_info "HTML scraper returned #{events.size} events."
          return events
        end

        log_warn "HTML scraper returned no events. Falling back to RSS..."
        scrape_rss
      end

      private

      # Scrape using the HTML calendar scraper.
      #
      # @return [Array<Event>]
      def scrape_html
        require "weekly_local_events/scrapers/austin_chronicle_scraper"
        html_scraper = Scrapers::AustinChronicleScraper.new(@config)
        result = html_scraper.scrape
        puts "[COMBINED DEBUG] HTML scraper returned #{result.size} events: #{result.map(&:title).inspect}"
        result
      rescue StandardError => e
        log_error "HTML scraper failed: #{e.class} - #{e.message}"
        []
      end

      # Scrape using the RSS fallback scraper.
      #
      # @return [Array<Event>]
      def scrape_rss
        rss_scraper = Scrapers::AustinChronicleRSSScraper.new(@config)
        rss_scraper.scrape
      rescue StandardError => e
        log_error "RSS fallback also failed: #{e.class} - #{e.message}"
        []
      end
    end
  end
end
