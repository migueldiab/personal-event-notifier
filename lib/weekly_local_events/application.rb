# frozen_string_literal: true

require "active_support/all"

module WeeklyLocalEvents
  # Main orchestrator for the WeeklyLocalEvents pipeline.
  #
  # Coordinates the full flow: load config → instantiate scrapers → run them
  # → collect events → aggregate → notify → return a Summary.
  #
  # Handles scraper failures gracefully: logs the error and continues with
  # the next scraper.
  #
  # Usage:
  #   app = Application.new
  #   summary = app.run
  #   puts summary
  class Application
    attr_reader :config, :scraper_registry, :notifier, :aggregator

    def initialize(config = Config.new)
      @config = config
      @scraper_registry = ScraperRegistry.new(config)
      @notifier = Notifier.new(config)
      @aggregator = Aggregator.new(config)
    end

    # Run the full pipeline: scrape → aggregate → notify → Summary.
    #
    # @param dry_run [Boolean] if true, skip notification step (takes precedence)
    # @param notify [Boolean] if true, send the aggregated events to the notifier
    # @return [Summary] with total event count and per-source breakdown.
    def run(dry_run: false, notify: false)
      log_info "Starting Weekly Local Events run at #{Time.now}"
      events = scrape_all
      aggregated = aggregate(events)
      result = notification_result(aggregated, dry_run: dry_run, notify: notify)
      log_info "Run complete. Found #{aggregated.size} events, notification #{result.to_s.downcase}."
      Summary.new(total: aggregated.size, sources: aggregated.map(&:source).tally, events: aggregated)
    end

    # Run a single scraper and return its events.
    #
    # @param scraper [BaseScraper] the scraper to run
    # @return [Array<Event>]
    # @raise [StandardError] if scraper is nil or not a BaseScraper
    def run_scraper(scraper)
      unless scraper.is_a?(BaseScraper)
        log_error "Invalid scraper: expected BaseScraper, got #{scraper.class}"
        return []
      end

      log_info "Running scraper: #{scraper.name}"
      scraper.scrape
    rescue StandardError => e
      log_error "Scraper #{scraper.name} failed: #{e.message}"
      []
    end

    # Run all registered scrapers and return all collected events.
    #
    # @return [Array<Event>]
    def run_all_scrapers
      scrape_all
    end

    # Delegate to the aggregator to deduplicate and sort events.
    #
    # @param events [Array<Event>]
    # @return [Array<Event>]
    def aggregate(events)
      aggregator.aggregate(events)
    end

    # Delegate to the notifier to send aggregated events.
    #
    # @param events [Array<Event>]
    # @return [NotificationResult]
    def notify(events)
      notifier.notify(events)
      NotificationResult.new(success: true, events_sent: events.size)
    rescue StandardError => e
      log_error "Notification failed: #{e.message}"
      NotificationResult.new(success: false, events_sent: 0, error: e.message)
    end

    private

    # Decide the notification outcome. `dry_run` always wins so an explicit
    # --notify can never cause an accidental send during a dry run.
    #
    # @return [NotificationResult]
    def notification_result(events, dry_run:, notify:)
      return NotificationResult.new(success: true, events_sent: 0, dry_run: true) if dry_run
      return notify(events) if notify

      NotificationResult.new(success: true, events_sent: 0)
    end

    # Scrape every active source once and return all collected events.
    #
    # @return [Array<Event>]
    def scrape_all
      scraper_registry.active.flat_map { |scraper| run_scraper(scraper) }
    end

    def log_info(msg)
      config.logger&.info(msg)
    end

    def log_error(msg)
      config.logger&.error(msg)
    end
  end
end
