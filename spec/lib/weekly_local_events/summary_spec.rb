# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Summary do
  describe "#events" do
    it "exposes the aggregated events from the run" do
      events = [instance_double(WeeklyLocalEvents::Event), instance_double(WeeklyLocalEvents::Event)]

      summary = described_class.new(total: 2, sources: { "alpha" => 2 }, events: events)

      expect(summary.events).to eq(events)
    end

    it "defaults to an empty event list" do
      expect(described_class.new(total: 0, sources: {}).events).to eq([])
    end
  end

  describe "#to_h" do
    it "includes the events alongside the counts" do
      events = [instance_double(WeeklyLocalEvents::Event)]
      summary = described_class.new(total: 1, sources: { "alpha" => 1 }, events: events)

      expect(summary.to_h).to eq(total: 1, sources: { "alpha" => 1 }, events: events)
    end
  end
end
