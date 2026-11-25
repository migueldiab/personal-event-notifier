# frozen_string_literal: true

require "weekly_local_events/core/event"

module WeeklyLocalEvents
  module Pipeline
    class Engine
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def execute
        events = fetch_events
        normalized = normalize(events)
        deduplicated = deduplicate(normalized)
        deduplicated
      end

      private

      def fetch_events
        config.sources.flat_map do |source|
          Engine::CrawlerEngine.new(source).fetch
        end
      end

      def normalize(events)
        events.map do |event|
          Normalizer.new(event).run
        end
      end

      def deduplicate(events)
        seen = Set.new
        events.select do |event|
          key = event.fuzzy_key
          seen.add?(key)
        end
      end
    end
  end
end
