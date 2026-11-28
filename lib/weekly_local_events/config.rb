# frozen_string_literal: true

require "yaml"
require "logger"

module WeeklyLocalEvents
  class Error < StandardError; end

  # Configuration loader for WeeklyLocalEvents.
  #
  # Loads settings from three sources in priority order:
  #   1. ~/.hermes/weekly_local_events/config.yml (primary)
  #   2. ENV variables (overrides YAML)
  #   3. .env file in project root (via dotenv)
  #
  # Access via: WeeklyLocalEvents.config
  class Config
    DEFAULTS = {
      sites: %w[austin_chronicle do512 community_impact],
      log_level: "INFO",
      date_range_days: 7,
      request_timeout: 30,
      request_delay: 2,
      max_retries: 3,
      max_events_per_batch: 50,
    }.freeze

    REQUIRED_KEYS = %w[notification_channel_id telegram_bot_token].freeze

    attr_reader :sites, :enabled_scrapers, :log_level, :date_range_days, :request_timeout,
                :request_delay, :max_retries, :max_events_per_batch, :cached_fixture_path

    def initialize
      @raw = load_from_yaml
      apply_env_overrides
      validate!
      build_attributes
    end

    def notification_channel_id
      raw["notification_channel_id"] || ENV["NOTIFICATION_CHANNEL_ID"]
    end

    def telegram_bot_token
      raw["telegram_bot_token"] || ENV["TELEGRAM_BOT_TOKEN"]
    end

    def notifications_enabled?
      !telegram_bot_token.to_s.strip.empty? && !notification_channel_id.to_s.strip.empty?
    end

    def logger
      @logger ||= begin
        level = Logger.const_get(log_level.upcase)
        Logger.new($stdout).tap { |l| l.level = level }
      end
    end

    private

    attr_reader :raw

    def load_from_yaml
      path = default_config_path
      return {} unless File.exist?(path)

      YAML.load_file(path) || {}
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML at #{path}: #{e.message}"
    end

    def default_config_path
      File.expand_path("~/.hermes/weekly_local_events/config.yml")
    end

    def apply_env_overrides
      ENV.each do |key, value|
        snake_key = key.downcase
        raw[snake_key] = value
      end
    end

    def validate!
      REQUIRED_KEYS.each do |key|
        value = raw[key]
        raise ConfigError, "Required config key '#{key}' is not set" if value.nil? || value.to_s.strip.empty?
      end
    end

    def build_attributes
      @sites = (raw["sites"] || DEFAULTS[:sites]).dup
      @sites = @sites.map(&:to_s) unless @sites.is_a?(Array)
      @enabled_scrapers = (raw["enabled_scrapers"] || raw["sites"] || DEFAULTS[:sites]).dup
      @enabled_scrapers = @enabled_scrapers.map(&:to_s) unless @enabled_scrapers.is_a?(Array)
      @log_level = (raw["log_level"] || DEFAULTS[:log_level]).to_s.upcase
      @date_range_days = (raw["date_range_days"] || DEFAULTS[:date_range_days]).to_i
      @request_timeout = (raw["request_timeout"] || DEFAULTS[:request_timeout]).to_i
      @request_delay = (raw["request_delay"] || DEFAULTS[:request_delay]).to_i
      @max_retries = (raw["max_retries"] || DEFAULTS[:max_retries]).to_i
      @max_events_per_batch = (raw["max_events_per_batch"] || DEFAULTS[:max_events_per_batch]).to_i
      @cached_fixture_path = raw["cached_fixture_path"]
    end
  end

  class ConfigError < Error; end
end
