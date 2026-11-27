# frozen_string_literal: true

module WeeklyLocalEvents
  # Summary of a single Application run.
  #
  # Contains counts per source and a total event count.
  #
  # Usage:
  #   summary = Summary.new(total: 42, sources: { austin_chronicle: 15, do512: 27 })
  #   summary.total              # => 42
  #   summary.sources            # => { austin_chronicle: 15, do512: 27 }
  #   summary.to_h               # => { total: 42, sources: { ... } }
  class Summary
    attr_reader :total, :sources, :events

    def initialize(total:, sources:, events: [])
      @total = total
      @sources = sources
      @events = events
    end

    def to_h
      { total: total, sources: sources, events: events }
    end

    def to_s
      "Summary(total: #{total}, sources: #{sources.inspect})"
    end
  end
end
