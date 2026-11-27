# frozen_string_literal: true

module WeeklyLocalEvents
  # Result of a single notification attempt.
  #
  # Usage:
  #   result = NotificationResult.new(success: true, events_sent: 5)
  #   result.success?   # => true
  #   result.to_h       # => { success: true, events_sent: 5 }
  class NotificationResult
    attr_reader :success, :events_sent, :error, :dry_run

    def initialize(success:, events_sent:, error: nil, dry_run: false)
      @success = success
      @events_sent = events_sent
      @error = error
      @dry_run = dry_run
    end

    def success?
      @success
    end

    def to_h
      { success: success, events_sent: events_sent, error: error, dry_run: dry_run }
    end

    def to_s
      return "NotificationResult(OK: #{events_sent} events)" if success?
      "NotificationResult(FAILED: #{error})"
    end

    def skipped?
      dry_run
    end
  end
end
