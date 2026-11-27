# frozen_string_literal: true

module WeeklyLocalEvents
  # Spaces outgoing requests to a polite, jittered rate.
  #
  # The default of five requests per minute means a minimum 12-second gap.
  # Jitter (±20% by default) avoids a fixed, machine-like request cadence.
  class RateLimiter
    DEFAULT_REQUESTS_PER_MINUTE = 5
    DEFAULT_JITTER = 0.2

    def initialize(requests_per_minute: DEFAULT_REQUESTS_PER_MINUTE,
                   jitter: DEFAULT_JITTER,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                   sleeper: ->(seconds) { Kernel.sleep(seconds) },
                   random: Random.new)
      rate = requests_per_minute.to_f
      @interval = rate.positive? ? 60.0 / rate : 0.0
      @jitter = jitter.to_f
      @clock = clock
      @sleeper = sleeper
      @random = random
      @last_call_at = nil
    end

    # Block until the next request is allowed; returns the delay actually used.
    #
    # @return [Float] seconds slept
    def wait
      delay = delay_before_next_request
      @sleeper.call(delay) if delay.positive?
      @last_call_at = @clock.call
      delay
    end

    private

    def delay_before_next_request
      return 0.0 if @interval <= 0 || @last_call_at.nil?

      factor = 1.0 + @random.rand(-@jitter..@jitter)
      target = @interval * factor
      [target - (@clock.call - @last_call_at), 0.0].max
    end
  end
end
