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
end
