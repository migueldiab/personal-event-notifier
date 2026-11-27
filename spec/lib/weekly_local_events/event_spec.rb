# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Event do
  let(:venue) { WeeklyLocalEvents::Venue.new(name: "Test Venue", city: "Austin", state: "TX") }
  let(:valid_attributes) do
    {
      title: "Test Concert",
      date: Date.today,
      venue: venue,
      url: "https://example.com/event",
      source: "test",
      price: "$10",
      description: "A test event",
      time: "8:00 PM",
      currency: "USD",
      image_url: "https://example.com/image.jpg",
      category: "music",
      tags: ["rock", "live"],
    }
  end

  describe ".from_hash" do
    it "raises EventParseError when :title is missing" do
      hash = valid_attributes.except(:title)
      expect { described_class.from_hash(hash) }
        .to raise_error(WeeklyLocalEvents::EventParseError, /Missing required fields: title/)
    end

    it "raises EventParseError when :date is missing" do
      hash = valid_attributes.except(:date)
      expect { described_class.from_hash(hash) }
        .to raise_error(WeeklyLocalEvents::EventParseError, /Missing required fields: date/)
    end

    it "raises EventParseError when :venue is missing" do
      hash = valid_attributes.except(:venue)
      expect { described_class.from_hash(hash) }
        .to raise_error(WeeklyLocalEvents::EventParseError, /Missing required fields: venue/)
    end

    it "raises EventParseError when :url is missing" do
      hash = valid_attributes.except(:url)
      expect { described_class.from_hash(hash) }
        .to raise_error(WeeklyLocalEvents::EventParseError, /Missing required fields: url/)
    end

    it "raises EventParseError when :source is missing" do
      hash = valid_attributes.except(:source)
      expect { described_class.from_hash(hash) }
        .to raise_error(WeeklyLocalEvents::EventParseError, /Missing required fields: source/)
    end

    it "creates an Event successfully when all required fields are present" do
      event = described_class.from_hash(valid_attributes)
      expect(event).to be_a(described_class)
      expect(event.title).to eq("Test Concert")
      expect(event.date).to eq(Date.today)
      expect(event.venue).to eq(venue)
      expect(event.url).to eq("https://example.com/event")
      expect(event.source).to eq("test")
      expect(event.price).to eq("$10")
      expect(event.description).to eq("A test event")
      expect(event.time).to eq("8:00 PM")
      expect(event.currency).to eq("USD")
      expect(event.image_url).to eq("https://example.com/image.jpg")
      expect(event.category).to eq("music")
      expect(event.tags).to eq(["rock", "live"])
    end

    it "defaults currency to USD when not provided" do
      hash = valid_attributes.except(:currency)
      event = described_class.from_hash(hash)
      expect(event.currency).to eq("USD")
    end
  end

  describe ".free?" do
    it "returns true when price is 'Free'" do
      event = described_class.new(**valid_attributes.merge(price: "Free"))
      expect(event).to be_free
    end

    it "returns true when price is '0'" do
      event = described_class.new(**valid_attributes.merge(price: "0"))
      expect(event).to be_free
    end

    it "returns false when price is '$10'" do
      event = described_class.new(**valid_attributes.merge(price: "$10"))
      expect(event).not_to be_free
    end

    it "returns false when price is '$10.00'" do
      event = described_class.new(**valid_attributes.merge(price: "$10.00"))
      expect(event).not_to be_free
    end

    it "returns true when price_cents is 0 (explicit)" do
      event = described_class.new(**valid_attributes.merge(price_cents: 0))
      expect(event).to be_free
    end
  end

  describe ".price_cents" do
    it "converts '$10' to 1000 cents" do
      event = described_class.new(**valid_attributes.merge(price: "$10"))
      expect(event.price_cents).to eq(1000)
    end

    it "converts '$10.00' to 1000 cents" do
      event = described_class.new(**valid_attributes.merge(price: "$10.00"))
      expect(event.price_cents).to eq(1000)
    end

    it "converts '$10-50' to 1000 cents (lowest)" do
      event = described_class.new(**valid_attributes.merge(price: "$10-50"))
      expect(event.price_cents).to eq(1000)
    end

    it "returns 0 for 'Free'" do
      event = described_class.new(**valid_attributes.merge(price: "Free"))
      expect(event.price_cents).to eq(0)
    end

    it "returns 0 for '$0'" do
      event = described_class.new(**valid_attributes.merge(price: "$0"))
      expect(event.price_cents).to eq(0)
    end

    it "returns explicit price_cents when set" do
      event = described_class.new(**valid_attributes.merge(price_cents: 5000))
      expect(event.price_cents).to eq(5000)
    end

    it "returns nil when price is empty" do
      event = described_class.new(**valid_attributes.merge(price: ""))
      expect(event.price_cents).to be_nil
    end
  end

  describe ".in_date_range?" do
    let(:event_date) { Date.new(2026, 12, 15) }
    let(:event) { described_class.new(**valid_attributes.merge(date: event_date)) }

    it "returns true when event date is within the range" do
      start_date = Date.new(2026, 12, 10)
      end_date = Date.new(2026, 12, 20)
      expect(event.in_date_range?(start_date, end_date)).to be true
    end

    it "returns false when event date is before the range" do
      start_date = Date.new(2026, 12, 20)
      end_date = Date.new(2026, 12, 31)
      expect(event.in_date_range?(start_date, end_date)).to be false
    end

    it "returns false when event date is after the range" do
      start_date = Date.new(2026, 12, 1)
      end_date = Date.new(2026, 12, 10)
      expect(event.in_date_range?(start_date, end_date)).to be false
    end

    it "returns true when event date matches start boundary exactly" do
      start_date = event_date
      end_date = Date.new(2026, 12, 20)
      expect(event.in_date_range?(start_date, end_date)).to be true
    end

    it "returns true when event date matches end boundary exactly" do
      start_date = Date.new(2026, 12, 10)
      end_date = event_date
      expect(event.in_date_range?(start_date, end_date)).to be true
    end

    it "returns false when event date is nil" do
      nil_event = described_class.new(**valid_attributes.merge(date: nil))
      start_date = Date.new(2026, 12, 10)
      end_date = Date.new(2026, 12, 20)
      expect(nil_event.in_date_range?(start_date, end_date)).to be false
    end
  end

  describe ".to_hash" do
    it "returns a hash with all expected keys" do
      event = described_class.new(**valid_attributes)
      hash = event.to_hash
      expected_keys = %i[title description date time begin_time end_time venue artists price price_cents currency url source image_url category is_free sold_out buy_url tags created_at updated_at]
      expect(hash.keys).to contain_exactly(*expected_keys)
    end

    it "returns values matching original model attributes" do
      event = described_class.new(**valid_attributes)
      hash = event.to_hash
      expect(hash[:title]).to eq(event.title)
      expect(hash[:description]).to eq(event.description)
      expect(hash[:date]).to eq(event.date)
      expect(hash[:time]).to eq(event.time)
      expect(hash[:price]).to eq(event.price)
      expect(hash[:price_cents]).to eq(event.price_cents)
      expect(hash[:currency]).to eq(event.currency)
      expect(hash[:url]).to eq(event.url)
      expect(hash[:source]).to eq(event.source)
      expect(hash[:image_url]).to eq(event.image_url)
      expect(hash[:category]).to eq(event.category)
      expect(hash[:tags]).to eq(event.tags)
      expect(hash[:created_at]).to eq(event.created_at)
      expect(hash[:updated_at]).to eq(event.updated_at)
    end

    it "serializes venue as a hash via venue.to_h" do
      event = described_class.new(**valid_attributes)
      hash = event.to_hash
      expect(hash[:venue]).to be_a(Hash)
    end
  end

  describe ".price_range" do
    it "formats a single price" do
      event = described_class.new(**valid_attributes.merge(price: "$10"))
      expect(event.price_range).to eq("$10")
    end

    it "formats a price range" do
      event = described_class.new(**valid_attributes.merge(price: "$10-50"))
      expect(event.price_range).to eq("$10–$50")
    end

    it "formats a free event" do
      event = described_class.new(**valid_attributes.merge(price: "Free"))
      expect(event.price_range).to eq("Free")
    end

    it "formats a range with 'to' separator" do
      event = described_class.new(**valid_attributes.merge(price: "$10 to $50"))
      expect(event.price_range).to eq("$10–$50")
    end

    it "returns empty string when price is nil and price_cents is nil" do
      event = described_class.new(**valid_attributes.merge(price: nil, price_cents: nil))
      expect(event.price_range).to eq("")
    end
  end

  describe "#==" do
    it "returns true for two events with same title, date, venue, and url" do
      event1 = described_class.new(**valid_attributes)
      event2 = described_class.new(**valid_attributes)
      expect(event1).to eq(event2)
    end

    it "returns false for two events with different titles" do
      event1 = described_class.new(**valid_attributes)
      event2 = described_class.new(**valid_attributes.merge(title: "Different"))
      expect(event1).not_to eq(event2)
    end

    it "returns false when compared to a non-Event object" do
      event = described_class.new(**valid_attributes)
      expect(event).not_to eq("not an event")
    end
  end

  describe "#hash" do
    it "returns the same hash for equal events" do
      event1 = described_class.new(**valid_attributes)
      event2 = described_class.new(**valid_attributes)
      expect(event1.hash).to eq(event2.hash)
    end
  end

  describe "validations" do
    it "is invalid without a title" do
      event = described_class.new(title: "", date: Date.today, venue: venue, url: "https://example.com", source: "test")
      expect(event).not_to be_valid
      expect(event.errors[:title]).to include("can't be blank")
    end

    it "is invalid without a date" do
      event = described_class.new(title: "Test", date: nil, venue: venue, url: "https://example.com", source: "test")
      expect(event).not_to be_valid
      expect(event.errors[:date]).to include("can't be blank")
    end

    it "is invalid without a venue" do
      event = described_class.new(title: "Test", date: Date.today, venue: nil, url: "https://example.com", source: "test")
      expect(event).not_to be_valid
      expect(event.errors[:venue]).to include("can't be blank")
    end

    it "is invalid without a url" do
      event = described_class.new(title: "Test", date: Date.today, venue: venue, url: "", source: "test")
      expect(event).not_to be_valid
      expect(event.errors[:url]).to include("can't be blank")
    end

    it "is invalid without a source" do
      event = described_class.new(title: "Test", date: Date.today, venue: venue, url: "https://example.com", source: "")
      expect(event).not_to be_valid
      expect(event.errors[:source]).to include("can't be blank")
    end

    it "is invalid with a negative price_cents" do
      event = described_class.new(title: "Test", date: Date.today, venue: venue, url: "https://example.com", source: "test", price_cents: -100)
      expect(event).not_to be_valid
      expect(event.errors[:price_cents]).to include("must be non-negative")
    end
  end
end
