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

    it "returns nil for non-hash input" do
      expect(described_class.from_hash(nil)).to be_nil
      expect(described_class.from_hash("string")).to be_nil
    end

    it "handles string keys" do
      hash = { "name" => "ACL Live", "address" => "310 W 5th St", "city" => "Austin" }
      venue = described_class.from_hash(hash)
      expect(venue.name).to eq("ACL Live")
    end
  end

  describe "#geocode!" do
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
    end
  end

  describe "#distance_from" do
    it "calculates distance in miles" do
      venue = described_class.new(name: "ACL Live", city: "Austin", lat: 30.2672, lng: -97.7431)
      distance = venue.distance_from(32.7767, -96.7970)
      expect(distance).to be_within(1).of(182.0)
    end

    it "raises ArgumentError for non-numeric lat" do
      venue = described_class.new(name: "Test", lat: 30.0, lng: -97.0)
      expect { venue.distance_from("not a number", 0) }
        .to raise_error(ArgumentError, /lat must be numeric/)
    end

    it "raises ArgumentError when coordinates not set" do
      venue = described_class.new(name: "Test")
      expect { venue.distance_from(30.0, -97.0) }
        .to raise_error(ArgumentError, /Venue coordinates must be set/)
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
  end

  describe "validation" do
    it "requires name" do
      venue = described_class.new(name: "")
      expect(venue).not_to be_valid
      expect(venue.errors[:name]).to include("can't be blank")
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
  end

  describe "state default" do
    it "defaults to TX" do
      venue = described_class.new(name: "Test")
      expect(venue.state).to eq("TX")
    end
  end
end
