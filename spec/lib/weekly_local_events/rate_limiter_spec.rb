# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::RateLimiter do
  describe "#wait" do
    it "does not sleep before the first request" do
      slept = []
      limiter = described_class.new(clock: -> { 0.0 }, sleeper: ->(seconds) { slept << seconds })

      expect(limiter.wait).to eq(0.0)
      expect(slept).to be_empty
    end

    it "spaces requests at roughly five per minute with jitter" do
      now = [0.0]
      slept = []
      limiter = described_class.new(
        clock: -> { now[0] },
        sleeper: lambda { |seconds|
          slept << seconds
          now[0] += seconds
        }
      )

      limiter.wait
      limiter.wait

      expect(slept.length).to eq(1)
      expect(slept.first).to be_between(9.6, 14.4)
    end

    it "does not sleep again when the interval has already elapsed" do
      now = [0.0]
      slept = []
      limiter = described_class.new(
        clock: -> { now[0] },
        sleeper: lambda { |seconds|
          slept << seconds
          now[0] += seconds
        }
      )

      limiter.wait
      now[0] += 60
      limiter.wait

      expect(slept).to eq([])
    end

    it "can be disabled for tests and offline use" do
      slept = []
      limiter = described_class.new(requests_per_minute: 0, sleeper: ->(seconds) { slept << seconds })

      limiter.wait
      limiter.wait

      expect(slept).to be_empty
    end
  end
end
