# frozen_string_literal: true

require "webmock/rspec"

# Disable all network connections by default, allow localhost for Telegram API testing
WebMock.disable_net_connect!(allow_localhost: true)

# Stub http://localhost:* for Telegram API testing
WebMock.stub_request(:any, %r{^http://localhost:\d+})
  .to_return(status: 200, body: '{"ok":true,"result":{}}')

# Stub austinchronicle.com URLs (generic 200 response with sample HTML)
WebMock.stub_request(:any, %r{^https?://.*austinchronicle\.com})
  .to_return(
    status: 200,
    body: "<html><body><h1>Event Listings</h1></body></html>",
    headers: { "Content-Type" => "text/html" }
  )

# Stub do512.com URLs (generic 200 response with sample HTML)
WebMock.stub_request(:any, %r{^https?://.*do512\.com})
  .to_return(
    status: 200,
    body: "<html><body><h1>Event Listings</h1></body></html>",
    headers: { "Content-Type" => "text/html" }
  )

# Stub communityimpact.com URLs (generic 200 response with sample HTML)
WebMock.stub_request(:any, %r{^https?://.*communityimpact\.com})
  .to_return(
    status: 200,
    body: "<html><body><h1>Event Listings</h1></body></html>",
    headers: { "Content-Type" => "text/html" }
  )

# Stub telegram.org URLs (generic 200 response with sample JSON)
WebMock.stub_request(:any, %r{^https?://.*telegram\.org})
  .to_return(
    status: 200,
    body: '{"ok":true,"result":{}}',
    headers: { "Content-Type" => "application/json" }
  )

RSpec.configure do |config|
  config.before(:each) do
    WebMock.reset!
  end
end
