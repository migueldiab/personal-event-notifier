# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents do
  describe ".config" do
    it "returns a Config instance" do
      expect(described_class.config).to be_a(WeeklyLocalEvents::Config)
    end
  end

  describe ".scraper_registry" do
    it "returns a ScraperRegistry instance" do
      expect(described_class.scraper_registry).to be_a(WeeklyLocalEvents::ScraperRegistry)
    end
  end

  describe ".notifier" do
    it "returns a Notifier instance" do
      expect(described_class.notifier).to be_a(WeeklyLocalEvents::Notifier)
    end
  end

  describe ".aggregator" do
    it "returns an Aggregator instance" do
      expect(described_class.aggregator).to be_a(WeeklyLocalEvents::Aggregator)
    end
  end
end
