# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::BaseScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }

  describe "#name" do
    it "returns the class name" do
      expect(scraper.name).to eq("BaseScraper")
    end
  end

  describe "#scrape" do
    it "raises NotImplementedError" do
      expect { scraper.scrape }.to raise_error(NotImplementedError)
    end
  end
end
