# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Aggregator do
  subject(:aggregator) { described_class.new }

  describe "#aggregate" do
    context "with duplicate events" do
      let(:events) do
        [
          WeeklyLocalEvents::Event.new(title: "Event A", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Venue X"), url: "https://example.com", source: "test"),
          WeeklyLocalEvents::Event.new(title: "Event A", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Venue X"), url: "https://example.com", source: "test"),
          WeeklyLocalEvents::Event.new(title: "Event B", date: "2026-12-02", venue: WeeklyLocalEvents::Venue.new(name: "Venue Y"), url: "https://example.com", source: "test"),
        ]
      end

      it "deduplicates by title, date, venue, and url" do
        result = aggregator.aggregate(events)
        expect(result.size).to eq(2)
        expect(result.map(&:title)).to match_array(["Event A", "Event B"])
      end
    end

    context "with no events" do
      it "returns empty array" do
        expect(aggregator.aggregate([])).to eq([])
      end
    end
  end
end
