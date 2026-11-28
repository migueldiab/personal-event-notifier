# frozen_string_literal: true

require "uri"

module WeeklyLocalEvents
  # HTTP fetch pipeline that survives rate limits, bot protection and login
  # walls. Candidates are tried in order: primary page, regional variants,
  # then a headless browser with stealth headers.
  #
  # The fetcher is deliberately tolerant: any blocked or failed candidate
  # moves on to the next one and total failure is reported as +nil+, never as
  # an exception escaping the scraper.
  class AntiBotFetcher
    RETRYABLE_CODES = [429, 503].freeze
    LOGIN_PATH = "/premium-signin"
    MAX_REDIRECTS = 3

    BOT_MARKERS = [
      # Interstitial text is the reliable signal: a bot wall can answer 200.
      /just a moment/i,
      /attention required/i,
      /cf-browser-verification/i,
      /cf_chl_/i,
      /px-captcha/i,
      /verify you are human/i,
      /enable javascript and cookies to continue/i,
      /access denied/i,
    ].freeze

    Result = Struct.new(:status, :body, :url, keyword_init: true) do
      def success? = status == :success
      def login_wall? = status == :login_wall
      def blocked? = status == :blocked
    end

    def initialize(request:, rate_limiter: nil, max_retries: 3, backoff_base: 2.0,
                   max_backoff: 30.0, jitter: 0.2, logger: nil,
                   sleeper: ->(seconds) { Kernel.sleep(seconds) },
                   random: Random.new, headless_fetcher: nil,
                   stealth_headers: HeadlessBrowserFetcher::STEALTH_HEADERS,
                   login_path: LOGIN_PATH, fixture_path: nil)
      @request = request
      @rate_limiter = rate_limiter
      @max_retries = [max_retries.to_i, 1].max
      @backoff_base = backoff_base.to_f
      @max_backoff = max_backoff.to_f
      @jitter = jitter.to_f
      @logger = logger
      @sleeper = sleeper
      @random = random
      @headless_fetcher = headless_fetcher
      @stealth_headers = stealth_headers
      @login_path = login_path
      @fixture_path = fixture_path
    end

    # Fetch the first URL that returns usable HTML.
    #
    # @param url [String] the primary URL
    # @param fallback_urls [Array<String>] regional variants to try in order
    # @param headless [Boolean] whether to try the headless browser last
    # @return [String, nil] HTML body, cached fixture HTML, or nil when every route failed
    def fetch(url, fallback_urls: [], headless: true)
      candidates = [url, *fallback_urls].uniq

      candidates.each do |candidate|
        result = fetch_candidate(candidate)
        return result.body if result.success?
        return nil if result.login_wall?
      end

      body = headless && @headless_fetcher ? fetch_headless(url) : nil
      return body unless body.to_s.strip.empty?

      fetch_cached_fixture
    end

    private

    def fetch_candidate(url)
      current_url = url
      redirects = 0
      attempt = 0

      while attempt < @max_retries
        @rate_limiter&.wait
        response = @request.call(current_url, headers: {})
        code = response.code.to_i

        return handle_success(response, url, current_url) if (200..299).cover?(code)

        if (300..399).cover?(code)
          location = header(response, "Location")
          return login_wall(current_url) if login_path?(location)
          return blocked(url, "unexpected redirect #{code}") if location.nil? || redirects >= MAX_REDIRECTS

          redirects += 1
          current_url = URI.join(current_url, location).to_s
          next
        end

        return blocked(url, "HTTP #{code}") unless RETRYABLE_CODES.include?(code)

        outcome = retry_or_give_up(response, code, url, attempt)
        return outcome unless outcome == :retry

        attempt += 1
      end

      blocked(url, "retry budget exhausted")
    rescue StandardError => e
      blocked(url, "#{e.class}: #{e.message}")
    end

    def handle_success(response, original_url, current_url)
      body = response.body.to_s
      return login_wall(current_url) if login_wall_body?(body)
      return blocked(original_url, "bot protection challenge") if bot_challenge?(body)

      Result.new(status: :success, body: body, url: current_url)
    end

    def retry_or_give_up(response, code, url, attempt)
      return blocked(url, "HTTP #{code}") if attempt + 1 >= @max_retries

      delay = backoff_delay(attempt + 1, response)
      log_info("HTTP #{code} for #{url}; retrying in #{delay.round(2)}s")
      @sleeper.call(delay)
      :retry
    end

    def fetch_headless(url)
      body = @headless_fetcher.call(url, headers: @stealth_headers)
      return log_and_nil("headless browser returned no HTML for #{url}") if body.to_s.strip.empty?
      return log_and_nil("headless browser hit bot protection for #{url}") if bot_challenge?(body)
      return log_and_nil("headless browser hit the login wall for #{url}") if login_wall_body?(body)

      body
    rescue StandardError => e
      log_and_nil("headless browser failed for #{url}: #{e.class} - #{e.message}")
    end

    def backoff_delay(retry_number, response)
      retry_after = header(response, "Retry-After").to_s
      return [retry_after.to_f, @max_backoff].min if retry_after.match?(/\A\d+(?:\.\d+)?\z/)

      raw = [@backoff_base * (2**(retry_number - 1)), @max_backoff].min
      [raw * (1.0 + @random.rand(-@jitter..@jitter)), @max_backoff].min
    end

    def bot_challenge?(body)
      snippet = body.to_s[0, 100_000]
      BOT_MARKERS.any? { |marker| snippet.match?(marker) }
    end

    def login_wall_body?(body)
      body.to_s.include?(@login_path)
    end

    def login_path?(location)
      !location.to_s.empty? && location.to_s.include?(@login_path)
    end

    def header(response, name)
      headers = response.headers if response.respond_to?(:headers)
      return headers[name] || headers[name.downcase] if headers

      return response[name] if response.respond_to?(:[]) && !response.is_a?(Struct)

      nil
    rescue NameError, IndexError, TypeError
      nil
    end

    def login_wall(url)
      log_warn("Login wall at #{url} (#{@login_path}); skipping premium content")
      Result.new(status: :login_wall, url: url)
    end

    def blocked(url, reason)
      log_warn("Blocked #{url}: #{reason}")
      Result.new(status: :blocked, url: url)
    end

    # Last resort: replay a previously captured fixture when every live route
    # was blocked. Cached HTML is read from disk, never requested over HTTP.
    def fetch_cached_fixture
      return nil if @fixture_path.to_s.strip.empty?
      return log_and_nil("Cached fixture not found at #{@fixture_path}") unless File.file?(@fixture_path)

      body = File.read(@fixture_path)
      return log_and_nil("Cached fixture #{@fixture_path} is empty") if body.to_s.strip.empty?
      return log_and_nil("Cached fixture #{@fixture_path} is a bot challenge") if bot_challenge?(body)

      log_warn("All live routes blocked; using cached fixture #{@fixture_path}")
      body
    rescue StandardError => e
      log_and_nil("Could not read cached fixture #{@fixture_path}: #{e.class} - #{e.message}")
    end

    def log_and_nil(message)
      log_warn(message)
      nil
    end

    def log_info(message)
      @logger&.info("[anti_bot_fetcher] #{message}")
    end

    def log_warn(message)
      @logger&.warn("[anti_bot_fetcher] #{message}")
    end
  end
end
