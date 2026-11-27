# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Application do
  describe "#run" do
    it "scrapes each source exactly once and builds summary counts from that pass" do
      call_counts = Hash.new(0)
      logger = instance_double(Logger, info: nil, warn: nil, error: nil)
      config = instance_double(WeeklyLocalEvents::Config, logger: logger)

      alpha_events = Array.new(2) { instance_double(WeeklyLocalEvents::Event, source: "alpha") }
      beta_events = Array.new(1) { instance_double(WeeklyLocalEvents::Event, source: "beta") }

      scraper_class = lambda do |name, events|
        Class.new(WeeklyLocalEvents::BaseScraper) do
          define_method(:name) { name }
          define_method(:config) { config }

          define_method(:events) do
            call_counts[name] += 1
            config.logger.warn("Rate limited: #{name}")
            events
          end
        end
      end

      alpha = scraper_class.call("alpha", alpha_events).new({})
      beta = scraper_class.call("beta", beta_events).new({})

      # `all` mirrors the active set: the old result_counts path scraped these
      # same instances a second time just to build the per-source hash.
      registry = instance_double(
        WeeklyLocalEvents::ScraperRegistry,
        active: [alpha, beta],
        all: [alpha, beta]
      )
      aggregator = instance_double(
        WeeklyLocalEvents::Aggregator,
        aggregate: alpha_events + beta_events
      )
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

    it "builds source counts from aggregated events so total equals their sum" do
      config = instance_double(WeeklyLocalEvents::Config, logger: nil)
      alpha_events = Array.new(3) { instance_double(WeeklyLocalEvents::Event, source: "alpha") }
      beta_events = Array.new(2) { instance_double(WeeklyLocalEvents::Event, source: "beta") }

      stub_scraper = lambda do |name, events|
        Class.new(WeeklyLocalEvents::BaseScraper) do
          define_method(:name) { name }
          define_method(:events) { events }
        end.new({})
      end

      registry = instance_double(
        WeeklyLocalEvents::ScraperRegistry,
        active: [stub_scraper.call("alpha", alpha_events), stub_scraper.call("beta", beta_events)]
      )
      # Dedup/date filtering keeps 2 of the 3 alpha and 1 of the 2 beta events.
      aggregated = alpha_events.first(2) + beta_events.first(1)
      aggregator = instance_double(WeeklyLocalEvents::Aggregator, aggregate: aggregated)
      allow(WeeklyLocalEvents::ScraperRegistry).to receive(:new).and_return(registry)
      allow(WeeklyLocalEvents::Aggregator).to receive(:new).and_return(aggregator)
      allow(WeeklyLocalEvents::Notifier).to receive(:new)

      summary = described_class.new(config).run(dry_run: true)

      expect(summary.sources).to eq("alpha" => 2, "beta" => 1)
      expect(summary.total).to eq(3)
      expect(summary.total).to eq(summary.sources.values.sum)
      expect(summary.to_h[:total]).to eq(summary.to_h[:sources].values.sum)
    end

    it "returns a summary carrying the aggregated events" do
      config = instance_double(WeeklyLocalEvents::Config, logger: nil)
      events = Array.new(2) { instance_double(WeeklyLocalEvents::Event, source: "alpha") }
      stub_scraper = Class.new(WeeklyLocalEvents::BaseScraper) do
        define_method(:name) { "alpha" }
        define_method(:events) { events }
      end.new({})

      registry = instance_double(
        WeeklyLocalEvents::ScraperRegistry,
        active: [stub_scraper]
      )
      aggregator = instance_double(WeeklyLocalEvents::Aggregator, aggregate: events)
      allow(WeeklyLocalEvents::ScraperRegistry).to receive(:new).and_return(registry)
      allow(WeeklyLocalEvents::Aggregator).to receive(:new).and_return(aggregator)
      allow(WeeklyLocalEvents::Notifier).to receive(:new)

      summary = described_class.new(config).run(dry_run: true)

      expect(summary.events).to eq(events)
    end
  end

  describe "notification and config wiring" do
    let(:config) { instance_double(WeeklyLocalEvents::Config, logger: nil) }
    let(:events) { [instance_double(WeeklyLocalEvents::Event, source: "alpha")] }
    let(:registry) { instance_double(WeeklyLocalEvents::ScraperRegistry, active: []) }
    let(:aggregator) { instance_double(WeeklyLocalEvents::Aggregator, aggregate: events) }
    let(:notifier) { instance_double(WeeklyLocalEvents::Notifier, notify: nil) }

    before do
      allow(WeeklyLocalEvents::ScraperRegistry).to receive(:new).and_return(registry)
      allow(WeeklyLocalEvents::Aggregator).to receive(:new).and_return(aggregator)
      allow(WeeklyLocalEvents::Notifier).to receive(:new).and_return(notifier)
    end

    it "sends aggregated events to the notifier when notify: true and dry_run: false" do
      described_class.new(config).run(dry_run: false, notify: true)

      expect(notifier).to have_received(:notify).with(events).once
    end

    it "never sends when dry_run: true, even if notify: true" do
      described_class.new(config).run(dry_run: true, notify: true)

      expect(notifier).not_to have_received(:notify)
    end

    it "passes config into Aggregator.new so --days overrides are honoured" do
      described_class.new(config).run(dry_run: true, notify: false)

      expect(WeeklyLocalEvents::Aggregator).to have_received(:new).with(config).once
    end
  end
end
