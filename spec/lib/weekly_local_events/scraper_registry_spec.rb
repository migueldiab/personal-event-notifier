# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe WeeklyLocalEvents::ScraperRegistry do
  subject(:registry) { described_class.new(config) }

  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:config) { double("config", sites: [], logger: logger) }

  let(:alpha_url) { "https://example.com/alpha" }
  let(:beta_url) { "https://example.com/beta" }
  let(:alpha_events) { [build(:event)] }
  let(:beta_events) { [build(:event)] }

  let(:alpha_class) do
    build(
      :test_scraper_class,
      scraper_name: "alpha",
      scraper_events: alpha_events,
      scraper_url: alpha_url
    )
  end
  let(:beta_class) do
    build(
      :test_scraper_class,
      scraper_name: "beta",
      scraper_events: beta_events,
      scraper_url: beta_url
    )
  end
  let(:failing_class) do
    Class.new(WeeklyLocalEvents::BaseScraper) do
      define_method(:name) { "failing" }
      define_method(:events) { raise StandardError, "scraper exploded" }
    end
  end

  before do
    # The shared :event factory uses Faker; "en_US" (suite default) is not a
    # valid locale for the installed Faker version, so select :en locally.
    Faker::Config.locale = :en

    # #initialize auto-registers the real scrapers; keep each example isolated.
    registry.scraper_classes.clear

    stub_request(:get, alpha_url)
      .to_return(status: 200, body: "<html><body>alpha events</body></html>")
    stub_request(:get, beta_url)
      .to_return(status: 200, body: "<html><body>beta events</body></html>")
  end

  describe "#register" do
    it "adds the scraper class under the given name" do
      registry.register("alpha", alpha_class)

      expect(registry.scraper_classes).to eq("alpha" => alpha_class)
    end

    it "rejects a class that is not a BaseScraper subclass" do
      expect { registry.register("invalid", Class.new) }
        .to raise_error(ArgumentError, /not a subclass of BaseScraper/)
    end
  end

  describe "#register_all" do
    it "discovers and registers every scraper listed in KNOWN_SCRAPERS" do
      stub_const(
        "WeeklyLocalEvents::ScraperRegistry::KNOWN_SCRAPERS",
        "alpha" => "SpecAlphaScraper",
        "beta" => "SpecBetaScraper"
      )
      stub_const("SpecAlphaScraper", alpha_class)
      stub_const("SpecBetaScraper", beta_class)

      registry.register_all

      expect(registry.scraper_classes).to eq(
        "alpha" => alpha_class, "beta" => beta_class
      )
    end

    it "silently skips scraper constants that are not defined" do
      stub_const(
        "WeeklyLocalEvents::ScraperRegistry::KNOWN_SCRAPERS",
        "alpha" => "SpecAlphaScraper",
        "missing" => "NoSuchScraperConstant"
      )
      stub_const("SpecAlphaScraper", alpha_class)

      registry.register_all

      expect(registry.scraper_classes.keys).to eq(["alpha"])
    end
  end

  describe "#get" do
    let!(:registration) { registry.register("alpha", alpha_class) }

    it "returns an instance of the scraper registered under the name" do
      expect(registry.get("alpha")).to be_an_instance_of(alpha_class)
    end

    it "accepts a symbol as the scraper name" do
      expect(registry.get(:alpha)).to be_an_instance_of(alpha_class)
    end

    it "raises NotFoundError when the name is not registered" do
      expect { registry.get("unknown") }
        .to raise_error(WeeklyLocalEvents::NotFoundError, /not registered/)
    end
  end

  describe "#all" do
    let!(:alpha_registration) { registry.register("alpha", alpha_class) }
    let!(:beta_registration) { registry.register(:beta, beta_class) }

    it "returns an instance for every registered scraper" do
      expect(registry.all.map(&:name)).to contain_exactly("alpha", "beta")
    end
  end

  describe "#active" do
    let(:config) { double("config", sites: %w[alpha], logger: logger) }
    let!(:alpha_registration) { registry.register("alpha", alpha_class) }
    let!(:beta_registration) { registry.register("beta", beta_class) }

    it "returns only scrapers enabled in config.sites" do
      expect(registry.active.map(&:name)).to eq(["alpha"])
    end

    it "returns all scrapers when no sites are configured" do
      allow(config).to receive(:sites).and_return([])

      expect(registry.active.map(&:name)).to contain_exactly("alpha", "beta")
    end

    context "when config exposes enabled_scrapers" do
      let(:config) do
        double("config", enabled_scrapers: [:beta], sites: %w[alpha], logger: logger)
      end

      it "prefers enabled_scrapers over sites" do
        expect(registry.active.map(&:name)).to eq(["beta"])
      end
    end

    context "when config exposes neither sites nor enabled_scrapers" do
      let(:config) { double("config", logger: logger) }

      it "treats every registered scraper as active" do
        expect(registry.active.map(&:name)).to contain_exactly("alpha", "beta")
      end
    end

    context "when config is nil" do
      subject(:registry) { described_class.new(nil) }

      it "treats every registered scraper as active" do
        registry.register("alpha", alpha_class)
        registry.register("beta", beta_class)

        expect(registry.active.map(&:name)).to contain_exactly("alpha", "beta")
      end
    end
  end

  describe "#run" do
    let!(:registration) { registry.register("alpha", alpha_class) }

    it "runs the named scraper and returns its events" do
      expect(registry.run("alpha")).to eq(alpha_events)
      expect(WebMock).to have_requested(:get, alpha_url)
    end

    it "raises NotFoundError for an unknown scraper name" do
      expect { registry.run("does_not_exist") }
        .to raise_error(WeeklyLocalEvents::NotFoundError, /not registered/)
    end

    it "returns an empty array when the scraper raises at runtime" do
      registry.register("failing", failing_class)

      expect(registry.run("failing")).to eq([])
      expect(logger).to have_received(:error).with(/failed/)
    end
  end

  describe "#run_all" do
    let!(:alpha_registration) { registry.register("alpha", alpha_class) }
    let!(:beta_registration) { registry.register("beta", beta_class) }

    it "runs every registered scraper and merges the results" do
      expect(registry.run_all).to eq(alpha_events + beta_events)
      expect(WebMock).to have_requested(:get, alpha_url)
      expect(WebMock).to have_requested(:get, beta_url)
    end

    it "handles scraper failures gracefully and keeps the remaining results" do
      registry.register("failing", failing_class)

      expect(registry.run_all).to eq(alpha_events + beta_events)
      expect(logger).to have_received(:error).with(/failed/)
    end
  end

  describe "#run_active" do
    let(:config) { double("config", sites: %w[alpha], logger: logger) }
    let!(:alpha_registration) { registry.register("alpha", alpha_class) }
    let!(:beta_registration) { registry.register("beta", beta_class) }

    it "runs only the active scrapers and merges their results" do
      expect(registry.run_active).to eq(alpha_events)
      expect(WebMock).to have_requested(:get, alpha_url)
      expect(WebMock).not_to have_requested(:get, beta_url)
    end
  end

  describe "Visit Cedar Park registration" do
    let(:registered_names) { described_class::KNOWN_SCRAPERS.keys }

    it "maps visit_cedar_park to the VisitCedarParkScraper class" do
      expect(described_class::KNOWN_SCRAPERS["visit_cedar_park"])
        .to eq("WeeklyLocalEvents::Scrapers::VisitCedarParkScraper")
    end

    it "lists visit_cedar_park in DEFAULT_SCRAPERS" do
      expect(described_class::DEFAULT_SCRAPERS).to include("visit_cedar_park")
    end

    it "includes visit_cedar_park in #all" do
      expect(described_class.new(nil).all.map(&:name)).to include("visit_cedar_park")
    end

    it "includes visit_cedar_park in #active when config lists it" do
      enabled = double("config", enabled_scrapers: %w[visit_cedar_park], logger: logger)

      expect(described_class.new(enabled).active.map(&:name)).to include("visit_cedar_park")
    end

    it "keeps visit_cedar_park and cedar_park distinct with no duplicate names" do
      expect(registered_names).to eq(registered_names.uniq)
      expect(registered_names).to include("visit_cedar_park")
      expect(registered_names).to include("cedar_park")
    end
  end

  describe "Cedar Park registration" do
    let(:registered_names) { described_class::KNOWN_SCRAPERS.keys }

    it "maps cedar_park to the CedarParkScraper class" do
      expect(described_class::KNOWN_SCRAPERS["cedar_park"])
        .to eq("WeeklyLocalEvents::Scrapers::CedarParkScraper")
    end

    it "lists cedar_park in DEFAULT_SCRAPERS" do
      expect(described_class::DEFAULT_SCRAPERS).to include("cedar_park")
    end

    it "includes cedar_park in #all" do
      expect(described_class.new(nil).all.map(&:name)).to include("cedar_park")
    end

    it "includes cedar_park in #active when config lists it" do
      enabled = double("config", enabled_scrapers: %w[cedar_park], logger: logger)

      expect(described_class.new(enabled).active.map(&:name)).to include("cedar_park")
    end

    it "registers cedar_park exactly once with no duplicate names" do
      expect(registered_names.count("cedar_park")).to eq(1)
      expect(registered_names).to eq(registered_names.uniq)
    end
  end
end
