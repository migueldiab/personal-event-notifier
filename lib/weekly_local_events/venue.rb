# frozen_string_literal: true

require "active_model"
require "net/http"
require "uri"
require "json"

module WeeklyLocalEvents
  # Raised when Venue.from_hash is called with missing required fields.
  class VenueParseError < StandardError; end

  # Raised when geocoding fails.
  class GeocodeError < StandardError; end

  # Represents a venue (event location) for a discovered event.
  #
  # Validates required fields, formats addresses nicely, and provides
  # geocoding (via Google Maps API) and distance calculation helpers.
  #
  # Usage:
  #   venue = Venue.new(name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701")
  #   venue.valid?
  #   Venue.from_hash({ name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701" })
  class Venue
    include ActiveModel::Validations

    # ISO 3166-2 US state codes for validation.
    US_STATE_CODES = %w[
      AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS
      MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA
      WV WI WY DC PR
    ].freeze

    attr_reader :name, :address, :city, :state, :zip, :lat, :lng, :website, :phone, :url

    validates :name, presence: true
    validates :state, inclusion: { in: US_STATE_CODES, allow_nil: true }, if: -> { state.present? }

    # Google Maps Geocoding API key (set via GEOCODER_API_KEY env var).
    # If not set, geocode! falls back to a manual lookup via the city/state.
    GOOGLE_MAPS_API_KEY = ENV.fetch("GEOCODER_API_KEY", nil)

    # @param name [String] - required venue name
    # @param address [String, nil] - street address
    # @param city [String, nil] - city name
    # @param state [String] - state abbreviation (default: 'TX')
    # @param zip [String, nil] - ZIP code
    # @param lat [Float, nil] - latitude (if known)
    # @param lng [Float, nil] - longitude (if known)
    # @param website [String, nil] - venue website URL
    # @param phone [String, nil] - contact phone number
    # @param url [String, nil] - alias for website
    def initialize(name:, address: nil, city: nil, state: "TX", zip: nil,
                   lat: nil, lng: nil, website: nil, phone: nil, url: nil)
      @name = name.to_s.strip
      @address = address.to_s.strip
      @city = city.to_s.strip
      @state = state.to_s.strip.upcase
      @zip = zip.to_s.strip
      @lat = lat
      @lng = lng
      @website = website.to_s.strip
      @phone = phone.to_s.strip
      @url = url.to_s.strip
    end

    # Create a Venue from a hash (e.g., parsed from a scraper).
    #
    # @param hash [Hash] keys: name, and optional address, city, state, zip, etc.
    # @return [Venue, nil] nil if hash is nil
    # @raise [VenueParseError] if name is missing
    def self.from_hash(hash)
      return nil unless hash.is_a?(Hash)

      name = hash[:name] || hash["name"]
      raise VenueParseError, "Missing required field: name" unless name && !name.to_s.strip.empty?

      new(
        name: name,
        address: hash[:address] || hash["address"],
        city: hash[:city] || hash["city"],
        state: hash[:state] || hash["state"],
        zip: hash[:zip] || hash["zip"],
        lat: hash[:lat],
        lng: hash[:lng],
        website: hash[:website] || hash["website"],
        phone: hash[:phone] || hash["phone"],
        url: hash[:url] || hash["url"],
      )
    end

    # Serialize the venue back to a hash.
    #
    # @return [Hash]
    def to_h
      {
        name: name,
        address: address,
        city: city,
        state: state,
        zip: zip,
        lat: lat,
        lng: lng,
        website: website,
        phone: phone,
        url: url,
      }
    end

    # Return a formatted full address string.
    #
    # Includes only non-empty components, comma-separated.
    # Examples:
    #   "310 W 5th St, Austin, TX 78701" (address only, no name)
    #   "ACL Live: 310 W 5th St, Austin, TX 78701" (with name)
    #
    # @return [String]
    def full_address
      parts = [address, city, state, zip].compact.reject(&:empty?)
      return name if parts.empty?
      # If only state is present (and no address components), exclude it
      parts = [] if parts == [state] && address.empty? && city.empty? && zip.empty?
      return name if parts.empty?

      "#{name}: #{parts.join(', ')}"
    end

    # Geocode the venue using the Google Maps Geocoding API.
    #
    # Sets @lat and @lng from the API response.
    # Raises GeocodeError if the API call fails.
    #
    # @return [self]
    # @raise [GeocodeError] if geocoding fails
    def geocode!
      if GOOGLE_MAPS_API_KEY
        geocode_with_google!
      else
        geocode_fallback!
      end
      self
    end

    # Calculate the distance from this venue to given coordinates.
    #
    # Uses the Haversine formula to compute the great-circle distance.
    #
    # @param lat [Float] latitude of the reference point
    # @param lng [Float] longitude of the reference point
    # @return [Float] distance in miles
    # @raise [ArgumentError] if lat/lng are not numeric
    def distance_from(lat, lng)
      raise ArgumentError, "lat must be numeric" unless lat.is_a?(Numeric)
      raise ArgumentError, "lng must be numeric" unless lng.is_a?(Numeric)
      raise ArgumentError, "Venue coordinates must be set" unless @lat && @lng

      haversine_distance(@lat, @lng, lat, lng)
    end

    # Check if the venue has valid coordinates.
    #
    # @return [Boolean]
    def geocoded?
      !@lat.nil? && !@lng.nil? && @lat != 0.0 && @lng != 0.0
    end

    # Equality based on name, address, city, and state.
    #
    # @param other [Venue]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Venue)
      name == other.name && address == other.address && city == other.city && state == other.state
    end

    alias eql? ==

    def hash
      [name, address, city, state].hash
    end

    private

    def geocode_with_google!
      query = [address, city, state, zip].compact.join(", ")
      return if query.strip.empty?

      uri = URI("https://maps.googleapis.com/maps/api/geocode/json")
      uri.query = URI.encode_www_form(
        address: query,
        key: GOOGLE_MAPS_API_KEY,
      )

      response = Net::HTTP.get(uri)
      data = JSON.parse(response)

      if data["status"] != "OK"
        raise GeocodeError, "Google Maps geocoding failed: #{data['status']} - #{data['error_message']}"
      end

      results = data["results"]
      raise GeocodeError, "No results found for '#{query}'" if results.empty?

      place = results.first
      @lat = place["geometry"]["location"]["lat"].to_f
      @lng = place["geometry"]["location"]["lng"].to_f
    end

    def geocode_fallback!
      # Manual lookup: use a simple coordinate mapping for known cities.
      # In production, this would use a different free API or a local geocoding library.
      return if city.nil? || city.strip.empty?

      case city.downcase
      when "dallas"
        @lat, @lng = 32.7767, -96.7970
      when "houston"
        @lat, @lng = 29.7604, -95.3698
      when "san antonio"
        @lat, @lng = 29.4241, -98.4936
      when "fort worth"
        @lat, @lng = 32.7555, -97.3308
      when "el paso"
        @lat, @lng = 31.7619, -106.4850
      when "austin"
        @lat, @lng = 30.2672, -97.7431
      else
        @lat, @lng = 30.2672, -97.7431  # default: Austin, TX
      end
    end

    # Haversine formula for great-circle distance between two points.
    #
    # @param lat1 [Float] latitude of point 1 (degrees)
    # @param lng1 [Float] longitude of point 1 (degrees)
    # @param lat2 [Float] latitude of point 2 (degrees)
    # @param lng2 [Float] longitude of point 2 (degrees)
    # @return [Float] distance in miles
    def haversine_distance(lat1, lng1, lat2, lng2)
      earth_radius_miles = 3958.8

      dlat = (lat2 - lat1) * Math::PI / 180
      dlng = (lng2 - lng1) * Math::PI / 180

      a = Math.sin(dlat / 2) ** 2 +
          Math.cos(lat1 * Math::PI / 180) *
          Math.cos(lat2 * Math::PI / 180) *
          Math.sin(dlng / 2) ** 2

      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      earth_radius_miles * c
    end
  end
end
