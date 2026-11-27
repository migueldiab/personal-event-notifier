# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.0"

# Core
gem "rails", "~> 7.1"
gem "dotenv-rails"
gem "nokogiri"
gem "pdf-reader"
gem "httparty"
gem "addressable"
gem "tzinfo"
gem "rake"
gem "telegram-bot"
gem "dry-struct"
gem "dry-types"

group :development do
  gem "rubocop", require: false
  gem "rubocop-rspec"
  gem "rubocop-rake"
end

group :development, :test do
  gem "rspec-rails", ">= 3.0"
end

group :test do
  gem "simplecov", require: false
  gem "webmock"
  gem "factory_bot_rails"
  gem "faker"
end
