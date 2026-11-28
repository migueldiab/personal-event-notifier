# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module WeeklyLocalEvents
  # Persists structured events to a JSON file at an absolute path.
  #
  # The file layout is:
  #   { "generated_at" => ISO8601, "count" => N, "events" => [ ... ] }
  class EventStore
    attr_reader :path

    # @param path [String] absolute path to the JSON output file
    def initialize(path:)
      @path = File.expand_path(path)
    end

    # Write events to the store, replacing any previous snapshot.
    #
    # @param events [Array<Hash>] structured event hashes
    # @return [String] the path written
    def write(events)
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        "generated_at" => Time.now.utc.iso8601,
        "count" => events.length,
        "events" => events
      }
      File.write(path, JSON.pretty_generate(payload), encoding: "UTF-8")
      path
    end

    # Read previously stored events.
    #
    # @return [Array<Hash>] event hashes (empty when the file is absent)
    def read
      return [] unless File.file?(path)

      JSON.parse(File.read(path, encoding: "UTF-8"))["events"] || []
    end
  end
end
