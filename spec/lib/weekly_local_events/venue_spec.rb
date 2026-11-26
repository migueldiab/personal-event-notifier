# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "weekly_local_events/venue"

RSpec.describe WeeklyLocalEvents::Venue do
  subject(:venue) { described_class.new(name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701") }

  describe "#full_address" do
    it "returns the full address string" do
      expect(venue.full_address).to eq("ACL Live: 310 W 5th St, Austin, TX, 78701")
    end

    context "with no address components" do
      subject(:venue) { described_class.new(name: "Solo Venue") }
      it "returns just the name" do
        expect(venue.full_address).to eq("Solo Venue")
      end
    end

    context "with partial address" do
      subject(:venue) { described_class.new(name: "Test", city: "Austin", state: "TX") }
      it "returns partial address" do
        expect(venue.full_address).to eq("Test: Austin, TX")
      end
    end

    context "with only address, no city/state/zip" do
      subject(:venue) { described_class.new(name: "Test", address: "123 Main St") }
      it "returns address with default state TX" do
        expect(venue.full_address).to eq("Test: 123 Main St, TX")
      end
    end

    context "with only city and state" do
      subject(:venue) { described_class.new(name: "Test", city: "Dallas", state: "TX") }
      it "returns city and state" do
        expect(venue.full_address).to eq("Test: Dallas, TX")
      end
    end

    context "with only state (no address, city, or zip)" do
      subject(:venue) { described_class.new(name: "Test", state: "TX") }
      it "returns just the name" do
        expect(venue.full_address).to eq("Test")
      end
    end

    context "with empty strings" do
      subject(:venue) { described_class.new(name: "Test", address: "", city: "", state: "", zip: "") }
      it "returns just the name" do
        expect(venue.full_address).to eq("Test")
      end
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      hash = venue.to_h
      expect(hash[:name]).to eq("ACL Live")
      expect(hash[:address]).to eq("310 W 5th St")
      expect(hash[:city]).to eq("Austin")
      expect(hash[:state]).to eq("TX")
      expect(hash[:zip]).to eq("78701")
    end

    it "includes optional fields" do
      v = described_class.new(name: "Test", website: "https://example.com", phone: "555-1234")
      hash = v.to_h
      expect(hash[:website]).to eq("https://example.com")
      expect(hash[:phone]).to eq("555-1234")
    end

    it "includes lat/lng when set" do
      v = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      hash = v.to_h
      expect(hash[:lat]).to eq(30.0)
      expect(hash[:lng]).to eq(-97.0)
    end

    it "includes url field" do
      v = described_class.new(name: "Test", url: "https://example.com")
      hash = v.to_h
      expect(hash[:url]).to eq("https://example.com")
    end

    it "strips whitespace from all string fields" do
      v = described_class.new(name: "  Test  ", address: "  123 Main  ")
      hash = v.to_h
      expect(hash[:name]).to eq("Test")
      expect(hash[:address]).to eq("123 Main")
    end
  end

  describe "#from_hash" do
    it "creates a venue from a hash" do
      hash = { name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701" }
      venue = described_class.from_hash(hash)
      expect(venue.name).to eq("ACL Live")
      expect(venue.full_address).to eq("ACL Live: 310 W 5th St, Austin, TX, 78701")
    end

    it "raises VenueParseError when name is missing" do
      expect { described_class.from_hash({ address: "123 Main" }) }
        .to raise_error(WeeklyLocalEvents::VenueParseError, /Missing required field: name/)
    end

    it "raises VenueParseError when name is empty string" do
      expect { described_class.from_hash({ name: "" }) }
        .to raise_error(WeeklyLocalEvents::VenueParseError, /Missing required field: name/)
    end

    it "raises VenueParseError when name is whitespace only" do
      expect { described_class.from_hash({ name: "   " }) }
        .to raise_error(WeeklyLocalEvents::VenueParseError, /Missing required field: name/)
    end

    it "returns nil for non-hash input" do
      expect(described_class.from_hash(nil)).to be_nil
      expect(described_class.from_hash("string")).to be_nil
    end

    it "handles string keys" do
      hash = { "name" => "ACL Live", "address" => "310 W 5th St", "city" => "Austin" }
      venue = described_class.from_hash(hash)
      expect(venue.name).to eq("ACL Live")
    end

    it "handles mixed keys" do
      hash = { name: "ACL Live", "address" => "310 W 5th St", city: "Austin" }
      venue = described_class.from_hash(hash)
      expect(venue.name).to eq("ACL Live")
      expect(venue.address).to eq("310 W 5th St")
    end

    it "passes through optional fields" do
      hash = { name: "Test", lat: 30.5, lng: -97.5, website: "https://example.com", phone: "555-0000" }
      venue = described_class.from_hash(hash)
      expect(venue.lat).to eq(30.5)
      expect(venue.lng).to eq(-97.5)
      expect(venue.website).to eq("https://example.com")
      expect(venue.phone).to eq("555-0000")
    end

    it "normalizes state to uppercase" do
      venue = described_class.from_hash({ name: "Test", state: "tx" })
      expect(venue.state).to eq("TX")
    end
  end

  describe "#geocode!" do
    before(:each) do
      # Ensure GOOGLE_MAPS_API_KEY is nil before each test (some tests mutate it)
      described_class.const_set(:GOOGLE_MAPS_API_KEY, nil)
    end

    context "without API key (fallback)" do
      it "sets coordinates for known cities" do
        venue = described_class.new(name: "Test", city: "Dallas")
        venue.geocode!
        expect(venue.lat).to eq(32.7767)
        expect(venue.lng).to eq(-96.7970)
      end

      it "defaults to Austin coordinates for unknown cities" do
        venue = described_class.new(name: "Test", city: "Unknown City")
        venue.geocode!
        expect(venue.lat).to eq(30.2672)
        expect(venue.lng).to eq(-97.7431)
      end

      it "does nothing if city is nil" do
        venue = described_class.new(name: "Test")
        venue.geocode!
        expect(venue.lat).to be_nil
        expect(venue.lng).to be_nil
      end

      it "does nothing if city is empty" do
        venue = described_class.new(name: "Test", city: "")
        venue.geocode!
        expect(venue.lat).to be_nil
        expect(venue.lng).to be_nil
      end

      it "returns self for chaining" do
        venue = described_class.new(name: "Test", city: "Austin")
        result = venue.geocode!
        expect(result).to eq(venue)
      end
    end

    context "with API key (Google Maps)" do
      it "uses fallback when no API key is configured" do
        venue = described_class.new(name: "Test", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701")
        venue.geocode!
        expect(venue.lat).to eq(30.2672)
        expect(venue.lng).to eq(-97.7431)
      end

      it "calls Google Maps API when key is set" do
        stub_request(:get, %r{https://maps\.googleapis\.com/maps/api/geocode/json})
          .to_return(status: 200, body: JSON.generate({
            "results" => [{
              "geometry" => { "location" => { "lat" => 30.2672, "lng" => -97.7431 } }
            }],
            "status" => "OK"
          }), headers: { "Content-Type" => "application/json" })

        # Temporarily set the API key constant
        original_key = described_class::GOOGLE_MAPS_API_KEY
        described_class.const_set(:GOOGLE_MAPS_API_KEY, "test-key-123")

        venue = described_class.new(name: "Test", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701")
        venue.geocode!
        expect(venue.lat).to eq(30.2672)
        expect(venue.lng).to eq(-97.7431)

        described_class.const_set(:GOOGLE_MAPS_API_KEY, original_key)
      end

      it "raises GeocodeError when Google Maps returns error status" do
        stub_request(:get, %r{https://maps\.googleapis\.com/maps/api/geocode/json})
          .to_return(status: 200, body: JSON.generate({
            "results" => [],
            "status" => "ZERO_RESULTS"
          }), headers: { "Content-Type" => "application/json" })

        original_key = described_class::GOOGLE_MAPS_API_KEY
        described_class.const_set(:GOOGLE_MAPS_API_KEY, "test-key-123")

        venue = described_class.new(name: "Test", address: "310 W 5th St", city: "Austin", state: "TX", zip: "78701")
        expect { venue.geocode! }.to raise_error(WeeklyLocalEvents::GeocodeError, /Google Maps geocoding failed: ZERO_RESULTS/)

        described_class.const_set(:GOOGLE_MAPS_API_KEY, original_key)
      end
    end
  end

  describe "#haversine_distance" do
    it "calculates distance between two points" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      distance = venue.send(:haversine_distance, 30.0, -97.0, 30.0, -97.0)
      expect(distance).to be_within(0.001).of(0.0)
    end

    it "calculates distance between Austin and Dallas" do
      venue = described_class.new(name: "Test", lat: 30.2672, lng: -97.7431)
      distance = venue.send(:haversine_distance, 30.2672, -97.7431, 32.7767, -96.7970)
      expect(distance).to be_within(1.0).of(182.1)
    end
  end

  describe "#distance_from" do
    it "calculates distance in miles" do
      venue = described_class.new(name: "ACL Live", city: "Austin", lat: 30.2672, lng: -97.7431)
      distance = venue.distance_from(32.7767, -96.7970)
      expect(distance).to be_within(1.0).of(182.1)
    end

    it "returns 0 for same coordinates" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      distance = venue.distance_from(30.0, -97.0)
      expect(distance).to be_within(0.001).of(0.0)
    end

    it "raises ArgumentError for non-numeric lat" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      expect { venue.distance_from("not a number", 0) }
        .to raise_error(ArgumentError, /lat must be numeric/)
    end

    it "raises ArgumentError for non-numeric lng" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      expect { venue.distance_from(30.0, "not a number") }
        .to raise_error(ArgumentError, /lng must be numeric/)
    end

    it "raises ArgumentError when coordinates not set" do
      venue = described_class.new(name: "Test")
      expect { venue.distance_from(30.0, -97.0) }
        .to raise_error(ArgumentError, /Venue coordinates must be set/)
    end

    it "accepts integer coordinates" do
      venue = described_class.new(name: "Test", lat: 30, lng: -97)
      distance = venue.distance_from(30, -97)
      expect(distance).to be_within(0.001).of(0.0)
    end
  end

  describe "#geocoded?" do
    it "returns false when not geocoded" do
      venue = described_class.new(name: "Test")
      expect(venue.geocoded?).to be false
    end

    it "returns true after geocoding" do
      venue = described_class.new(name: "Test", city: "Austin")
      venue.geocode!
      expect(venue.geocoded?).to be true
    end

    it "returns false when lat is 0.0" do
      venue = described_class.new(name: "Test", lat: 0.0, lng: -97.0)
      expect(venue.geocoded?).to be false
    end

    it "returns false when lng is 0.0" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: 0.0)
      expect(venue.geocoded?).to be false
    end
  end

  describe "#==" do
    it "returns true for equivalent venues" do
      v1 = described_class.new(name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX")
      v2 = described_class.new(name: "ACL Live", address: "310 W 5th St", city: "Austin", state: "TX")
      expect(v1).to eq(v2)
    end

    it "returns false for different venues" do
      v1 = described_class.new(name: "ACL Live", address: "310 W 5th St")
      v2 = described_class.new(name: "ACL Live", address: "200 Congress Ave")
      expect(v1).not_to eq(v2)
    end

    it "returns false for non-Venue objects" do
      expect(venue).not_to eq("not a venue")
      expect(venue).not_to eq(nil)
    end

    it "compares using name, address, city, and state only" do
      v1 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX", zip: "78701")
      v2 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX", zip: "78702")
      expect(v1).to eq(v2)
    end
  end

  describe "#eql?" do
    it "is an alias for ==" do
      v1 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX")
      v2 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX")
      expect(v1.eql?(v2)).to be true
    end
  end

  describe "#hash" do
    it "returns same hash for equivalent venues" do
      v1 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX")
      v2 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX")
      expect(v1.hash).to eq(v2.hash)
    end

    it "returns different hash for different venues" do
      v1 = described_class.new(name: "Test", address: "123 Main", city: "Austin", state: "TX")
      v2 = described_class.new(name: "Test", address: "456 Oak", city: "Austin", state: "TX")
      expect(v1.hash).not_to eq(v2.hash)
    end
  end

  describe "validation" do
    it "requires name" do
      venue = described_class.new(name: "")
      expect(venue).not_to be_valid
      expect(venue.errors[:name]).to include("can't be blank")
    end

    it "requires name with whitespace only" do
      venue = described_class.new(name: "   ")
      expect(venue).not_to be_valid
    end

    it "validates state is a valid US state code" do
      venue = described_class.new(name: "Test", state: "ZZ")
      expect(venue).not_to be_valid
      expect(venue.errors[:state]).to include("is not included in the list")
    end

    it "allows valid state codes" do
      venue = described_class.new(name: "Test", state: "CA")
      expect(venue).to be_valid
    end

    it "allows nil state" do
      venue = described_class.new(name: "Test", state: nil)
      expect(venue).to be_valid
    end

    it "allows empty state" do
      venue = described_class.new(name: "Test", state: "")
      expect(venue).to be_valid
    end
  end

  describe "state default" do
    it "defaults to TX" do
      venue = described_class.new(name: "Test")
      expect(venue.state).to eq("TX")
    end

    it "normalizes state to uppercase" do
      venue = described_class.new(name: "Test", state: "tx")
      expect(venue.state).to eq("TX")
    end
  end

  describe "initialization" do
    it "strips whitespace from name" do
      venue = described_class.new(name: "  Test Venue  ")
      expect(venue.name).to eq("Test Venue")
    end

    it "strips whitespace from address" do
      venue = described_class.new(name: "Test", address: "  123 Main St  ")
      expect(venue.address).to eq("123 Main St")
    end

    it "strips whitespace from city" do
      venue = described_class.new(name: "Test", city: "  Austin  ")
      expect(venue.city).to eq("Austin")
    end

    it "strips whitespace from zip" do
      venue = described_class.new(name: "Test", zip: "  78701  ")
      expect(venue.zip).to eq("78701")
    end

    it "strips whitespace from website" do
      venue = described_class.new(name: "Test", website: "  https://example.com  ")
      expect(venue.website).to eq("https://example.com")
    end

    it "strips whitespace from phone" do
      venue = described_class.new(name: "Test", phone: "  555-1234  ")
      expect(venue.phone).to eq("555-1234")
    end

    it "strips whitespace from url" do
      venue = described_class.new(name: "Test", url: "  https://example.com  ")
      expect(venue.url).to eq("https://example.com")
    end
  end

  describe "with factories" do
    it "creates a venue via factory" do
      venue = build(:venue)
      expect(venue.name).not_to be_empty
      expect(venue.city).to eq("Austin")
      expect(venue.state).to eq("TX")
    end

    it "creates an austin_venue via factory" do
      venue = build(:austin_venue)
      expect(venue.city).to eq("Austin")
      expect(venue.state).to eq("TX")
      expect(venue.zip).to eq("78701")
    end
  end
end
