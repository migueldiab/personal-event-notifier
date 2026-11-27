# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Application do
  describe "#run" do
    it "scrapes each source exactly once and builds summary counts from that pass" do
      call_counts = Hash.new(0)
      logger = instance_double(Logger, info: nil, warn: nil, error: nil)
      config = instance_double(WeeklyLocalEvents::Config, logger: logger)

      scraper_class = lambda do |name, event_count|
        Class.new(WeeklyLocalEvents::BaseScraper) do
          define_method(:name) { name }
          define_method(:config) { config }

          define_method(:events) do
            call_counts[name] += 1
            config.logger.warn("Rate limited: #{name}")
            Array.new(event_count) { "event-#{name}" }
          end
        end
      end

      alpha = scraper_class.call("alpha", 2).new({})
      beta = scraper_class.call("beta", 1).new({})

      # `all` mirrors the active set: the old result_counts path scraped these
      # same instances a second time just to build the per-source hash.
      registry = instance_double(
        WeeklyLocalEvents::ScraperRegistry,
        active: [alpha, beta],
        all: [alpha, beta]
      )
      aggregator = instance_double(WeeklyLocalEvents::Aggregator, aggregate: [])
      allow(WeeklyLocalEvents::ScraperRegistry).to receive(:new).and_return(registry)
      allow(WeeklyLocalEvents::Aggregator).to receive(:new).and_return(aggregator)
      allow(WeeklyLocalEvents::Notifier).to receive(:new)
        .and_return(instance_double(WeeklyLocalEvents::Notifier))

      summary = described_class.new(config).run(dry_run: true)

      expect(call_counts).to eq("alpha" => 1, "beta" => 1)
      expect(summary.sources).to eq("alpha" => 2, "beta" => 1)
      expect(logger).to have_received(:warn).with("Rate limited: alpha").once
      expect(logger).to have_received(:warn).with("Rate limited: beta").once
    end
  end
end
