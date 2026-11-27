# frozen_string_literal: true

require "spec_helper"
require "weekly_local_events/eventbrite_api_client"

RSpec.describe WeeklyLocalEvents::EventbriteApiClient do
  let(:raw_response) do
    instance_double(
      HTTParty::Response,
      code: code,
      headers: { "X-Rate-Limit" => "token:abc 7/2000 reset=3446s" },
      parsed_response: { "events" => [] },
      body: "{\"events\":[]}"
    )
  end
  let(:code) { 200 }
  let(:underlying_client) { instance_double(WeeklyLocalEvents::EventbriteClient) }
  let(:sleeper) { [] }
  let(:client) do
    described_class.new(
      client: underlying_client,
      sleeper: ->(seconds) { sleeper << seconds },
      rate_limiter: rate_limiter
    )
  end
  let(:rate_limiter) { instance_double(WeeklyLocalEvents::RateLimiter, wait: 0.0) }

  describe "#get" do
    before do
      allow(underlying_client).to receive(:get_response).and_return(raw_response)
      allow(rate_limiter).to receive(:wait).and_return(0.0)
    end

    it "returns the parsed response body for HTTP 200" do
      expect(client.get("/v3/venues/1/events/", query: { page: 1 })).to eq("events" => [])
    end

    it "throttles every outgoing request" do
      client.get("/v3/venues/1/events/")
      expect(rate_limiter).to have_received(:wait).once
    end

    context "when the API returns 429 with Retry-After" do
      let(:retry_response) do
        instance_double(
          HTTParty::Response,
          code: 429,
          headers: { "Retry-After" => "9", "X-Rate-Limit" => "token:x 2000/2000 reset=9s" },
          parsed_response: { "error" => "RATE_LIMIT" },
          body: "rate limited"
        )
      end

      it "sleeps for the Retry-After value and retries" do
        allow(underlying_client).to receive(:get_response).and_return(retry_response, raw_response)
        result = client.get("/v3/venues/1/events/")
        expect(result).to eq("events" => [])
        expect(sleeper).to eq([9.0])
      end

      it "raises after exhausting retries" do
        allow(underlying_client).to receive(:get_response).and_return(retry_response)
        expect { client.get("/v3/venues/1/events/") }
          .to raise_error(described_class::RateLimitError)
        expect(sleeper.length).to eq(3)
      end
    end

    context "when the API returns 401" do
      let(:code) { 401 }

      it "raises AuthenticationError without retrying" do
        allow(underlying_client).to receive(:get_response).and_return(raw_response)
        expect { client.get("/v3/events/1/") }
          .to raise_error(described_class::AuthenticationError)
        expect(underlying_client).to have_received(:get_response).once
      end
    end

    context "when the API returns 404" do
      let(:code) { 404 }

      it "raises NotFoundError without retrying" do
        allow(underlying_client).to receive(:get_response).and_return(raw_response)
        expect { client.get("/v3/events/1/") }.to raise_error(described_class::NotFoundError)
        expect(underlying_client).to have_received(:get_response).once
      end
    end

    context "when the API returns 500" do
      let(:code) { 500 }

      it "retries with exponential backoff" do
        ok_response = instance_double(
          HTTParty::Response,
          code: 200,
          headers: {},
          parsed_response: { "events" => [] },
          body: "{\"events\":[]}"
        )
        allow(underlying_client).to receive(:get_response).and_return(raw_response, ok_response)
        expect(client.get("/v3/events/1/")).to eq("events" => [])
        expect(sleeper).to eq([1.0])
      end
    end

    it "stops before exceeding the hourly budget" do
      limited = described_class.new(
        client: underlying_client,
        sleeper: ->(seconds) { sleeper << seconds },
        rate_limiter: rate_limiter,
        requests_per_hour: 1
      )
      limited.get("/v3/events/1/")
      expect { limited.get("/v3/events/2/") }.to raise_error(described_class::BudgetExceeded)
    end
  end
end
