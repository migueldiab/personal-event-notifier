# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::HeadlessBrowserFetcher do
  describe "#call" do
    it "renders the page in headless Chromium with stealth flags and headers" do
      captured_args = nil
      fetcher = described_class.new(
        binary: "/usr/bin/chromium",
        runner: lambda { |*args|
          captured_args = args
          ["<html>rendered</html>", "", ""]
        }
      )
      fetcher.call("https://example.com/calendar")

      expect(captured_args).to include("--headless=new")
      expect(captured_args).to include("--disable-blink-features=AutomationControlled")
      expect(captured_args).to include(a_string_starting_with("--user-agent=Mozilla/5.0"))
      expect(captured_args).to include("https://example.com/calendar")
    end

    it "returns the rendered HTML when the browser succeeds" do
      fetcher = described_class.new(
        binary: "/usr/bin/chromium",
        runner: ->(*_args) { ["<html>rendered</html>", "", ""] }
      )

      expect(fetcher.call("https://example.com/calendar")).to eq("<html>rendered</html>")
    end

    it "returns nil with a warning when no browser binary is available" do
      logger = instance_double(Logger, warn: nil)
      fetcher = described_class.new(binary: nil, logger: logger)

      expect(fetcher.call("https://example.com/calendar")).to be_nil
      expect(logger).to have_received(:warn).with(/headless browser/)
    end
  end
end
