# frozen_string_literal: true

require "open3"

module WeeklyLocalEvents
  # Last-resort fetcher: renders a page with a real headless browser when
  # plain HTTP requests are blocked by bot protection.
  #
  # The browser is launched with automation-detection flags and a browser-like
  # user agent. Additional stealth headers are honourable through +headers+:
  # Chromium's CLI only accepts the User-Agent header directly, so the other
  # headers are documented in STEALTH_HEADERS for callers using CDP-based
  # runners.
  class HeadlessBrowserFetcher
    BINARIES = %w[chromium chromium-browser google-chrome google-chrome-stable].freeze

    STEALTH_USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                         "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    STEALTH_HEADERS = {
      "User-Agent" => STEALTH_USER_AGENT,
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9",
      "Sec-Fetch-Dest" => "document",
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Site" => "none",
      "Upgrade-Insecure-Requests" => "1",
    }.freeze

    CHROMIUM_FLAGS = [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-blink-features=AutomationControlled",
      "--hide-scrollbars",
      "--window-size=1920,1080",
      "--virtual-time-budget=5000",
    ].freeze

    def initialize(binary: :auto, runner: nil, logger: nil, stealth_headers: STEALTH_HEADERS)
      @binary = binary
      @runner = runner || ->(*args) { Open3.capture3(*args) }
      @logger = logger
      @stealth_headers = stealth_headers
    end

    # Render +url+ and return its HTML, or nil when no browser is available.
    #
    # @param url [String] absolute URL
    # @param headers [Hash] optional header overrides (User-Agent is applied)
    # @return [String, nil]
    def call(url, headers: {})
      binary = resolve_binary
      unless binary
        log_warn("headless browser unavailable; skipping fallback for #{url}")
        return nil
      end

      user_agent = headers["User-Agent"] || @stealth_headers["User-Agent"] || STEALTH_USER_AGENT
      stdout, stderr, = @runner.call(binary, *CHROMIUM_FLAGS, "--user-agent=#{user_agent}", url)

      if stdout.to_s.strip.empty?
        log_warn("headless browser returned no HTML for #{url}: #{stderr.to_s.strip[0, 200]}")
        return nil
      end

      stdout
    rescue StandardError => e
      log_warn("headless browser failed for #{url}: #{e.class} - #{e.message}")
      nil
    end

    private

    def resolve_binary
      return nil if @binary.nil?
      return @binary unless @binary == :auto

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        BINARIES.each do |name|
          candidate = File.join(directory, name)
          return candidate if File.executable?(candidate)
        end
      end
      nil
    end

    def log_warn(message)
      @logger&.warn("[headless_browser] #{message}")
    end
  end
end
