# frozen_string_literal: true

require "weekly_local_events/eventbrite_client"

RSpec.describe WeeklyLocalEvents::EventbriteClient do
  let(:token_url) { "https://www.eventbrite.com/oauth/token" }
  let(:api_base_url) { "https://www.eventbriteapi.com" }

  describe ".from_env" do
    it "reads credentials from environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("EVENTBRITE_CLIENT_ID", nil).and_return("app-key")
      allow(ENV).to receive(:fetch).with("EVENTBRITE_CLIENT_SECRET", nil).and_return("app-secret")
      allow(ENV).to receive(:fetch).with("EVENTBRITE_REDIRECT_URI", nil).and_return("http://localhost:8080/oauth/redirect")
      allow(ENV).to receive(:fetch).with("EVENTBRITE_PRIVATE_TOKEN", nil).and_return("private-token")

      client = described_class.from_env

      expect(client.client_id).to eq("app-key")
      expect(client.client_secret).to eq("app-secret")
      expect(client.redirect_uri).to eq("http://localhost:8080/oauth/redirect")
      expect(client.private_token).to eq("private-token")
    end
  end

  describe "#configured?" do
    it "is false without any credentials" do
      expect(described_class.new.configured?).to be(false)
    end

    it "is true with a private token" do
      expect(described_class.new(private_token: "private-token").configured?).to be(true)
    end

    it "is true with an API key and client secret" do
      client = described_class.new(client_id: "app-key", client_secret: "app-secret")
      expect(client.configured?).to be(true)
    end
  end

  describe "#authorization_url" do
    it "builds the server-side authorization URL with encoded parameters" do
      client = described_class.new(
        client_id: "app key",
        redirect_uri: "http://localhost:8080/oauth redirect"
      )
      url = client.authorization_url(state: "nonce 42")
      uri = URI(url)

      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://www.eventbrite.com/oauth/authorize")
      expect(URI.decode_www_form(uri.query).to_h).to include(
        "response_type" => "code",
        "client_id" => "app key",
        "redirect_uri" => "http://localhost:8080/oauth redirect",
        "state" => "nonce 42"
      )
    end
  end

  describe "#exchange_code" do
    let(:client) do
      described_class.new(
        client_id: "app-key",
        client_secret: "app-secret",
        redirect_uri: "http://localhost:8080/oauth/redirect"
      )
    end

    it "exchanges an authorization code for a private token" do
      stub = stub_request(:post, token_url)
             .with(
               body: {
                 "grant_type" => "authorization_code",
                 "client_id" => "app-key",
                 "client_secret" => "app-secret",
                 "code" => "auth-code",
                 "redirect_uri" => "http://localhost:8080/oauth/redirect"
               },
               headers: { "Content-Type" => "application/x-www-form-urlencoded" }
             )
             .to_return(status: 200, body: '{"access_token":"private-token"}',
                        headers: { "Content-Type" => "application/json" })

      expect(client.exchange_code("auth-code")).to eq("private-token")
      expect(stub).to have_been_requested
    end

    it "raises when credentials are missing" do
      expect { described_class.new.exchange_code("auth-code") }
        .to raise_error(WeeklyLocalEvents::EventbriteClient::MissingCredentialsError)
    end

    it "raises when the token endpoint rejects the request" do
      stub_request(:post, token_url)
        .to_return(status: 400, body: '{"error":"invalid_grant"}',
                   headers: { "Content-Type" => "application/json" })

      expect { client.exchange_code("bad-code") }
        .to raise_error(WeeklyLocalEvents::EventbriteClient::AuthenticationError, /invalid_grant/)
    end

    it "raises when the response has no access token" do
      stub_request(:post, token_url)
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      expect { client.exchange_code("auth-code") }
        .to raise_error(WeeklyLocalEvents::EventbriteClient::AuthenticationError, /access_token/)
    end
  end

  describe "#access_token" do
    it "prefers a configured private token" do
      client = described_class.new(private_token: "private-token")
      expect(client.access_token).to eq("private-token")
    end
  end

  describe "#event" do
    it "fetches an event with a bearer token" do
      client = described_class.new(private_token: "private-token")
      stub = stub_request(:get, "#{api_base_url}/v3/events/12345/")
             .with(headers: { "Authorization" => "Bearer private-token" })
             .to_return(status: 200, body: '{"id":"12345"}',
                        headers: { "Content-Type" => "application/json" })

      expect(client.event("12345")).to eq("id" => "12345")
      expect(stub).to have_been_requested
    end

    it "raises an API error for unauthorized requests" do
      client = described_class.new(private_token: "expired-token")
      stub_request(:get, "#{api_base_url}/v3/events/12345/")
        .to_return(status: 401, body: '{"error":"unauthorized"}',
                   headers: { "Content-Type" => "application/json" })

      expect { client.event("12345") }
        .to raise_error(WeeklyLocalEvents::EventbriteClient::AuthenticationError, /401/)
    end
  end

  describe "#get_response" do
    it "returns the raw response so callers can inspect headers" do
      client = described_class.new(private_token: "private-token")
      stub_request(:get, "#{api_base_url}/v3/events/12345/?page=2")
        .with(headers: { "Authorization" => "Bearer private-token" })
        .to_return(status: 429, body: '{"error":"RATE_LIMIT"}',
                   headers: { "Retry-After" => "12", "Content-Type" => "application/json" })

      response = client.get_response("/v3/events/12345/", query: { page: 2 })

      expect(response.code).to eq(429)
      expect(response.headers["Retry-After"]).to eq("12")
    end
  end
end
