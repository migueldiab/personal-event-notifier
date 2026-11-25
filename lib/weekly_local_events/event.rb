# frozen_string_literal: true

require "active_model"
require "date"
require "weekly_local_events/version"

module WeeklyLocalEvents
  # Raised when Event.from_hash is called with missing required fields.
  class EventParseError < StandardError; end

  # Represents a single event discovered by a scraper.
  #
  # Validates required fields, normalizes price strings into cents,
  # and provides helper methods for filtering and serialization.
  #
  # Usage:
  #   event = Event.new(title: "Concert", date: Date.today, venue: venue, url: "https://...")
  #   event.valid?
  #   Event.from_hash({ title: "...", date: "...", venue: venue, url: "..." })
  class Event
    include ActiveModel::Validations

    attr_reader :title, :description, :date, :time, :venue, :price,
                :currency, :url, :source, :image_url,
                :category, :tags, :created_at, :updated_at

    # Returns price in cents. Computed from `price` string if not explicitly set.
    #
    # @return [Integer, nil]
    def price_cents
      return @price_cents_explicit if @price_cents_explicit
      parse_price_to_cents(price)
    end

    validates :title, presence: true
    validates :date, presence: true
    validates :venue, presence: true
    validates :url, presence: true
    validates :source, presence: true

    validate :price_cents_positive_if_set

    # @param title [String]
    # @param description [String, nil]
    # @param date [Date, String]
    # @param time [String, nil]
    # @param venue [Venue]
    # @param price [String, nil] - raw price string
    # @param price_cents [Integer, nil] - normalized price in cents
    # @param currency [String]
    # @param url [String]
    # @param source [String]
    # @param image_url [String, nil]
    # @param category [String, nil]
    # @param tags [Array<String>, nil]
    # @param created_at [Time]
    # @param updated_at [Time]
    def initialize(title:, date:, venue:, url:, source:,
                   description: nil, time: nil, price: nil,
                   price_cents: nil, currency: "USD",
                   image_url: nil, category: nil, tags: nil,
                   created_at: nil, updated_at: nil)
      @title = title.to_s
      @description = description.to_s
      @date = parse_date(date)
      @time = time.to_s
      @venue = venue
      @price = price.to_s
      @price_cents = price_cents
      @currency = currency.to_s
      @url = url.to_s
      @source = source.to_s
      @image_url = image_url.to_s
      @category = category.to_s
      @tags = tags.is_a?(Array) ? tags : (tags.to_s.split(",").map(&:strip) if tags && !tags.to_s.strip.empty?)
      @created_at = created_at || Time.now
      @updated_at = updated_at || Time.now
      @price_cents_explicit = price_cents
    end

    # Create an Event from a hash (e.g., parsed from a scraper).
    #
    # @param hash [Hash] keys: title, date, venue, url, source, and optional fields
    # @return [Event]
    # @raise [ParseError] if required fields are missing
    def self.from_hash(hash)
      required = %i[title date venue url source]
      missing = required - hash.keys
      raise EventParseError, "Missing required fields: #{missing.join(", ")}" unless missing.empty?

      new(
        title: hash[:title],
        date: hash[:date],
        venue: hash[:venue],
        url: hash[:url],
        source: hash[:source],
        description: hash[:description],
        time: hash[:time],
        price: hash[:price],
        price_cents: hash[:price_cents],
        currency: hash[:currency] || "USD",
        image_url: hash[:image_url],
        category: hash[:category],
        tags: hash[:tags],
      )
    end

    # Serialize the event back to a hash.
    #
    # @return [Hash]
    def to_hash
      {
        title: title,
        description: description,
        date: date,
        time: time,
        venue: venue&.to_h,
        price: price,
        price_cents: price_cents,
        currency: currency,
        url: url,
        source: source,
        image_url: image_url,
        category: category,
        tags: tags,
        created_at: created_at,
        updated_at: updated_at,
      }
    end

    # Check if the event is free (price is 'free' or 0 cents).
    #
    # @return [Boolean]
    def free?
      price.to_s.strip.downcase == "free" || price_cents == 0
    end

    # Return a human-readable price range string.
    #
    # Handles formats like "$10", "$10.00", "$10-50", "$10 to $50".
    #
    # @return [String]
    def price_range
      raw = price.to_s.strip
      return "" if raw.empty? && price_cents.nil?

      if raw.downcase == "free"
        "Free"
      elsif raw.include?("-") || raw.include?(" to ") || raw.include?("–")
        # Range: extract min and max from raw string
        parts = raw.split(/[-–]|\s+to\s+/i)
        min_cents = parse_price_to_cents(parts.first)
        max_cents = parse_price_to_cents(parts.last)
        if min_cents && max_cents
          "#{format_price(min_cents)}–#{format_price(max_cents)}"
        elsif min_cents
          format_price(min_cents)
        else
          raw
        end
      elsif price_cents
        format_price(price_cents)
      else
        format_price(parse_price_to_cents(raw) || 0)
      end
    end

    # Check if the event falls within the given date range (inclusive).
    #
    # @param start_date [Date]
    # @param end_date [Date]
    # @return [Boolean]
    def in_date_range?(start_date, end_date)
      return false unless date
      date >= start_date && date <= end_date
    end

    # Equality based on title, date, venue, and URL.
    #
    # @param other [Event]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Event)
      title == other.title && date == other.date && venue == other.venue && url == other.url
    end

    alias eql? ==

    def hash
      [title, date, venue, url].hash
    end

    private

    def parse_date(value)
      return nil unless value
      case value
      when Date
        value
      when String
        Date.parse(value)
      else
        Date.parse(value.to_s)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def parse_price_to_cents(price_str)
      return nil if price_str.to_s.strip.empty?

      s = price_str.to_s.strip.gsub(/[^0-9.]/, "")
      return nil if s.empty?

      dollars = s.to_f
      (dollars * 100).round
    end

    def format_price(cents)
      dollars = cents / 100.0
      if dollars == dollars.to_i
        "$#{dollars.to_i}"
      else
        "$#{dollars}"
      end
    end

    def price_cents_positive_if_set
      return unless price_cents && price_cents < 0
      errors.add(:price_cents, "must be non-negative")
    end
  end
end
