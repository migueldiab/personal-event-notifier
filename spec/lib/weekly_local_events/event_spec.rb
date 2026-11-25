# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Event do
  subject(:event) { described_class.new(title: "Test Event", date: "2026-12-01", venue: venue, url: "https://example.com", source: "test") }

  let(:venue) { WeeklyLocalEvents::Venue.new(name: "Test Venue") }

  describe "#free?" do
    context "when price is nil" do
      it "returns false" do
        expect(event).not_to be_free
      end
    end

    context "when price is 0" do
      let(:event) { described_class.new(title: "Free Event", date: "2026-12-01", venue: venue, url: "https://example.com", source: "test", price: 0) }
      it "returns true" do
        expect(event).to be_free
      end
    end

    context "when price is a string 'free'" do
      let(:event) { described_class.new(title: "Free Event", date: "2026-12-01", venue: venue, url: "https://example.com", source: "test", price: "free") }
      it "returns true" do
        expect(event).to be_free
      end
    end

    context "when price is a number" do
      let(:event) { described_class.new(title: "Paid Event", date: "2026-12-01", venue: venue, url: "https://example.com", source: "test", price: 25.00) }
      it "returns false" do
        expect(event).not_to be_free
      end
    end
  end
end
