# frozen_string_literal: true

module WeeklyLocalEvents
  # Registry that manages all scraper instances.
  #
  # Provides a central store for scraper classes, auto-registration,
  # and methods to run single or all scrapers with proper error handling.
  #
  # Usage:
  #   registry = ScraperRegistry.new(config)
  #   registry.run_all          # → [Event, ...]
  #   registry.run("austin_chronicle")  # → [Event, ...]
  class ScraperRegistry
    # Hash[String, BaseScraper] - registry of registered scraper instances.
    attr_reader :scraper_classes

    # Array[String] - list of scraper names to run by default.
    DEFAULT_SCRAPERS = %w[
      austin_chronicle
      do512
      community_impact
      eventbrite_austin
      acl_live
      stubbss
      paramount_austin
    ].freeze

    # Map of scraper names to their class constants.
    KNOWN_SCRAPERS = {
      "austin_chronicle" => "WeeklyLocalEvents::Scrapers::AustinChronicleScraper",
      "do512"            => "WeeklyLocalEvents::Scrapers::Do512Scraper",
      "community_impact" => "WeeklyLocalEvents::Scrapers::CommunityImpactScraper",
      "eventbrite_austin" => "WeeklyLocalEvents::Scrapers::EventbriteAustinScraper",
      "acl_live"         => "WeeklyLocalEvents::Scrapers::ACLLiveScraper",
      "stubbss"          => "WeeklyLocalEvents::Scrapers::StubbssScraper",
      "paramount_austin" => "WeeklyLocalEvents::Scrapers::ParamountAustinScraper",
    }.freeze

    def initialize(config = nil)
      @config = config
      @scraper_classes = {}
      register_all
    end

    # Register a scraper class by name.
    #
    # @param name [String, Symbol] the scraper identifier
    # @param klass [Class] the scraper class (must be a subclass of BaseScraper)
    # @return [nil]
    # @raise [ArgumentError] if klass is not a subclass of BaseScraper
    def register(name, klass)
      unless klass.ancestors.include?(::WeeklyLocalEvents::BaseScraper)
        raise ArgumentError, "#{klass} is not a subclass of BaseScraper"
      end

      key = name.to_s
      @scraper_classes[key] = klass
    end

    # Auto-register all known scrapers from KNOWN_SCRAPERS.
    #
    # Only registers classes that exist (resolves NameError gracefully).
    #
    # @return [nil]
    def register_all
      KNOWN_SCRAPERS.each do |name, class_name|
        begin
          klass = Object.const_get(class_name)
          register(name, klass)
        rescue NameError
          # Scraper class not yet loaded or defined — skip silently.
          nil
        end
      end
    end

    # Retrieve a scraper instance by name.
    #
    # @param name [String, Symbol] the scraper identifier
    # @return [BaseScraper] a new instance of the scraper
    # @raise [NotFoundError] if the scraper is not registered
    def get(name)
      key = name.to_s
      klass = @scraper_classes[key]
      raise ::WeeklyLocalEvents::NotFoundError, "Scraper '#{name}' is not registered" unless klass

      klass.new(@config)
    end

    # Return all registered scraper instances.
    #
    # @return [Array<BaseScraper>]
    def all
      @scraper_classes.map do |name, klass|
        klass.new(@config)
      end
    end

    # Return only the scrapers enabled in config (config.sites / config.enabled_scrapers).
    #
    # @return [Array<BaseScraper>]
    def active
      enabled = enabled_scrapers
      return all if enabled.empty?

      all.select { |scraper| enabled.include?(scraper.name) }
    end

    # Run a single scraper by name and return its events.
    #
    # Handles errors gracefully: logs the error and returns an empty array
    # if the scraper fails.
    #
    # @param name [String, Symbol] the scraper identifier
    # @return [Array<Event>]
    # @raise [NotFoundError] if the scraper is not registered
    def run(name)
      scraper = get(name)
      scraper.scrape
    rescue NotFoundError => e
      log_error "Scraper not found: #{e.message}"
      []
    rescue StandardError => e
      log_error "Scraper '#{name}' failed: #{e.class} - #{e.message}"
      []
    end

    # Run all registered scrapers and merge results.
    #
    # Each scraper runs independently; failures are logged but do not
    # stop processing other scrapers.
    #
    # @return [Array<Event>] merged events from all scrapers
    def run_all
      all.flat_map do |scraper|
        run(scraper.name)
      end
    end

    # Run only the active (enabled) scrapers and merge results.
    #
    # Respects config.sites (or config.enabled_scrapers if set).
    # If no sites are configured, runs all registered scrapers.
    #
    # @return [Array<Event>] merged events from active scrapers
    def run_active
      active.flat_map do |scraper|
        run(scraper.name)
      end
    end

    private

    # Determine which scraper names are enabled based on config.
    #
    # @return [Array<String>]
    def enabled_scrapers
      return [] unless @config

      # Prefer config.enabled_scrapers if it exists, fall back to config.sites
      if @config.respond_to?(:enabled_scrapers)
        @config.enabled_scrapers.map(&:to_s)
      elsif @config.respond_to?(:sites)
        @config.sites.map(&:to_s)
      else
        []
      end
    end

    def log_info(msg)
      @config&.logger&.info("[ScraperRegistry] #{msg}")
    end

    def log_error(msg)
      @config&.logger&.error("[ScraperRegistry] #{msg}")
    end
  end
end
