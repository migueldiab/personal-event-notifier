# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  skip "/spec/"
  skip "/.bundle/"
  group "Libraries", "lib"
end

require "weekly_local_events"
require "weekly_local_events/pipeline/engine"
require "weekly_local_events/pipeline/normalizer"
require "weekly_local_events/pipeline/crawler_engine"
require "weekly_local_events/notifications/dispatcher"
require "weekly_local_events/utils/date_helper"

require "rspec/core"
require "rspec/expectations"
require "rspec/mocks"
require "factory_bot_rails"
require "webmock/rspec"
require "faker"

WebMock.disable_net_connect!(allow_localhost: true)

Faker::Config.locale = "en_US"

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    FactoryBot.find_definitions
  end

  config.before(:each) do
    Faker::Config.locale = "en_US"
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
