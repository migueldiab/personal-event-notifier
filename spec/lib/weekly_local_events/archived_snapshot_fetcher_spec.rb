# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "zlib"
require "weekly_local_events/archived_snapshot_fetcher"

# Injectable HTTP double. The helper calls #call(url, headers:) and reads
# #code/#body/#headers; WebMock still blocks any real connection, so an
# unstubbed URL fails loudly instead of silently going to the network.
class ArchivedSnapshotFakeHttp
  Response = Struct.new(:code, :body, :headers, keyword_init: true)

  attr_reader :calls

  def initialize(routes)
    @routes = routes
    @calls = []
  end

  def call(url, headers: {})
    @calls << { url: url, headers: headers }
    match = @routes.find do |pattern, _value|
      pattern.is_a?(Regexp) ? pattern.match?(url) : pattern == url
    end
    raise "unstubbed request: #{url}" unless match

    value = match.last
    value = value.call(url, headers) if value.respond_to?(:call)
    Response.new(
      code: value.fetch(:code, 200),
      body: value.fetch(:body, ""),
      headers: value.fetch(:headers, {})
    )
  end
end

RSpec.describe WeeklyLocalEvents::ArchivedSnapshotFetcher do
  let(:source_url) { "https://www.cedarparktexas.gov/calendar.aspx" }
  let(:jina_key) { nil }
  let(:genuine_body) do
    File.read(File.expand_path("spec/fixtures/cedar_park_events.html", Dir.pwd))
  end
  let(:http) { ArchivedSnapshotFakeHttp.new(routes) }
  let(:fetcher) { described_class.new(request: http, jina_api_key: jina_key) }
  let(:routes) { no_wayback }

  def availability(snapshots)
    {
      code: 200,
      body: JSON.generate("url" => source_url, "archived_snapshots" => snapshots),
      headers: { "Content-Type" => "application/json" }
    }
  end

  def closest_snapshot
    {
      "status" => "200",
      "available" => true,
      "timestamp" => "20260207030455",
      "url" => "http://web.archive.org/web/20260207030455/#{source_url}"
    }
  end

  def no_wayback
    {
      %r{archive\.org/wayback/available} => availability({}),
      %r{web\.archive\.org/cdx/search/cdx} => {
        code: 503, body: "Temporarily Offline", headers: {}
      }
    }
  end

  def page(title, text)
    "<html><head><title>#{title}</title></head><body>#{text}</body></html>"
  end

  def expect_fake_200_rejected(body, reason)
    expect(described_class.valid_body?(body, original_url: source_url)).to be(false)

    snapshot = fetcher.fetch(source_url)

    expect(snapshot).to be_nil
    expect(fetcher.rejections.map { |entry| entry[:reason] }).to include(reason)
  end

  describe "genuine snapshot from the Wayback availability API" do
    let(:routes) do
      {
        %r{archive\.org/wayback/available} => availability("closest" => closest_snapshot),
        %r{web\.archive\.org/web/20260207030455id_} => {
          code: 200, body: genuine_body, headers: {}
        }
      }
    end

    it "returns the raw id_ snapshot with body, source URL and timestamp provenance" do
      snapshot = fetcher.fetch(source_url)

      expect(snapshot).to be_a(described_class::Snapshot)
      expect(snapshot.body).to include("BASKETBALL (1 COURT)")
      expect(snapshot.body).to eq(genuine_body)
      expect(snapshot.route).to eq(:wayback)
      expect(snapshot.source_url).to eq(source_url)
      expect(snapshot.snapshot_url).to include("web.archive.org/web/20260207030455id_/")
      expect(snapshot.snapshot_timestamp).to eq("20260207030455")
    end

    it "requests the raw id_ form rather than the replay URL from the API" do
      fetcher.fetch(source_url)

      snapshot_request = http.calls.map { |call| call[:url] }.find { |url| url.include?("web.archive.org/web/") }
      expect(snapshot_request).to match(%r{/web/20260207030455id_/https://www\.cedarparktexas\.gov/calendar\.aspx\z})
    end

    it "exposes provenance as data and as a fixture header comment" do
      snapshot = fetcher.fetch(source_url)

      expect(snapshot.provenance).to include(
        source_url: source_url,
        snapshot_url: snapshot.snapshot_url,
        route: :wayback,
        snapshot_timestamp: "20260207030455",
        captured_on: "2026-02-07",
        kind: :snapshot
      )
      expect(snapshot.provenance_header).to include(source_url, "20260207030455", "as archived 2026-02-07")
      expect(snapshot.snapshot?).to be(true)
    end
  end

  describe "CDX fallback when the availability API has no snapshot" do
    let(:routes) do
      {
        %r{archive\.org/wayback/available} => availability({}),
        %r{web\.archive\.org/cdx/search/cdx} => {
          code: 200,
          body: JSON.generate(
            [%w[timestamp original statuscode], ["20260207030455", source_url, "200"]]
          ),
          headers: {}
        },
        %r{web\.archive\.org/web/20260207030455id_} => {
          code: 200, body: genuine_body, headers: {}
        }
      }
    end

    it "uses the first successful CDX row as the snapshot timestamp" do
      snapshot = fetcher.fetch(source_url)

      expect(snapshot).not_to be_nil
      expect(snapshot.route).to eq(:cdx)
      expect(snapshot.snapshot_timestamp).to eq("20260207030455")
      expect(snapshot.body).to include("BASKETBALL (1 COURT)")
    end
  end

  describe "gzip-encoded Wayback id_ snapshot" do
    let(:compressed_body) do
      writer = StringIO.new(+"", "wb")
      gz = Zlib::GzipWriter.new(writer)
      gz.write(genuine_body)
      gz.close
      writer.string
    end
    let(:routes) do
      {
        %r{archive\.org/wayback/available} => availability("closest" => closest_snapshot),
        %r{web\.archive\.org/web/20260207030455id_} => {
          code: 200,
          body: compressed_body,
          headers: { "Content-Encoding" => "gzip" }
        }
      }
    end

    it "decompresses the body before validation and returns readable HTML" do
      snapshot = fetcher.fetch(source_url)

      expect(snapshot).not_to be_nil
      expect(snapshot.body).to include("BASKETBALL (1 COURT)")
      expect(snapshot.body).not_to start_with("\x1F\x8B".b)
    end
  end

  describe "archive.today rotation" do
    let(:captcha_body) do
      intro = "One more step. Please complete the security check to access this page. " \
              "CAPTCHA verification required. "
      page("archive.ph", "#{intro}#{"x" * 59_000}")
    end

    context "when every domain returns a fake-200 CAPTCHA" do
      let(:routes) do
        no_wayback.merge(
          %r{archive\.(?:ph|md|li|is)/newest/} => { code: 200, body: captcha_body, headers: {} }
        )
      end

      it "rejects all four domains and records why" do
        expect(fetcher.fetch(source_url)).to be_nil

        archive_rejections = fetcher.rejections.select { |entry| entry[:route] == :archive_today }
        expect(archive_rejections.length).to eq(4)
        expect(archive_rejections.map { |entry| entry[:reason] }.uniq).to eq([:interstitial])
      end
    end

    context "when a later domain carries a genuine snapshot" do
      let(:routes) do
        no_wayback.merge(
          %r{archive\.ph/newest/} => { code: 200, body: captcha_body, headers: {} },
          %r{archive\.md/newest/} => { code: 429, body: "Too Many Requests", headers: {} },
          %r{archive\.li/newest/} => { code: 200, body: genuine_body, headers: {} },
          %r{archive\.is/newest/} => { code: 200, body: captcha_body, headers: {} }
        )
      end

      it "stops at the first genuine body with archive.today provenance" do
        snapshot = fetcher.fetch(source_url)

        expect(snapshot).not_to be_nil
        expect(snapshot.route).to eq(:archive_today)
        expect(snapshot.body).to include("BASKETBALL (1 COURT)")
        expect(snapshot.source_url).to eq(source_url)
        expect(snapshot.snapshot_timestamp).to be_nil
        expect(http.calls.map { |call| call[:url] }.grep(%r{archive\.is/})).to be_empty
      end
    end
  end

  describe "mandatory body validation on HTTP 200" do
    let(:routes) do
      no_wayback.merge(
        %r{archive\.(?:ph|md|li|is)/newest/} => { code: 200, body: bad_body, headers: {} }
      )
    end

    context "when the body is a Cloudflare interstitial" do
      let(:bad_body) { page("Just a moment...", "Checking your browser before accessing the site") }

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :interstitial)
      end
    end

    context "when the body is a bot-verification interstitial" do
      let(:bad_body) { page("Attention Required!", "Verify you are human to continue #{"y" * 4_000}") }

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :interstitial)
      end
    end

    context "when the body is a rate-limit page" do
      let(:bad_body) { page("Rate limit", "Too Many Requests. Rate limit exceeded. #{"z" * 4_000}") }

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :rate_limited)
      end
    end

    context "when the body is an Internet Archive outage page" do
      let(:bad_body) { page("Internet Archive", "Temporarily Offline: please try again later") }

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :rate_limited)
      end
    end

    context "when the body is a meta-refresh redirect stub" do
      let(:bad_body) do
        '<html><head><title>Redirecting</title>' \
          "<meta http-equiv=\"refresh\" content=\"0; url=#{source_url}\"></head><body></body></html>"
      end

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :redirect_stub)
      end
    end

    context "when the body is a JavaScript redirect stub" do
      let(:bad_body) do
        page("Redirecting", "<script>window.location.replace('#{source_url}');</script>")
      end

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :redirect_stub)
      end
    end

    context "when the body is a Google Cache stub" do
      let(:bad_body) do
        stub = "<meta http-equiv=\"refresh\" content=\"0; url=" \
               "https://webcache.googleusercontent.com/search?q=cache:#{source_url}\">" \
               "Google Cache is no longer available #{"g" * 2_000}"
        page("Google Search", stub)
      end

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :google_cache_stub)
      end
    end

    context "when the body is an AMP cache redirect stub" do
      let(:bad_body) do
        page("Redirecting", "<meta http-equiv=\"refresh\" content=\"0; url=" \
                            "https://www-cedarparktexas-gov.cdn.ampproject.org/c/s/" \
                            "www.cedarparktexas.gov/calendar.aspx\">")
      end

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :amp_redirect_stub)
      end
    end

    context "when the body is an empty stub" do
      let(:bad_body) { "<html><title>Redirecting</title></html>" }

      it "rejects the 200 response" do
        expect_fake_200_rejected(bad_body, :redirect_stub)
      end
    end
  end

  describe "Jina Reader gating" do
    context "when no API key is configured" do
      let(:routes) do
        no_wayback.merge(
          %r{archive\.(?:ph|md|li|is)/newest/} => { code: 200, body: "One more step CAPTCHA", headers: {} }
        )
      end

      it "never requests r.jina.ai" do
        expect(fetcher.fetch(source_url)).to be_nil
        expect(http.calls.map { |call| call[:url] }.grep(%r{r\.jina\.ai/})).to be_empty
      end
    end

    context "when a key is configured" do
      let(:jina_key) { "test-token" }
      let(:jina_markdown) { "# Cedar Park events\n\nBASKETBALL (1 COURT) — Recreation Center\n" }
      let(:routes) do
        no_wayback.merge(
          %r{archive\.(?:ph|md|li|is)/newest/} => { code: 200, body: "One more step CAPTCHA", headers: {} },
          %r{r\.jina\.ai/} => { code: 200, body: jina_markdown, headers: {} }
        )
      end

      it "fetches Jina with a bearer token and marks the result as live" do
        snapshot = fetcher.fetch(source_url)

        expect(snapshot).not_to be_nil
        expect(snapshot.route).to eq(:jina)
        expect(snapshot.body).to include("BASKETBALL (1 COURT)")
        expect(snapshot.snapshot_timestamp).to be_nil
        expect(snapshot.snapshot?).to be(false)
        expect(snapshot.provenance[:kind]).to eq(:live)

        jina_call = http.calls.find { |call| call[:url].include?("r.jina.ai") }
        expect(jina_call[:headers]["Authorization"]).to eq("Bearer test-token")
      end
    end
  end

  describe "total failure" do
    let(:routes) do
      {
        %r{archive\.org/wayback/available} => { code: 404, body: "not found", headers: {} },
        %r{web\.archive\.org/cdx/search/cdx} => { code: 503, body: "Temporarily Offline", headers: {} },
        %r{archive\.(?:ph|md|li|is)/newest/} => { code: 200, body: "One more step", headers: {} }
      }
    end

    it "returns nil rather than a fake success" do
      expect(fetcher.fetch(source_url)).to be_nil
      expect(fetcher.rejections).not_to be_empty
    end
  end
end
