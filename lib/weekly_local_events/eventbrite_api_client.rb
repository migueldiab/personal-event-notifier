# frozen_string_literal: true

require "weekly_local_events/eventbrite_client"
require "weekly_local_events/rate_limiter"

module WeeklyLocalEvents
  # Rate-limited, retrying wrapper around EventbriteClient for API v3 calls.
  #
  # Responsibilities:
  #   - throttle requests to a polite rate (default 10 requests/minute),
  #   - enforce a rolling one-hour call budget (default 2000 calls/hour),
  #   - retry 429/5xx and transient network errors with backoff,
  #   - surface 401/403 as AuthenticationError and 404 as NotFoundError.
  #
  # The raw X-Rate-Limit header is never logged or returned: only its numeric
  # reset value is parsed, so the private token embedded in it cannot leak.
  class EventbriteApiClient
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class NotFoundError < Error; end
    class RequestError < Error; end
    class BudgetExceeded < Error; end

    class RateLimitError < Error
      attr_reader :retry_after, :reset_after

      def initialize(message, retry_after: nil, reset_after: nil)
        super(message)
        @retry_after = retry_after
        @reset_after = reset_after
      end
    end

    DEFAULT_REQUESTS_PER_MINUTE = 10
    DEFAULT_REQUESTS_PER_HOUR = 2000
    DEFAULT_MAX_RETRIES = 3
    BASE_BACKOFF_SECONDS = 1.0
    MAX_BACKOFF_SECONDS = 300.0
    WINDOW_SECONDS = 3600.0

    attr_reader :requests_per_hour, :max_retries

    # @param client [EventbriteClient] low-level authenticated client
    # @param rate_limiter [RateLimiter] inter-request throttle
    # @param requests_per_hour [Integer] hard hourly call budget
    # @param max_retries [Integer] retries after the initial attempt
    # @param sleeper [#call] injectable sleep function for tests
    # @param clock [#call] injectable monotonic clock for tests
    def initialize(client:, rate_limiter: nil, requests_per_hour: DEFAULT_REQUESTS_PER_HOUR,
                   max_retries: DEFAULT_MAX_RETRIES,
                   sleeper: ->(seconds) { Kernel.sleep(seconds) },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @client = client
      @rate_limiter = rate_limiter || RateLimiter.new(
        requests_per_minute: DEFAULT_REQUESTS_PER_MINUTE
      )
      @requests_per_hour = requests_per_hour.to_i
      @max_retries = max_retries.to_i
      @sleeper = sleeper
      @clock = clock
      @calls = []
    end

    # Perform a GET and return the parsed JSON body.
    #
    # @param path [String] path beginning with /v3/
    # @param query [Hash] query parameters
    # @return [Hash, Array] parsed response
    def get(path, query: {})
      retries = 0

      loop do
        prune_calls!
        raise BudgetExceeded, "Eventbrite hourly budget of #{requests_per_hour} calls exhausted" if
          @calls.length >= requests_per_hour

        @rate_limiter.wait
        @calls << @clock.call
        response = perform_request(path, query)
        code = response.code.to_i

        return response.parsed_response if (200..299).cover?(code)

        case code
        when 401, 403
          raise AuthenticationError, "Eventbrite API returned #{code} (invalid or expired token)"
        when 404
          raise NotFoundError, "Eventbrite API returned 404 for #{path}"
        when 429
          retries = retry_or_raise(RateLimitError, response, retries, path, use_headers: true)
        when 500..599
          retries = retry_or_raise(RequestError, response, retries, path)
        else
          raise RequestError, "Eventbrite API returned #{code} for #{path}"
        end
      end
    end

    private

    def perform_request(path, query)
      @client.get_response(path, query: query)
    rescue StandardError => e
      raise e if e.is_a?(Error)

      raise RequestError, "Eventbrite request failed: #{e.class}: #{e.message}"
    end

    def retry_or_raise(error_class, response, retries, path, use_headers: false)
      raise error_class, "Eventbrite API returned #{response.code} for #{path}" if retries >= max_retries

      @sleeper.call(backoff_seconds(response, retries, use_headers: use_headers))
      retries + 1
    end

    def backoff_seconds(response, retries, use_headers: false)
      return exponential_backoff(retries) unless use_headers

      headers = response.headers.is_a?(Hash) ? response.headers : {}
      retry_after = numeric_header(headers["Retry-After"])
      return [retry_after, MAX_BACKOFF_SECONDS].min if retry_after&.positive?

      reset = reset_seconds(headers["X-Rate-Limit"])
      return [reset, MAX_BACKOFF_SECONDS].min if reset&.positive?

      exponential_backoff(retries)
    end

    def exponential_backoff(retries)
      [BASE_BACKOFF_SECONDS * (2**retries), MAX_BACKOFF_SECONDS].min
    end

    def numeric_header(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    # X-Rate-Limit looks like "token:... 7/2000 reset=3446s, key:... 7/2000 reset=3446s".
    # Only the numeric reset is extracted; the token portion is discarded.
    def reset_seconds(value)
      match = value.to_s.match(/reset=(\d+)s/)
      match ? match[1].to_f : nil
    end

    def prune_calls!
      cutoff = @clock.call - WINDOW_SECONDS
      @calls.reject! { |timestamp| timestamp < cutoff }
    end
  end
end
