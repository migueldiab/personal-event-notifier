# frozen_string_literal: true

module WeeklyLocalEvents
  # Represents a date range for scraping.
  #
  # Usage:
  #   DateRange.new(start: Date.today, end: Date.today + 7)
  #   DateRange.from_days(7)
  class DateRange
    attr_reader :start_date, :end_date

    def initialize(start:, end_date:)
      @start_date = start
      @end_date = end_date
    end

    # Create a date range spanning N days from today.
    #
    # @param days [Integer] number of days from today
    # @return [DateRange]
    def self.from_days(days)
      new(start: Date.today, end_date: Date.today + days)
    end

    # Check if a date falls within this range (inclusive).
    #
    # @param date [Date]
    # @return [Boolean]
    def includes?(date)
      date >= start_date && date <= @end_date
    end

    # Duration in days.
    #
    # @return [Integer]
    def duration
      (@end_date - start_date).to_i + 1
    end

    # String representation.
    #
    # @return [String]
    def to_s
      "#{start_date}..#{@end_date} (#{duration} days)"
    end
  end

  # Base scraper class that all scrapers inherit from.
  #
  # Provides common functionality: HTTP fetching with retries and
  # exponential backoff, rate limiting, response parsing, and
  # normalization helpers for prices, dates, and times.
  #
  # Subclasses must implement:
  #   - events -> [Event]      (main entry point)
  #   - parse_response(html) -> [Event]
  #
  # Usage:
  #   class AustinChronicleScraper < BaseScraper
  #     def initialize(config)
  #       super(name: "austin_chronicle", base_url: "https://austinchronicle.com",
  #             date_range: DateRange.from_days(7), config: config)
  #     end
  #
  #     def events
  #       scrape_page("/calendar") + scrape_page("/events")
  #     end
  #
  #     def parse_response(html)
  #       # ... parse and return Event instances
  #     end
  #   end
  class BaseScraper
    attr_reader :name, :base_url, :date_range, :rate_limit_delay,
                :max_retries, :user_agent, :headers, :cookies, :config

    def initialize(config = {})
      if config.is_a?(Config)
        @config = config
      elsif config.is_a?(Hash)
        @config = Config.new
      else
        @config = Config.new
      end
      cfg = config.is_a?(Hash) ? config : {}
      @name = (cfg[:name] || cfg["name"] || self.class.name.to_s.split("::").last).to_s
      @base_url = cfg[:base_url] || cfg["base_url"] || ""
      @date_range = (cfg[:date_range] || (cfg[:date_range_days] && DateRange.from_days(cfg[:date_range_days]))) || DateRange.from_days(@config.date_range_days)
      @rate_limit_delay = (cfg[:rate_limit_delay] || cfg[:request_delay] || 2.0).to_f
      @max_retries = (cfg[:max_retries] || @config.max_retries || 3).to_i
      @user_agent = cfg[:user_agent] || cfg[:useragent] || "WeeklyLocalEvents/#{VERSION}"
      @headers = (cfg[:headers] || cfg["headers"] || {}).to_h
      @cookies = (cfg[:cookies] || cfg["cookies"] || {}).to_h
    end

    # Main entry point — returns all events for this scraper.
    # Subclasses MUST implement this.
    #
    # @return [Array<Event>]
    def events
      raise NotImplementedError, "#{self.class.name} must implement #events"
    end

    # Alias for compatibility with existing code that calls #scrape.
    #
    # @return [Array<Event>]
    def scrape
      events
    end

    # Fetch a URL and return a Nokogiri::HTML document.
    #
    # Handles retries with exponential backoff, rate limiting,
    # and various error conditions (network, HTTP, parse).
    #
    # @param url [String] the URL to fetch
    # @return [Nokogiri::HTML::Document]
    # @raise [NotFoundError] on 404
    # @raise [RateLimitError] on 429
    # @raise [ScraperError] on other HTTP errors
    # @raise [ScraperError] on network errors after retries
    def fetch(url)
      uri = URI(url)
      raise ArgumentError, "Invalid URL: #{url}" unless uri.scheme && uri.host

      last_error = nil
      attempts = 0

      while attempts < max_retries
        attempts += 1
        break if attempts > 1

        sleep(rate_limit_delay) if attempts > 1

        begin
          response = perform_request(uri)

          case response
          when Net::HTTPSuccess
            return parse_html(response.body)
          when Net::HTTPNotFound
            raise NotFoundError, "Not found: #{url}"
          when Net::HTTPTooManyRequests
            raise RateLimitError, "Rate limited: #{url} (attempt #{attempts})"
          else
            raise ScraperError, "HTTP #{response.code}: #{url}"
          end
        rescue RateLimitError => e
          last_error = e
          raise
        rescue StandardError => e
          last_error = e
          log_error "Attempt #{attempts}/#{max_retries} failed for #{url}: #{e.class} - #{e.message}"

          if attempts < max_retries
            backoff = (2**(attempts - 1)) * rate_limit_delay
            log_info "Retrying in #{backoff.round(1)}s..."
            sleep(backoff)
          end
        end
      end

      raise ScraperError, "Failed after #{max_retries} attempts for #{url}: #{last_error&.class} - #{last_error&.message}"
    end

    # Parse an HTML response into Event instances.
    # Subclasses MUST implement this.
    #
    # @param html [String, Nokogiri::HTML::Document] the HTML to parse
    # @return [Array<Event>]
    def parse_response(html)
      raise NotImplementedError, "#{self.class.name} must implement #parse_response"
    end

    # Scrape a single page: fetch, parse, and return events.
    #
    # @param url [String] the page URL
    # @return [Array<Event>]
    def scrape_page(url)
      full_url = build_url(url)
      html = fetch(full_url)
      parse_response(html)
    rescue NotFoundError
      log_info "Page not found: #{full_url}"
      []
    rescue RateLimitError => e
      log_error "Rate limit hit while scraping #{full_url}: #{e.message}"
      []
    rescue StandardError => e
      log_error "Error scraping #{full_url}: #{e.class} - #{e.message}"
      []
    end

    # Normalize a price string to cents (Integer).
    #
    # Handles formats: "$10", "$10.00", "$10-50", "$10 to $50",
    # "10", "10.00", "Free", "FREE", "TBD", ""
    #
    # @param price_string [String] raw price string
    # @return [Integer] price in cents (0 for free/TBD/empty)
    def normalize_price(price_string)
      return 0 if price_string.nil?

      s = price_string.to_s.strip.downcase
      return 0 if s.empty? || s == "free" || s == "tbd" || s == "tba"

      # Remove currency symbols and whitespace
      s = s.gsub(/[$€£₹]/, "").gsub(/\s+/, "")

      # Handle ranges: "10-50", "10 to 50", "10–50"
      if s.include?("-") || s.include?("to")
        parts = s.split(/[-–]|to/i)
        # Return the minimum price in the range
        s = parts.first.to_s
      end

      # Strip non-numeric except decimal point
      s = s.gsub(/[^0-9.]/, "")
      return 0 if s.empty?

      dollars = s.to_f
      (dollars * 100).round
    end

    # Normalize a date string to a Date object.
    #
    # Handles formats: "2026-12-01", "12/01/2026", "Dec 1, 2026",
    # "1 Dec 2026", "tomorrow", "today", "next Monday"
    #
    # @param date_string [String] raw date string
    # @return [Date, nil]
    def normalize_date(date_string)
      return nil if date_string.nil?

      s = date_string.to_s.strip

      # Handle relative dates
      case s.downcase
      when "today"
        return Date.today
      when "tomorrow"
        return Date.tomorrow
      when "yesterday"
        return Date.yesterday
      end

      # Try multiple date formats
      formats = [
        "%Y-%m-%d",
        "%m/%d/%Y",
        "%m-%d-%Y",
        "%d/%m/%Y",
        "%B %d, %Y",       # December 01, 2026
        "%b %d, %Y",       # Dec 01, 2026
        "%d %B %Y",        # 01 December 2026
        "%d %b %Y",        # 01 Dec 2026
        "%Y/%m/%d",
        "%d-%m-%Y",
      ]

      formats.each do |fmt|
        begin
          return Date.strptime(s, fmt)
        rescue ArgumentError
          next
        end
      end

      # Last resort: try Date.parse (handles many formats)
      begin
        return Date.parse(s)
      rescue ArgumentError, TypeError
        return nil
      end
    end

    # Normalize a time string to a standard format.
    #
    # Returns times as "HH:MM" (24h) or "HH:MM AM/PM".
    # Handles formats: "7:00 PM", "19:00", "7pm", "7:00pm",
    # "7:00", "1900", "7:30 PM"
    #
    # @param time_string [String] raw time string
    # @return [String] normalized time string
    def normalize_time(time_string)
      return nil if time_string.nil?

      s = time_string.to_s.strip
      return nil if s.empty?

      # Already in HH:MM format (24h)
      if s =~ /\A(\d{1,2}):(\d{2})\z/
        hours, minutes = $1.to_i, $2.to_i
        return format("%02d:%02d", hours, minutes)
      end

      # HH:MM AM/PM
      if s =~ /\A(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)\z/
        hours, minutes, period = $1.to_i, $2.to_i, $3.upcase
        hours = 0 if hours == 12 && period == "AM"
        hours = 12 if hours == 12 && period == "PM"
        hours += 12 if period == "PM" && hours != 12
        return format("%02d:%02d", hours, minutes)
      end

      # H:MM AM/PM (single digit hour)
      if s =~ /\A(\d{1,2})\s*(AM|PM|am|pm)\z/
        hours, period = $1.to_i, $2.upcase
        hours = 0 if hours == 12 && period == "AM"
        hours = 12 if hours == 12 && period == "PM"
        hours += 12 if period == "PM" && hours != 12
        return format("%02d:00", hours)
      end

      # HHMM (no separator)
      if s =~ /\A(\d{4})\z/
        hours, minutes = s[0..1].to_i, s[2..3].to_i
        return format("%02d:%02d", hours, minutes)
      end

      # Return as-is if we can't parse it
      s
    end

    # Validate an event and return it, or raise an error.
    #
    # Ensures required fields are present and values are sensible.
    #
    # @param event [Event] the event to validate
    # @return [Event] the validated event
    # @raise [ParseError] if validation fails
    def validate_event(event)
      errors = []

      if event.title.to_s.strip.empty?
        errors << "title is empty"
      end

      if event.date.nil?
        errors << "date is missing"
      end

      if event.venue.nil? || event.venue.name.to_s.strip.empty?
        errors << "venue is missing or empty"
      end

      if event.url.to_s.strip.empty?
        errors << "url is empty"
      end

      if event.source.to_s.strip.empty?
        errors << "source is empty"
      end

      if errors.any?
        raise ParseError, "#{name}: Invalid event — #{errors.join(", ")}"
      end

      event
    end

    private

    # Build a full URL from a relative or absolute path.
    #
    # @param path [String]
    # @return [String]
    def build_url(path)
      return path if path.start_with?("http://", "https://")
      base = base_url.chomp("/")
      stripped = path.sub(/\A\/+/, "")
      "#{base}/#{stripped}"
    end

    # Perform the actual HTTP request with headers and cookies.
    #
    # @param uri [URI]
    # @return [Net::HTTPResponse]
    def perform_request(uri)
      require "net/http"

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = user_agent
      request["Accept"] = "text/html,application/xhtml+xml"
      request["Accept-Language"] = "en-US,en;q=0.9"

      # Set custom headers
      headers.each do |key, value|
        request[key] = value.to_s
      end

      # Set cookies
      unless cookies.empty?
        cookie_str = cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
        request["Cookie"] = cookie_str
      end

      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        read_timeout: config.request_timeout,
        open_timeout: config.request_timeout,
      ) do |http|
        http.request(request)
      end
    end

    # Parse raw HTML body into a Nokogiri::HTML document.
    #
    # @param body [String] raw HTML
    # @return [Nokogiri::HTML::Document]
    # @raise [ParseError] if Nokogiri is unavailable
    def parse_html(body)
      require "nokogiri"
      Nokogiri::HTML5.parse(body, encoding: "UTF-8")
    rescue LoadError
      require "nokogiri"
      Nokogiri::HTML5.parse(body, encoding: "UTF-8")
    end

    def log_info(msg)
      config.logger&.info("[#{name}] #{msg}")
    end

    def log_error(msg)
      config.logger&.error("[#{name}] #{msg}")
    end
  end
end
