# frozen_string_literal: true

module WeeklyLocalEvents
  module Utils
    class DateHelper
      def self.next_week_start
        Time.now.in_time_zone("America/Chicago").beginning_of_week
      end

      def self.next_week_end
        next_week_start + 7.days
      end

      def self.format_for_telegram(date)
        return "N/A" unless date
        date.strftime("%A, %B %-d, %Y at %-l:%M %p")
      end
    end
  end
end
