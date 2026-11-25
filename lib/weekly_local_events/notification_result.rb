# frozen_string_literal: true

module WeeklyLocalEvents
  # Result of a single notification attempt.
  #
  # Usage:
  #   result = NotificationResult.new(success: true, events_sent: 5)
  #   result.success?   # => true
  #   result.to_h       # => { success: true, events_sent: 5 }
  class NotificationResult
    attr_reader :success, :events_sent, :error

    def initialize(success:, events_sent:, error: nil)
      @success = success
      @events_sent = events_sent
      @error = error
    end

    def success?
      @success
    end

    def to_h
      { success: success, events_sent: events_sent, error: error }
    end

    def to_s
      return "NotificationResult(OK: #{events_sent} events)" if success?
      "NotificationResult(FAILED: #{error})"
    end
  end
end
