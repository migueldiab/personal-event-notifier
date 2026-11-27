# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::AntiBotFetcher do
  subject(:fetcher) do
    described_class.new(
      request: request,
      rate_limiter: rate_limiter,
      max_retries: 3,
      backoff_base: 1.0,
      jitter: 0,
      logger: logger,
      sleeper: ->(seconds) { slept << seconds },
      headless_fetcher: headless_fetcher
    )
  end

  let(:request) { instance_double(Proc) }
  let(:rate_limiter) { instance_double(WeeklyLocalEvents::RateLimiter, wait: nil) }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:headless_fetcher) { instance_double(WeeklyLocalEvents::HeadlessBrowserFetcher) }
  let(:slept) { [] }
  let(:response_class) { Struct.new(:code, :body, :headers, keyword_init: true) }

  def response(code, body = "<html><body>calendar</body></html>", headers = {})
    response_class.new(code: code, body: body, headers: headers)
  end

  describe "#fetch" do
    it "returns the body of a successful response" do
      allow(request).to receive(:call).and_return(response(200))

      expect(fetcher.fetch("https://example.com/calendar")).to include("calendar")
    end

    it "retries a 429 with exponential backoff and returns the successful response" do
      allow(request).to receive(:call).and_return(response(429, ""), response(200))

      expect(fetcher.fetch("https://example.com/calendar")).to include("calendar")
      expect(slept).to eq([1.0])
      expect(request).to have_received(:call).twice
    end

    it "retries a 503 with exponential backoff" do
      allow(request).to receive(:call).and_return(response(503, ""), response(200))

      expect(fetcher.fetch("https://example.com/calendar")).to include("calendar")
      expect(slept).to eq([1.0])
    end

    it "honours the Retry-After header when backing off" do
      allow(request).to receive(:call).and_return(
        response(429, "", { "Retry-After" => "7" }),
        response(200)
      )

      fetcher.fetch("https://example.com/calendar")

      expect(slept).to eq([7.0])
    end

    it "falls back to a regional variant after repeated 429 responses" do
      primary = "https://communityimpact.com/austin/calendar/"
      regional = "https://satxevents.communityimpact.com/calendar/"
      allow(request).to receive(:call) do |url, **_kwargs|
        url == primary ? response(429, "") : response(200, "<html>regional events</html>")
      end

      body = fetcher.fetch(primary, fallback_urls: [regional])

      expect(body).to eq("<html>regional events</html>")
      expect(request).to have_received(:call).with(primary, headers: {}).exactly(3).times
      expect(request).to have_received(:call).with(regional, headers: {}).once
    end

    it "uses the headless browser with stealth headers when every variant is blocked" do
      allow(request).to receive(:call).and_return(response(403, "Forbidden"))
      allow(headless_fetcher).to receive(:call).and_return("<html>headless events</html>")

      body = fetcher.fetch(
        "https://example.com/calendar",
        fallback_urls: ["https://satxevents.communityimpact.com/calendar/"]
      )

      expect(body).to eq("<html>headless events</html>")
      expect(headless_fetcher).to have_received(:call).with(
        "https://example.com/calendar", headers: hash_including("User-Agent")
      )
    end

    it "skips premium content behind a login wall and logs a warning" do
      allow(headless_fetcher).to receive(:call)
      allow(request).to receive(:call).and_return(
        response(302, "", { "Location" => "https://example.com/premium-signin" })
      )

      expect(fetcher.fetch("https://example.com/premium-event")).to be_nil
      expect(logger).to have_received(:warn).with(/[Ll]ogin wall/)
      expect(headless_fetcher).not_to have_received(:call)
    end

    it "treats a bot-challenge body as blocked and moves to the next variant" do
      allow(request).to receive(:call) do |url, **_kwargs|
        if url == "https://example.com/calendar"
          response(200, "<title>Just a moment...</title>")
        else
          response(200, "<html>regional events</html>")
        end
      end

      body = fetcher.fetch("https://example.com/calendar",
                           fallback_urls: ["https://satxevents.communityimpact.com/calendar/"])

      expect(body).to eq("<html>regional events</html>")
      expect(logger).to have_received(:warn).with(/bot protection/)
    end

    it "does not raise when the request raises a network error" do
      allow(request).to receive(:call).and_raise(Errno::ECONNREFUSED)
      allow(headless_fetcher).to receive(:call).and_return(nil)

      expect { fetcher.fetch("https://example.com/calendar") }.not_to raise_error
      expect(fetcher.fetch("https://example.com/calendar")).to be_nil
    end

    it "returns nil without raising when the headless browser cannot run" do
      allow(request).to receive(:call).and_return(response(403, "Forbidden"))
      allow(headless_fetcher).to receive(:call).and_return(nil)

      expect(fetcher.fetch("https://example.com/calendar")).to be_nil
    end
  end
end
