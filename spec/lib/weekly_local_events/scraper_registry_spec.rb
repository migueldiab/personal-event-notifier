# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::ScraperRegistry do
  subject(:registry) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }

  describe "#all" do
    it "returns an array of scraper instances" do
      expect(registry.all).to be_an(Array)
    end
  end

  describe "Stubb's scraper registration" do
    it "lists stubbss among the default scrapers" do
      expect(described_class::DEFAULT_SCRAPERS).to include("stubbss")
    end

    it "maps stubbss to StubbssScraper in KNOWN_SCRAPERS" do
      expect(described_class::KNOWN_SCRAPERS["stubbss"]).to eq(
        "WeeklyLocalEvents::Scrapers::StubbssScraper"
      )
    end

    it "registers stubbss from the known scrapers list" do
      expect(registry.scraper_classes).to have_key("stubbss")
    end

    it "instantiates a scraper that responds to events from the registry lookup" do
      scraper = registry.get("stubbss")

      expect(scraper).to be_a(WeeklyLocalEvents::Scrapers::StubbssScraper)
      expect(scraper).to respond_to(:events)
    end
  end
end
