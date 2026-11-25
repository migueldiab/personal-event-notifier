# frozen_string_literal: true

require "digest"

module WeeklyLocalEvents
  module Pipeline
    class Normalizer
      attr_reader :raw_event

      def initialize(raw_event)
        @raw_event = raw_event
      end

      def run
        Event.new(
          id: generate_id(raw_event),
          title: normalize_title(raw_event[:title]),
          event_type: classify_event(raw_event[:title]),
          date: parse_date(raw_event[:date]),
          location: normalize_location(raw_event[:location]),
          source: raw_event[:source],
          description: raw_event[:description] || "",
          url: raw_event[:url] || "",
          broadcast_info: raw_event[:broadcast_info] || ""
        )
      end

      private

      def generate_id(event)
        Digest::MD5.hexdigest(
          "#{normalize_title(event[:title])}#{parse_date(event[:date])}#{normalize_location(event[:location])}"
        )[0..15]
      end

      def normalize_title(title)
        title.to_s.strip.downcase
      end

      def classify_event(title)
        title.to_s.downcase
      end

      def parse_date(date_str)
        return nil unless date_str
        # Placeholder: implement proper date parsing
        date_str
      end

      def normalize_location(location)
        location.to_s.strip
      end
    end
  end
end
