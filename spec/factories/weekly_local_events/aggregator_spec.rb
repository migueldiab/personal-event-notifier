# frozen_string_literal: true

require "spec_helper"

# FactoryBot.find_definitions loads every .rb under spec/factories, including
# this spec. Guard against registering the examples a second time.
return if defined?(AGGREGATOR_FACTORIES_SPEC_LOADED)

AGGREGATOR_FACTORIES_SPEC_LOADED = true

RSpec.describe "Aggregator factories" do
  describe "price factory" do
    it "builds a paid price with realistic attributes" do
      price = build(:price)

      expect(price.amount).to be_a(Float)
      expect(price.currency).to eq("USD")
      expect(price.display).to eq("$10.00")
      expect(price.is_free).to be(false)
      expect(price.to_s).to eq(price.display)
    end

    it "builds free, premium, and euro variants" do
      expect(build(:free_price)).to have_attributes(display: "Free", is_free: true, amount: 0.0)
      expect(build(:premium_price)).to have_attributes(display: "$45.00", is_free: false)
      expect(build(:euro_price)).to have_attributes(display: "€5.00", currency: "EUR")
    end
  end

  describe "venue factory" do
    it "builds a geocoded Austin venue" do
      venue = build(:venue)

      expect(venue).to be_a(WeeklyLocalEvents::Venue)
      expect(venue).to be_valid
      expect(venue.city).to eq("Austin")
      expect(venue.state).to eq("TX")
      expect(venue.lat).to be_a(Float)
      expect(venue.lng).to be_a(Float)
      expect(venue).to be_geocoded
    end

    it "builds distinct city and ungeocoded variants" do
      expect(build(:austin_venue).zip).to eq("78701")
      expect(build(:dallas_venue).city).to eq("Dallas")
      expect(build(:ungeocoded_venue)).not_to be_geocoded
    end
  end

  describe "event factory" do
    let(:aggregator) { WeeklyLocalEvents::Aggregator.new }

    it "builds a valid event with a future date and associated venue and price" do
      event = build(:event)

      expect(event).to be_a(WeeklyLocalEvents::Event)
      expect(event).to be_valid
      expect(event.title).to include("Live Jazz Night")
      expect(event.date).to be > Date.today
      expect(event.venue).to be_a(WeeklyLocalEvents::Venue)
      expect(event.price).to eq("$10.00")
      expect(event.source).to eq("EventBrite")
    end

    it "builds free and paid variants" do
      free_event = build(:free_event)
      paid_event = build(:paid_event)

      expect(free_event.price).to eq("Free")
      expect(free_event).to be_free
      expect(paid_event.price).to eq("$45.00")
      expect(paid_event.source).to eq("Do512")
    end

    it "builds events with distinct dedup keys for deduplication tests" do
      keys = Array.new(3) { build(:event) }.map { |event| aggregator.dedup_key(event) }

      expect(keys.uniq.size).to eq(3)
    end

    it "builds a duplicate with the same dedup key as the original" do
      original = build(:event)
      duplicate = build(:duplicate_event, original: original)

      expect(aggregator.dedup_key(duplicate)).to eq(aggregator.dedup_key(original))
      expect(duplicate.title).not_to eq(original.title)
    end

    it "builds past events for date-range tests" do
      expect(build(:past_event).date).to be < Date.today
    end

    it "honors caller-supplied attribute overrides" do
      event = build(:event, title: "Custom Title", price: "$12.50", source: "Do512")

      expect(event.title).to eq("Custom Title")
      expect(event.price).to eq("$12.50")
      expect(event.source).to eq("Do512")
    end
  end
end
