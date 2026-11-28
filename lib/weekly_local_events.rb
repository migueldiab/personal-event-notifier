# frozen_string_literal: true

require "weekly_local_events/version"
require "weekly_local_events/application"
require "weekly_local_events/base_scraper"
require "weekly_local_events/rate_limiter"
require "weekly_local_events/headless_browser_fetcher"
require "weekly_local_events/anti_bot_fetcher"
require "weekly_local_events/archived_snapshot_fetcher"
require "weekly_local_events/event"
require "weekly_local_events/venue"
require "weekly_local_events/scrapers/stubbss_scraper"
require "weekly_local_events/scrapers/acl_live_scraper"
require "weekly_local_events/scrapers/acl_live_pdf_scraper"
require "weekly_local_events/scrapers/austin_chronicle_scraper"
require "weekly_local_events/scrapers/austin_chronicle_rss_scraper"
require "weekly_local_events/scrapers/austin_chronicle_combined_scraper"
require "weekly_local_events/scrapers/do512_scraper"
require "weekly_local_events/scrapers/community_impact_scraper"
require "weekly_local_events/scrapers/eventbrite_austin_scraper"
require "weekly_local_events/scrapers/paramount_austin_scraper"
require "weekly_local_events/scrapers/visit_cedar_park_scraper"
require "weekly_local_events/scrapers/cedar_park_rss_scraper"
require "weekly_local_events/scraper_registry"
require "weekly_local_events/notifier"
require "weekly_local_events/aggregator"
require "weekly_local_events/config"
require "weekly_local_events/summary"
require "weekly_local_events/notification_result"

module WeeklyLocalEvents
  class Error < StandardError; end
  class ScraperError < Error; end
  class NotFoundError < ScraperError; end
  class ParseError < ScraperError; end
  class RateLimitError < ScraperError; end

  class << self
    def config
      @config ||= Config.new
    end

    def scraper_registry
      @scraper_registry ||= ScraperRegistry.new
    end

    def notifier
      @notifier ||= Notifier.new(config)
    end

    def aggregator
      @aggregator ||= Aggregator.new
    end

    def run
      Application.new(config).run
    end
  end
end
