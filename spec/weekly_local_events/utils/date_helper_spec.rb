# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Utils::DateHelper do
  describe ".next_week_start" do
    it "returns the beginning of the current week" do
      result = described_class.next_week_start
      expect(result).to be_a(Time)
    end
  end

  describe ".format_for_telegram" do
    it "formats a date for Telegram display" do
      date = Time.new(2027, 3, 7, 20, 0, 0, "-06:00")
      result = described_class.format_for_telegram(date)
      expect(result).to include("March")
      expect(result).to include("7")
    end

    it "returns N/A for nil" do
      expect(described_class.format_for_telegram(nil)).to eq("N/A")
    end
  end
end
