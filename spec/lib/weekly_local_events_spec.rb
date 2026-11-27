# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"

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

  describe ".VERSION" do
    it "returns the correct version string" do
      expect(described_class::VERSION).to eq("0.1.0")
    end
  end

  describe ".Error" do
    it "is a StandardError subclass" do
      expect(described_class::Error).to be < StandardError
    end
  end

  describe ".ScraperError" do
    it "is an Error subclass" do
      expect(described_class::ScraperError).to be < described_class::Error
    end
  end

  describe ".NotFoundError" do
    it "is a ScraperError subclass" do
      expect(described_class::NotFoundError).to be < described_class::ScraperError
    end
  end

  describe ".ParseError" do
    it "is a ScraperError subclass" do
      expect(described_class::ParseError).to be < described_class::ScraperError
    end
  end

  describe ".RateLimitError" do
    it "is a ScraperError subclass" do
      expect(described_class::RateLimitError).to be < described_class::ScraperError
    end
  end

  describe "error hierarchy chain" do
    it "is correct: NotFoundError/ParseError/RateLimitError < ScraperError < Error < StandardError" do
      expect(described_class::NotFoundError.ancestors).to include(described_class::ScraperError)
      expect(described_class::NotFoundError.ancestors).to include(described_class::Error)
      expect(described_class::NotFoundError.ancestors).to include(StandardError)

      expect(described_class::ParseError.ancestors).to include(described_class::ScraperError)
      expect(described_class::ParseError.ancestors).to include(described_class::Error)
      expect(described_class::ParseError.ancestors).to include(StandardError)

      expect(described_class::RateLimitError.ancestors).to include(described_class::ScraperError)
      expect(described_class::RateLimitError.ancestors).to include(described_class::Error)
      expect(described_class::RateLimitError.ancestors).to include(StandardError)
    end
  end

  describe "scraper registration and active selection" do
    let(:configured) do
      %w[
        austin_chronicle do512 community_impact eventbrite_austin
        acl_live stubbss paramount_austin
      ]
    end
    let(:config_file) { Tempfile.new(["config", ".yml"]) }

    after { config_file.close! }

    it "registers every known scraper and activates only the configured sources" do
      File.write(config_file.path, {
        "notification_channel_id" => "-1004330304115",
        "telegram_bot_token" => "123456:ABC-DEF",
        "enabled_scrapers" => configured,
      }.to_yaml)
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path)
        .with("~/.hermes/weekly_local_events/config.yml")
        .and_return(config_file.path)

      config = WeeklyLocalEvents::Config.new
      registry = WeeklyLocalEvents::ScraperRegistry.new(config)

      expect(registry.all.size).to be >= 7
      expect(registry.active.map(&:name)).to contain_exactly(*configured)
    end
  end

  describe ".run" do
    it "builds the Application with only the config and returns its Summary" do
      summary = WeeklyLocalEvents::Summary.new(total: 3, sources: { "do512" => 3 })
      app = instance_double(WeeklyLocalEvents::Application, run: summary)

      expect(WeeklyLocalEvents::Application).to receive(:new)
        .with(described_class.config).once.and_return(app)

      expect(described_class.run).to be(summary)
    end
  end
end
