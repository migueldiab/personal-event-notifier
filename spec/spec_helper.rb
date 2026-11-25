# frozen_string_literal: true

# SimpleCov coverage reporting
require "simplecov"
SimpleCov.start

# Core application
require "weekly_local_events"
require "weekly_local_events/pipeline/engine"
require "weekly_local_events/pipeline/normalizer"
require "weekly_local_events/pipeline/crawler_engine"
require "weekly_local_events/notifications/dispatcher"
require "weekly_local_events/utils/date_helper"

# FactoryBot for test object creation
require "factory_bot_rails"
require "faker"

# WebMock to disable network connections
require "webmock/rspec"

# Load support files if needed (load individually in spec files)
# Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

# FactoryBot configuration
FactoryBot.define do
  factory :event, class: "WeeklyLocalEvents::Event" do
    title { Faker::Lorem.sentence(word_count: 3) }
    description { Faker::Lorem.paragraph(sentence_count: 2) }
    date { Faker::Time.between(from: Date.today, to: Date.today + 30) }
    time { "19:00" }
    venue { association(:venue) }
    price { Faker::Number.between(from: 0, to: 15000).to_s }
    url { "https://example.com/event" }
    source { "austin_chronicle" }
    tags { [Faker::Lorem.word, Faker::Lorem.word] }
  end

  factory :venue, class: "WeeklyLocalEvents::Venue" do
    name { Faker::Company.name }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    state { "TX" }
    zip { Faker::Address.zip_code }
    phone { Faker::PhoneNumber.phone_number }
    url { "https://#{Faker::Internet.domain_name}" }
  end

  factory :base_scraper, class: "WeeklyLocalEvents::BaseScraper" do
    name { "test_scraper" }
    base_url { "https://example.com" }
    date_range { WeeklyLocalEvents::DateRange.from_days(7) }
    config { WeeklyLocalEvents::Config.new }
  end
end

# Faker locale
Faker::Config.locale = :en

# RSpec configuration
RSpec.configure do |config|
  # Enable flags for cleaner test output
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Run tests in random order to catch order-dependent bugs
  config.order = :random

  # Seed the random number generator for reproducibility
  Kernel.srand config.seed

  # Shared examples for scraper tests
  config.define_derived_metadata(file_path: %r{/spec/lib/weekly_local_events/scrapers/}) do |metadata|
    metadata[:type] = :scraper
  end

  # Shared contexts for scraper testing
  config.before(:each, type: :scraper) do
    @config = WeeklyLocalEvents::Config.new
    @date_range = WeeklyLocalEvents::DateRange.from_days(7)
  end

  config.after(:each) do
    WebMock.reset!
  end
end

# Shared examples definition
RSpec.shared_examples "scraper returns valid data" do
  it "returns an array of Event instances" do
    expect(scraper.events).to be_an(Array)
    expect(scraper.events).to all(be_a(WeeklyLocalEvents::Event))
  end

  it "validates each event" do
    scraper.events.each do |event|
      expect(event).to be_valid, "Event failed validation: #{event.errors.full_messages.join(', ')}"
    end
  end

  it "sets required fields on each event" do
    scraper.events.each do |event|
      expect(event.title).not_to be_empty
      expect(event.date).not_to be_nil
      expect(event.venue).not_to be_nil
      expect(event.url).not_to be_empty
      expect(event.source).not_to be_empty
    end
  end

  it "sets source to the scraper name" do
    scraper.events.each do |event|
      expect(event.source).to eq(scraper.name)
    end
  end
end

RSpec.shared_examples "scraper handles empty response" do
  it "returns an empty array when no events are found" do
    allow(scraper).to receive(:fetch).and_return(Nokogiri::HTML5.parse("<html><body></body></html>"))
    expect(scraper.events).to eq([])
  end

  it "does not raise an error on empty response" do
    expect { scraper.events }.not_to raise_error
  end
end

RSpec.shared_examples "scraper handles HTTP errors gracefully" do
  it "returns empty array on 404" do
    allow(scraper).to receive(:fetch).and_raise(WeeklyLocalEvents::NotFoundError, "Not found")
    expect(scraper.events).to eq([])
  end

  it "returns empty array on rate limit" do
    allow(scraper).to receive(:fetch).and_raise(WeeklyLocalEvents::RateLimitError, "Rate limited")
    expect(scraper.events).to eq([])
  end
end

# Shared contexts definition
RSpec.shared_context "with a stubbed HTTP response" do
  let(:html_response) { "<html><body>Test</body></html>" }

  before do
    allow(scraper).to receive(:fetch).and_return(Nokogiri::HTML5.parse(html_response))
  end
end

RSpec.shared_context "with a scraper instance" do
  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(7) }
  let(:scraper) { described_class.new(config) }
end

RSpec.shared_context "with a scraper and stubbed response" do
  let(:config) { WeeklyLocalEvents::Config.new }
  let(:date_range) { WeeklyLocalEvents::DateRange.from_days(7) }
  let(:scraper) { described_class.new(config) }

  before do
    allow(scraper).to receive(:fetch).and_call_original
  end
end

RSpec.shared_context "with Faker Address" do
  before do
    @address = {
      street: Faker::Address.street_address,
      city: Faker::Address.city,
      state: Faker::Address.state,
      zip: Faker::Address.zip_code,
      country: Faker::Address.country,
    }
  end
end

RSpec.shared_context "with Faker Lorem" do
  before do
    @lorem = {
      sentence: Faker::Lorem.sentence,
      paragraph: Faker::Lorem.paragraph(sentence_count: 3),
      word: Faker::Lorem.word,
    }
  end
end

# WebMock configuration
WebMock.disable_net_connect!(allow_localhost: true)

# Ensure Faker is set up for each test
RSpec.configure do |config|
  config.before(:each) do
    Faker::Config.locale = :en
  end
end
