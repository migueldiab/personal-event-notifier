# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Core::Config do
  describe ".load" do
    it "returns defaults when no path is provided" do
      config = described_class.load
      expect(config.telegram_channel_id).to eq("")
      expect(config.lookahead_days).to eq(7)
      expect(config.time_zone).to eq("America/Chicago")
    end
  end

  describe "#interests" do
    it "includes all target events" do
      config = described_class.load
      expect(config.interests).to include("Oscars")
      expect(config.interests).to include("SXSW")
      expect(config.interests).to include("Olympics")
      expect(config.interests).to include("Oktoberfest")
    end
  end
end
