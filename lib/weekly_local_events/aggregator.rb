# frozen_string_literal: true

require "active_support/core_ext/enumerable"
require "active_support/core_ext/string/inflections"

module WeeklyLocalEvents
  # Aggregates raw events from all scrapers: deduplicates, normalizes,
  # filters, sorts, and formats them for downstream consumption.
  #
  # Usage:
  #   aggregator = Aggregator.new
  #   events = aggregator.aggregate(raw_events)
  #   puts aggregator.format_for_notification(events)
  class Aggregator
    # Default date range for filtering (next N days).
    DEFAULT_DAYS = 7

    def initialize(config = nil)
      @config = config
      @category_normalization = {}
      @enriched = {}
    end

    # Main pipeline: normalize → deduplicate → filter → sort → enrich.
    #
    # @param events [Array<Event>] raw events from scrapers
    # @return [Array<Event>] processed events
    def aggregate(events)
      events = normalize_prices(events)
      events = deduplicate(events)
      events = filter_by_date_range(events, start_date, end_date)
      events = sort_by_date(events)
      events = enrich(events)
      events
    end

    # Remove duplicate events based on a composite key (venue + date + title).
    #
    # Events with the same dedup_key are considered duplicates; the first
    # occurrence is kept.
    #
    # @param events [Array<Event>]
    # @return [Array<Event>]
    def deduplicate(events)
      seen = {}
      events.select do |event|
        key = dedup_key(event)
        unless seen.key?(key)
          seen[key] = event
          true
        else
          false
        end
      end
    end

    # Generate a composite deduplication key from an event.
    #
    # Combines venue name, date, and a normalized version of the title
    # (lowercase, no punctuation, collapsed whitespace).
    #
    # @param event [Event]
    # @return [String] composite key
    def dedup_key(event)
      venue_name = event.venue&.name&.downcase&.gsub(/\s+/, " ") || "unknown"
      date_str = event.date&.to_s || "unknown"
      title = normalize_title(event.title)
      "#{venue_name}|#{date_str}|#{title}"
    end

    # Normalize price strings across all events.
    #
    # Sets `price_cents` on each event and normalizes the `price` string
    # to a consistent format. Handles: "$10", "$10.00", "$10-50",
    # "$10 to $50", "Free", "free", "0", "0.00", and raw numeric strings.
    #
    # @param events [Array<Event>]
    # @return [Array<Event>] events with normalized price_cents
    def normalize_prices(events)
      events.each do |event|
        cents = parse_price_to_cents(event.price)
        event.instance_variable_set(:@price_cents_explicit, cents) if cents
      end
      events
    end

    # Filter events to only those within the given date range (inclusive).
    #
    # @param events [Array<Event>]
    # @param start_date [Date] inclusive start
    # @param end_date [Date] inclusive end
    # @return [Array<Event>]
    def filter_by_date_range(events, start_date, end_date)
      events.select { |event| event.in_date_range?(start_date, end_date) }
    end

    # Sort events by date in ascending order.
    #
    # Events without a valid date are placed at the end.
    #
    # @param events [Array<Event>]
    # @return [Array<Event>]
    def sort_by_date(events)
      # Tuple key keeps dated events in chronological order and pushes
      # undated events to the end without relying on a non-existent Date.max.
      events.sort_by { |event| [event.date.nil? ? 1 : 0, event.date] }
    end

    # Enrich events with additional data (geocoding, categories).
    #
    # - Geocodes venues that lack coordinates (via Venue#geocode!).
    # - Normalizes categories to a standard set.
    # - Caches enrichment results to avoid redundant work.
    #
    # @param events [Array<Event>]
    # @return [Array<Event>]
    def enrich(events)
      events.each do |event|
        # Geocode venue if coordinates are missing
        if event.venue && !event.venue.geocoded?
          begin
            event.venue.geocode!
          rescue WeeklyLocalEvents::GeocodeError
            # Silently skip — venue remains un-geocoded
          end
        end

        # Normalize category
        event.instance_variable_set(:@category, normalize_category(event.category))

        # Cache enrichment
        @enriched[event.object_id] = true
      end
      events
    end

    # Format events into a human-readable text block for Telegram notifications.
    #
    # Groups events by date and formats each with venue, price, and time.
    #
    # @param events [Array<Event>]
    # @return [String] formatted text
    def format_for_notification(events)
      return "No events found for the selected date range." if events.empty?

      grouped = events.group_by { |e| e.date&.strftime("%A, %B %d") || "Undated" }
      lines = grouped.sort_by { |date, _| date }.map do |date_label, day_events|
        header = "**#{date_label}**\n"
        body = day_events.map { |e| format_event(e) }.join("\n\n")
        "#{header}\n#{body}"
      end

      lines.join("\n\n" + "-" * 40 + "\n\n")
    end

    # Generate summary statistics from a list of events.
    #
    # @return [Hash] with keys:
    #   :total, :free_count, :paid_count, :categories, :price_ranges,
    #   :sources, :average_price, :date_range, :venues
    def format_summary(events)
      return {} if events.empty?

      categories = events.map(&:category).compact.tally.sort_by { |_, count| -count }
      sources = events.map(&:source).compact.tally.sort_by { |_, count| -count }
      venues = events.map { |e| e.venue&.name }.compact.tally.sort_by { |_, count| -count }

      price_cents_values = events.map(&:price_cents).compact.reject(&:zero?)
      avg_price = price_cents_values.any? ? price_cents_values.sum.to_f / price_cents_values.size : 0

      dates = events.map(&:date).compact
      date_range = { from: dates.min, to: dates.max }

      {
        total: events.size,
        free_count: events.count(&:free?),
        paid_count: events.size - events.count(&:free?),
        categories: categories,
        price_ranges: {
          free: events.count(&:free?),
          paid: events.size - events.count(&:free?),
          average_cents: avg_price.round,
          average_dollars: (avg_price / 100.0).round(2),
        },
        sources: sources,
        average_price: avg_price,
        date_range: date_range,
        venues: venues,
      }
    end

    private

    # Generate the start date for filtering (default: today).
    #
    # @return [Date]
    def start_date
      @start_date ||= Date.today
    end

    # Generate the end date for filtering (default: today + configured days).
    # Falls back to DEFAULT_DAYS when no config is available.
    #
    # @return [Date]
    def end_date
      @end_date ||= Date.today + (@config&.date_range_days || DEFAULT_DAYS)
    end

    # Normalize a title for deduplication: lowercase, strip punctuation,
    # collapse whitespace, remove common stop words.
    #
    # @param title [String]
    # @return [String] normalized title
    def normalize_title(title)
      title
        .downcase
        .gsub(/[^\w\s]/, "")
        .gsub(/\s+/, " ")
        .strip
    end

    # Parse a price string into cents.
    #
    # Handles: "$10", "$10.00", "$10-50", "$10 to $50", "Free", "free",
    # "0", "0.00", "10", "10.50", "€10", "£10".
    #
    # @param price_str [String, nil]
    # @return [Integer, nil] price in cents, or nil if unparseable
    def parse_price_to_cents(price_str)
      return nil if price_str.to_s.strip.empty?

      s = price_str.to_s.strip

      # Free / no cost
      return 0 if s.downcase == "free" || s.downcase == "no cost" || s.downcase == "none"

      # Range: take the minimum
      if s.include?("-") || s.include?(" to ") || s.include?("–") || s.include?("—")
        parts = s.split(/[-–—]|\s+to\s+/i)
        return parse_single_price(parts.first)
      end

      parse_single_price(s)
    end

    # Parse a single price value (e.g., "$10.50", "10.50", "€10").
    #
    # @param s [String]
    # @return [Integer, nil] cents or nil
    def parse_single_price(s)
      cleaned = s.gsub(/[^0-9.]/, "")
      return nil if cleaned.empty?

      dollars = cleaned.to_f
      return nil if dollars.nan? || dollars.infinite?

      (dollars * 100).round
    end

    # Normalize a category string to a standard set.
    #
    # @param category [String, nil]
    # @return [String, nil]
    def normalize_category(category)
      return nil unless category && !category.to_s.strip.empty?

      cat = category.to_s.strip.downcase
      @category_normalization[cat] ||= case cat
      when /concert|live music|show|performance|gig|band|musician|music/
        "Music"
      when /comedy|stand-up|improv|joke|humor/
        "Comedy"
      when /festival|fair|carnival|cultural/
        "Festival"
      when /sport|game|match|tournament|athletic/
        "Sports"
      when /art|exhibition|gallery|museum|painting|sculpture/
        "Art"
      when /food|culinary|dining|restaurant|tasting|cook/
        "Food & Drink"
      when /market|bazaar|craft|vendor/
        "Market"
      when /conference|workshop|seminar|lecture|class|training/
        "Education"
      when /theater|play|drama|musical|broadway/
        "Theater"
      when /family|kids|children|youth|teen/
        "Family"
      when /nightlife|club|bar|party|dance|dj|rave/
        "Nightlife"
      when /outdoor|park|trail|hiking|nature|camping/
        "Outdoor"
      when /religious|church|temple|mosque|spiritual/
        "Religious"
      when /politics|protest|rally|election|debate/
        "Politics"
      when /tech|startup|hackathon|developer|coding/
        "Technology"
      else
        cat.humanize
      end
    end

    # Format a single event for notification display.
    #
    # @param event [Event]
    # @return [String]
    def format_event(event)
      parts = []
      parts << "**#{event.title}**"
      parts << event.venue&.full_address if event.venue
      parts << "🕐 #{event.time}" if event.time.present?
      parts << "💰 #{event.price_range}" unless event.price_range.empty?
      parts << "📍 #{event.category}" if event.category.present?
      parts << "🔗 #{event.url}" if event.url.present?
      parts.join("\n")
    end
  end
end
