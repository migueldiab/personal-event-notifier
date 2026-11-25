# frozen_string_literal: true

require "weekly_local_events/version"

module WeeklyLocalEvents
  # Main entry point for the weekly local events monitor
  class Application
    attr_reader :config

    def initialize(config_path: nil)
      @config = Config.load(path: config_path)
    end

    def run
      pipeline = Pipeline::Engine.new(config)
      events = pipeline.execute
      NotificationDispatcher.dispatch(events)
      puts "Processed #{events.size} events."
    end
  end
end
