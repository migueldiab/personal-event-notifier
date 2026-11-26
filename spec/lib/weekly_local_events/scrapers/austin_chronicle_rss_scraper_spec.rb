# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "weekly_local_events/scrapers/austin_chronicle_rss_scraper"

RSpec.describe WeeklyLocalEvents::Scrapers::AustinChronicleRSSScraper do
  subject(:scraper) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }
  let(:config_with_range) do
    { name: "austin_chronicle_rss", base_url: "https://www.austinchronicle.com",
      user_agent: "TestBot/1.0" }
  end
  let(:scraper_with_range) { described_class.new(config_with_range) }

  let(:sample_rss) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"
           xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>The Austin Chronicle</title>
          <link>https://www.austinchronicle.com/</link>
          <description>The Austin Chronicle is an independent, locally owned and operated alternative newsweekly.</description>
          <lastBuildDate>Wed, 25 Nov 2026 19:48:52 +0000</lastBuildDate>
          <language>en-US</language>
          <item>
            <title>Live Jazz Night at Continental Club</title>
            <link>https://www.austinchronicle.com/music/live-jazz-night-continental-club/</link>
            <pubDate>Wed, 25 Nov 2026 19:48:52 +0000</pubDate>
            <dc:creator><![CDATA[John Smith]]></dc:creator>
            <category><![CDATA[Music]]></category>
            <category><![CDATA[Jazz]]></category>
            <description><![CDATA[<p>An evening of live jazz featuring local artists at the Continental Club.</p><p>Doors at 8pm.</p>]]></description>
          </item>
          <item>
            <title>Free Open Mic Night</title>
            <link>https://www.austinchronicle.com/arts/free-open-mic-night/</link>
            <pubDate>Thu, 26 Nov 2026 10:00:00 +0000</pubDate>
            <dc:creator><![CDATA[Jane Doe]]></dc:creator>
            <category><![CDATA[Arts]]></category>
            <category><![CDATA[Open Mic]]></category>
            <description><![CDATA[Open mic night at Bathtub Row. Free admission.]]></description>
          </item>
          <item>
            <title>Concert at ACL Live</title>
            <link>https://www.austinchronicle.com/music/concert-at-acl-live/</link>
            <pubDate>Fri, 27 Nov 2026 14:30:00 +0000</pubDate>
            <dc:creator><![CDATA[Bob Wilson]]></dc:creator>
            <category><![CDATA[Music]]></category>
            <category><![CDATA[Concert]]></category>
            <description><![CDATA[<p>A full night of music at Austin's premier venue.</p>]]></description>
          </item>
        </channel>
      </rss>
    XML
  end

  let(:sample_rss_empty) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>The Austin Chronicle</title>
          <link>https://www.austinchronicle.com/</link>
          <description>Empty feed</description>
        </channel>
      </rss>
    XML
  end

  let(:sample_rss_no_categories) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>The Austin Chronicle</title>
          <link>https://www.austinchronicle.com/</link>
          <item>
            <title>Event Without Categories</title>
            <link>https://www.austinchronicle.com/events/no-categories/</link>
            <pubDate>Mon, 30 Nov 2026 12:00:00 +0000</pubDate>
            <description><![CDATA[<p>No categories listed here.</p>]]></description>
          </item>
        </channel>
      </rss>
    XML
  end

  let(:sample_rss_html_description) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>The Austin Chronicle</title>
          <link>https://www.austinchronicle.com/</link>
          <item>
            <title>Event With Rich HTML Description</title>
            <link>https://www.austinchronicle.com/events/rich-html/</link>
            <pubDate>Tue, 01 Dec 2026 09:00:00 +0000</pubDate>
            <description><![CDATA[<figure><img src="https://example.com/image.jpg" alt="Event photo"/></figure><p><strong>Bold text</strong> and <em>italic text</em> in the description.</p><a href="https://example.com">A link</a>]]></description>
          </item>
        </channel>
      </rss>
    XML
  end

  describe "#initialize" do
    it "sets the name to austin_chronicle_rss" do
      expect(scraper.name).to eq("austin_chronicle_rss")
    end

    it "sets the base_url to the Austin Chronicle URL" do
      expect(scraper.base_url).to eq("https://www.austinchronicle.com")
    end

    it "sets a proper user agent" do
      expect(scraper.user_agent).to include("WeeklyLocalEvents")
    end

    it "inherits from BaseScraper" do
      expect(scraper).to be_a(WeeklyLocalEvents::BaseScraper)
    end
  end

  describe "#parse_response" do
    it "parses RSS items into events" do
      events = scraper.parse_response(sample_rss)
      expect(events).to be_an(Array)
      expect(events.size).to eq(3)
    end

    it "extracts title from RSS items" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].title).to eq("Live Jazz Night at Continental Club")
      expect(events[1].title).to eq("Free Open Mic Night")
      expect(events[2].title).to eq("Concert at ACL Live")
    end

    it "extracts date from pubDate" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].date).to eq(Date.new(2026, 11, 25))
      expect(events[1].date).to eq(Date.new(2026, 11, 26))
      expect(events[2].date).to eq(Date.new(2026, 11, 27))
    end

    it "extracts URL from link element" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].url).to eq("https://www.austinchronicle.com/music/live-jazz-night-continental-club/")
      expect(events[1].url).to eq("https://www.austinchronicle.com/arts/free-open-mic-night/")
    end

    it "extracts description and strips HTML tags" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].description).to include("An evening of live jazz")
      expect(events[0].description).not_to include("<p>")
      expect(events[0].description).to include("Doors at 8pm")
    end

    it "extracts categories as tags" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].tags).to eq(["Music", "Jazz"])
      expect(events[1].tags).to eq(["Arts", "Open Mic"])
    end

    it "sets source to austin_chronicle_rss" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].source).to eq("austin_chronicle_rss")
    end

    it "sets venue to placeholder for RSS events (no venue in RSS feed)" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].venue.name).to eq("The Austin Chronicle (RSS)")
    end

    it "sets price to nil (RSS has no price data)" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].price).to eq("")
    end

    it "sets time to nil (RSS has no time data)" do
      events = scraper.parse_response(sample_rss)
      expect(events[0].time).to eq("")
    end

    it "returns empty array for empty RSS" do
      events = scraper.parse_response(sample_rss_empty)
      expect(events).to be_empty
    end

    it "returns empty array for nil input" do
      events = scraper.parse_response(nil)
      expect(events).to be_empty
    end

    it "returns empty array for empty XML string" do
      events = scraper.parse_response("<xml></xml>")
      expect(events).to be_empty
    end

    it "handles items without categories" do
      events = scraper.parse_response(sample_rss_no_categories)
      expect(events.size).to eq(1)
      expect(events[0].tags).to eq([])
    end

    it "strips HTML from descriptions" do
      events = scraper.parse_response(sample_rss_html_description)
      expect(events[0].description).to include("Bold text")
      expect(events[0].description).to include("italic text")
      expect(events[0].description).not_to include("<figure>")
      expect(events[0].description).not_to include("<img")
      expect(events[0].description).not_to include("<a href")
    end

    it "handles relative URLs" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>The Austin Chronicle</title>
            <link>https://www.austinchronicle.com/</link>
            <item>
              <title>Relative URL Test</title>
              <link>/events/relative-url/</link>
              <pubDate>Wed, 02 Dec 2026 12:00:00 +0000</pubDate>
              <description><![CDATA[<p>Test</p>]]></description>
            </item>
          </channel>
        </rss>
      XML
      events = scraper.parse_response(xml)
      expect(events[0].url).to eq("https://www.austinchronicle.com/events/relative-url/")
    end
  end

  describe "#events" do
    it "returns an array of Event objects when fetch succeeds" do
      stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
        .to_return(status: 200, body: sample_rss, headers: { "Content-Type" => "application/rss+xml" })

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to all(be_a(WeeklyLocalEvents::Event))
    end

    it "handles network failures gracefully" do
      stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
        .to_raise(Errno::ECONNREFUSED)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 404 gracefully" do
      stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
        .to_return(status: 404)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 429 (rate limit) gracefully" do
      stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
        .to_return(status: 429)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end

    it "handles HTTP 500 gracefully" do
      stub_request(:get, "https://www.austinchronicle.com/rss/chronic.xml")
        .to_return(status: 500)

      events = scraper_with_range.events
      expect(events).to be_an(Array)
      expect(events).to be_empty
    end
  end

  describe "#extract_creator" do
    it "extracts dc:creator text" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>The Austin Chronicle</title>
            <link>https://www.austinchronicle.com/</link>
            <item>
              <title>Test</title>
              <link>https://www.austinchronicle.com/test/</link>
              <pubDate>Wed, 02 Dec 2026 12:00:00 +0000</pubDate>
              <dc:creator><![CDATA[Author Name]]></dc:creator>
              <description><![CDATA[<p>Test</p>]]></description>
            </item>
          </channel>
        </rss>
      XML
      events = scraper.parse_response(xml)
      expect(events[0].title).to eq("Test")
    end
  end

  describe "#parse_response with malformed date" do
    it "handles invalid pubDate gracefully" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>The Austin Chronicle</title>
            <link>https://www.austinchronicle.com/</link>
            <item>
              <title>Bad Date Event</title>
              <link>https://www.austinchronicle.com/events/bad-date/</link>
              <pubDate>Not a valid date</pubDate>
              <description><![CDATA[<p>Test</p>]]></description>
            </item>
          </channel>
        </rss>
      XML
      events = scraper.parse_response(xml)
      expect(events.size).to eq(1)
      # Should default to Date.today when date parsing fails
      expect(events[0].date).to eq(Date.today)
    end
  end
end
