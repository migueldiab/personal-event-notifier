# frozen_string_literal: true

require "date"
require "json"
require "net/http"
require "stringio"
require "uri"
require "zlib"
require "weekly_local_events/version"

module WeeklyLocalEvents
  # Fetches a blocked page through the cheapest route that yields a genuine
  # body: Wayback availability API, Wayback CDX, archive.today domain rotation,
  # then Jina Reader only when JINA_API_KEY is configured.
  #
  # Every route is subject to mandatory body validation. A HTTP 200 that is a
  # CAPTCHA/interstitial, a rate-limit page, a meta-refresh/JS redirect stub or
  # a Google Cache / AMP redirect is rejected exactly like a failed request —
  # status codes are never treated as evidence of success.
  #
  # The returned Snapshot carries provenance: the original source URL, the URL
  # actually fetched, the archive timestamp (when the route has one) and a
  # fixture-ready header comment. Recon: docs/cedar_park_recon.md.
  class ArchivedSnapshotFetcher
    ARCHIVE_TODAY_DOMAINS = %w[archive.ph archive.md archive.li archive.is].freeze
    AVAILABILITY_URL = "https://archive.org/wayback/available?url=%<url>s"
    CDX_URL = "https://web.archive.org/cdx/search/cdx?url=%<url>s&output=json" \
              "&filter=statuscode:200&limit=10"
    RAW_SNAPSHOT_URL = "https://web.archive.org/web/%<timestamp>sid_/%<url>s"
    JINA_URL = "https://r.jina.ai/%<url>s"
    USER_AGENT = "WeeklyLocalEvents/#{VERSION}".freeze
    MAX_REDIRECTS = 3

    # A validated recovery result. +snapshot_timestamp+ is nil for routes that
    # do not expose one (archive.today, Jina); +kind+ marks Jina as live.
    Snapshot = Struct.new(:body, :source_url, :snapshot_url, :snapshot_timestamp,
                          :route, :kind, keyword_init: true) do
      def snapshot? = !snapshot_timestamp.nil?

      def captured_on
        return nil if snapshot_timestamp.to_s.empty?

        Date.strptime(snapshot_timestamp.to_s[0, 8], "%Y%m%d").strftime("%Y-%m-%d")
      rescue ArgumentError
        nil
      end

      def provenance
        {
          source_url: source_url,
          snapshot_url: snapshot_url,
          route: route,
          snapshot_timestamp: snapshot_timestamp,
          captured_on: captured_on,
          kind: kind
        }
      end

      # Suitable for prepending to a captured fixture so its age is auditable.
      def provenance_header
        stamp = snapshot_timestamp || "unknown"
        date = captured_on ? " (as archived #{captured_on})" : ""
        ["# source: #{source_url}", "# route: #{route} | snapshot: #{stamp}#{date}"].join("\n")
      end

      def to_h
        provenance.merge(body: body)
      end
    end

    # Body-level rejection rules. Deliberately independent of HTTP status.
    class BodyValidator
      INTERSTITIAL_TITLES = [
        /just a moment/i, /attention required/i, /one more step/i, /google search/i,
        /security check/i, /checking your browser/i, /verify you are human/i,
        /access denied/i, /cf-browser-verification/i, /px-captcha/i
      ].freeze
      INTERSTITIAL_TEXT = [
        /one more step/i, /security check/i, /just a moment/i, /attention required/i,
        /verify you are human/i, /enable javascript and cookies to continue/i,
        /checking your browser/i, /px-captcha/i, /cf-browser-verification/i
      ].freeze
      RATE_LIMIT_TEXT = [
        /too many requests/i, /rate limit exceeded/i, /request limit reached/i,
        /temporarily offline/i, /temporarily unavailable/i,
        /you have reached your .{0,40}limit/i
      ].freeze
      REFRESH_META = /<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>/i
      JS_ASSIGN = /(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']/i
      JS_CALL = /location\.(?:replace|assign)\(\s*["']([^"']+)["']/i
      TITLE = %r{<title>(.*?)</title>}im
      SMALL_STUB_BYTES = 2_000
      AMP_STUB_BYTES = 1_000

      def initialize(min_bytes: 200)
        @min_bytes = min_bytes
      end

      # @return [Symbol, nil] rejection reason, or nil when the body is usable
      def rejection_reason(body, original_url: nil)
        text = body.to_s
        return :empty if text.strip.empty?
        return :google_cache_stub if google_cache_stub?(text)
        return :amp_redirect_stub if amp_redirect?(text)
        return :redirect_stub if redirect_stub?(text, original_url)
        return :rate_limited if rate_limited?(text)
        return :interstitial if interstitial?(text)
        return :too_short if text.strip.bytesize < @min_bytes

        nil
      end

      private

      def google_cache_stub?(text)
        text.match?(/webcache\.googleusercontent\.com/i)
      end

      def rate_limited?(text)
        return true if RATE_LIMIT_TEXT.any? { |marker| text.match?(marker) }

        small_stub?(text) && text.match?(/please try again later/i)
      end

      def amp_redirect?(text)
        return false unless text.match?(/cdn\.ampproject\.org/i)

        redirect_stub?(text, nil) || text.strip.bytesize < AMP_STUB_BYTES
      end

      def small_stub?(text)
        text.strip.bytesize < SMALL_STUB_BYTES
      end

      def redirect_stub?(text, original_url)
        targets = redirect_targets(text)
        title = text[TITLE, 1].to_s.strip
        small = small_stub?(text)

        return true if targets.any? { |target| same_host?(target, original_url) }
        return true if targets.any? && small
        return true if title.match?(/\A(?:redirect(?:ing)?|moved|please wait)\b/i) && small

        false
      end

      def redirect_targets(text)
        targets = []
        text.scan(REFRESH_META) do |tag|
          match = tag.match(/url\s*=\s*["']?([^"'\s>;]+)/i)
          targets << match[1] if match
        end
        text.scan(JS_ASSIGN) { |target| targets << target }
        text.scan(JS_CALL) { |target| targets << target }
        targets
      end

      def same_host?(target, original_url)
        return false if original_url.to_s.empty?

        URI(target.to_s).host.to_s.downcase == URI(original_url.to_s).host.to_s.downcase
      rescue URI::InvalidURIError
        false
      end

      def interstitial?(text)
        title = text[TITLE, 1].to_s
        snippet = text[0, 100_000]
        INTERSTITIAL_TITLES.any? { |marker| title.match?(marker) } ||
          INTERSTITIAL_TEXT.any? { |marker| snippet.match?(marker) }
      end
    end

    attr_reader :rejections

    # @param request [#call] injectable HTTP client called as +#call(url, headers:)+
    # @param jina_api_key [String, nil] defaults to ENV["JINA_API_KEY"]
    def initialize(request: nil, jina_api_key: ENV.fetch("JINA_API_KEY", nil),
                   min_body_bytes: 200, timeout: 30)
      @request = request || method(:default_request)
      @jina_api_key = jina_api_key
      @min_body_bytes = min_body_bytes.to_i
      @timeout = timeout.to_f
      @rejections = []
    end

    class << self
      # Public so scrapers can apply the same fake-200 guard to their own bodies.
      def valid_body?(body, original_url: nil, min_bytes: 200)
        BodyValidator.new(min_bytes: min_bytes).rejection_reason(body, original_url: original_url).nil?
      end
    end

    # Walk the recovery ladder and return the first genuine Snapshot.
    # @return [Snapshot, nil] nil when every route is blocked or rejected
    def fetch(url)
      source = url.to_s
      raise ArgumentError, "url must be absolute http(s): #{source}" unless source.match?(%r{\Ahttps?://})

      @rejections = []
      wayback_availability(source) || wayback_cdx(source) || archive_today(source) || jina(source)
    end

    private

    def wayback_availability(source)
      data = request_json(format(AVAILABILITY_URL, url: source))
      return nil unless data.is_a?(Hash)

      closest = data.dig("archived_snapshots", "closest")
      return nil unless closest.is_a?(Hash)

      available = [true, "true"].include?(closest["available"]) || closest["status"].to_s == "200"
      return nil unless available

      timestamp = closest["timestamp"].to_s
      return nil unless timestamp.match?(/\A\d{14}\z/)

      raw_snapshot(source, timestamp, :wayback)
    end

    def wayback_cdx(source)
      data = request_json(format(CDX_URL, url: source))
      return nil unless data.is_a?(Array) && data.length > 1

      timestamp = cdx_snapshot_timestamp(data)
      return nil if timestamp.nil? || timestamp.empty?

      raw_snapshot(source, timestamp, :cdx)
    end

    def cdx_snapshot_timestamp(data)
      columns = data.first.map { |name| name.to_s.downcase }
      timestamp_index = columns.index("timestamp")
      status_index = columns.index("statuscode")
      return nil unless timestamp_index && status_index

      row = data.drop(1).find do |candidate|
        candidate[status_index].to_s == "200" && candidate[timestamp_index].to_s.match?(/\A\d{14}\z/)
      end
      row&.at(timestamp_index)&.to_s
    end

    def raw_snapshot(source, timestamp, route)
      capture(
        format(RAW_SNAPSHOT_URL, timestamp: timestamp, url: source),
        source_url: source,
        snapshot_timestamp: timestamp,
        route: route,
        kind: :snapshot,
        min_bytes: @min_body_bytes
      )
    end

    def archive_today(source)
      ARCHIVE_TODAY_DOMAINS.each do |domain|
        snapshot = capture(
          "https://#{domain}/newest/#{source}",
          source_url: source,
          snapshot_timestamp: nil,
          route: :archive_today,
          kind: :snapshot,
          min_bytes: [@min_body_bytes, 2_000].max,
          headers: { "Accept" => "text/html" }
        )
        return snapshot if snapshot
      end
      nil
    end

    def jina(source)
      return nil if @jina_api_key.to_s.strip.empty?

      capture(
        format(JINA_URL, url: source),
        source_url: source,
        snapshot_timestamp: nil,
        route: :jina,
        kind: :live,
        min_bytes: 32,
        headers: { "Authorization" => "Bearer #{@jina_api_key}", "Accept" => "text/markdown" }
      )
    end

    def capture(url, source_url:, snapshot_timestamp:, route:, kind:, min_bytes:, headers: {})
      response = perform(url, headers: headers)
      return nil unless response

      status, raw_body, response_headers = response
      return record_rejection(route, url, :http_error) unless status.between?(200, 299)

      body = decode_body(raw_body, response_headers)
      reason = BodyValidator.new(min_bytes: min_bytes).rejection_reason(body, original_url: source_url)
      return record_rejection(route, url, reason) if reason

      Snapshot.new(
        body: body,
        source_url: source_url,
        snapshot_url: url,
        snapshot_timestamp: snapshot_timestamp,
        route: route,
        kind: kind
      )
    end

    def request_json(url)
      response = perform(url)
      return nil unless response

      status, body, = response
      return nil unless status.between?(200, 299)

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def perform(url, headers: {})
      response = @request.call(url, headers: headers)
      return record_rejection(:request, url, :no_response) if response.nil?

      [response.code.to_i, response.body.to_s, normalized_headers(response)]
    rescue SocketError, Timeout::Error, IOError, SystemCallError => e
      record_rejection(:request, url, e.class.name)
      nil
    end

    def normalized_headers(response)
      source = response.headers if response.respond_to?(:headers)
      return downcase_headers(source) if source.is_a?(Hash)
      return downcase_headers(response.each_header.to_h) if response.respond_to?(:each_header)

      {}
    end

    def downcase_headers(headers)
      headers.each_with_object({}) { |(key, value), acc| acc[key.to_s.downcase] = value.to_s }
    end

    # Wayback id_ snapshots arrive gzip-encoded even without --compressed.
    def decode_body(raw, headers)
      text = raw.to_s
      encoded = headers["content-encoding"].to_s.downcase
      return inflate(text) if encoded.include?("gzip") || gzip_magic?(text)

      text
    end

    def gzip_magic?(text)
      text.getbyte(0) == 0x1F && text.getbyte(1) == 0x8B
    end

    def inflate(text)
      Zlib::GzipReader.new(StringIO.new(text)).read
    rescue Zlib::Error, IOError, ArgumentError
      ""
    end

    def record_rejection(route, url, reason)
      @rejections << { route: route, url: url, reason: reason }
      nil
    end

    def build_request(uri, headers)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept-Encoding"] = "gzip"
      headers.each { |key, value| request[key] = value.to_s }
      request
    end

    def default_request(url, headers: {})
      current = URI(url)
      MAX_REDIRECTS.times do
        request = build_request(current, headers)

        response = Net::HTTP.start(
          current.hostname, current.port,
          use_ssl: current.scheme == "https",
          open_timeout: @timeout, read_timeout: @timeout
        ) { |http| http.request(request) }

        location = response["Location"]
        if response.code.to_i.between?(300, 399) && !location.to_s.empty?
          current = URI.join(current, location)
          next
        end
        return response
      end
      nil
    end
  end
end
