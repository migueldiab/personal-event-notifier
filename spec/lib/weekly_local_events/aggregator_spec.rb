# frozen_string_literal: true

require "spec_helper"

# The Aggregator exposes instance methods; the dotted describe labels below
# follow the story's naming while `subject` supplies the instance under test.
RSpec.describe WeeklyLocalEvents::Aggregator do
  subject(:aggregator) { described_class.new }

  let(:today) { Date.today }
  let(:dedup_venue) { build(:venue, name: "The Blue Note") }
  let(:other_venue) { build(:venue, name: "The Continental Club") }

  describe '.aggregate' do
    let(:day_one) { today + 1 }
    let(:day_two) { today + 2 }
    let(:day_three) { today + 3 }

    context "with exact duplicates among five events" do
      let!(:first) { build(:event, title: "Jazz at the Blue Note", venue: dedup_venue, date: day_one) }
      let!(:duplicate_one) { build(:event, title: "Jazz at the Blue Note", venue: dedup_venue, date: day_one) }
      let!(:duplicate_two) { build(:event, title: "Jazz at the Blue Note", venue: dedup_venue, date: day_one) }
      let!(:unique_one) { build(:event, title: "Indie Rock Showcase", venue: dedup_venue, date: day_two) }
      let!(:unique_two) { build(:event, title: "Community Garden Tour", venue: dedup_venue, date: day_three) }
      let(:events) { [first, duplicate_one, duplicate_two, unique_one, unique_two] }

      it "keeps only the unique events" do
        result = aggregator.aggregate(events)

        expect(result.size).to eq(3)
        expect(result).to contain_exactly(first, unique_one, unique_two)
      end

      it "keeps the first occurrence of a duplicate group" do
        expect(aggregator.aggregate(events).first).to equal(first)
      end

      it "does not mutate the caller's array contents order for unique events" do
        expect(aggregator.aggregate(events).map(&:title)).to eq([first.title, unique_one.title, unique_two.title])
      end
    end

    context "with titles that differ only by case, punctuation, or whitespace" do
      let(:original) { build(:event, title: "Live Jazz Night", venue: dedup_venue, date: day_one) }
      let(:similar_one) { build(:event, title: "live jazz night!", venue: dedup_venue, date: day_one) }
      let(:similar_two) { build(:event, title: "LIVE  JAZZ  NIGHT", venue: dedup_venue, date: day_one) }
      let(:unrelated) { build(:event, title: "Comedy Open Mic", venue: dedup_venue, date: day_two) }

      it "deduplicates events whose normalized titles match" do
        expect(aggregator.aggregate([original, similar_one, similar_two, unrelated]))
          .to eq([original, unrelated])
      end
    end

    context "with a duplicate built from the same original event" do
      let(:original) { build(:event, venue: dedup_venue, date: day_one) }
      let(:duplicate) { build(:duplicate_event, original: original) }

      it "treats the duplicate as the same event even though its title differs" do
        expect(duplicate.title).not_to eq(original.title)
        expect(aggregator.aggregate([original, duplicate])).to eq([original])
      end
    end

    context "when only the venue or the date differs" do
      let(:original) { build(:event, title: "Live Jazz Night", venue: dedup_venue, date: day_one) }
      let(:different_venue) { build(:event, title: "Live Jazz Night", venue: other_venue, date: day_one) }
      let(:different_date) { build(:event, title: "Live Jazz Night", venue: dedup_venue, date: day_two) }

      it "keeps all events because their dedup keys differ" do
        expect(aggregator.aggregate([original, different_venue, different_date]))
          .to contain_exactly(original, different_venue, different_date)
      end
    end

    context "with events outside the default date range" do
      let(:too_old) { build(:event, title: "Past Show", venue: dedup_venue, date: today - 1) }
      let(:too_far) { build(:event, title: "Future Show", venue: dedup_venue, date: today + described_class::DEFAULT_DAYS + 1) }
      let(:in_range) { build(:event, title: "This Week", venue: dedup_venue, date: day_one) }

      it "runs the full normalize, dedup, filter, sort, and enrich pipeline" do
        expect(aggregator.aggregate([too_far, too_old, in_range])).to eq([in_range])
      end
    end

    it "returns an empty array when given no events" do
      expect(aggregator.aggregate([])).to eq([])
    end
  end

  describe '.dedup_key' do
    let(:title) { "Live Jazz Night" }
    let(:date) { today + 1 }
    let(:first) { build(:event, title: title, venue: dedup_venue, date: date) }
    let(:identical) { build(:event, title: title, venue: dedup_venue, date: date) }
    let(:duplicate) { build(:duplicate_event, original: first) }

    it "returns the same key for identical events" do
      expect(aggregator.dedup_key(identical)).to eq(aggregator.dedup_key(first))
    end

    it "returns the same key for similar titles after normalization" do
      similar = build(:event, title: "live jazz night!", venue: dedup_venue, date: date)

      expect(aggregator.dedup_key(similar)).to eq(aggregator.dedup_key(first))
      expect(aggregator.dedup_key(duplicate)).to eq(aggregator.dedup_key(first))
    end

    it "collapses case and whitespace differences in the venue name" do
      venue_variant = build(:venue, name: "the  blue note")
      variant = build(:event, title: title, venue: venue_variant, date: date)

      expect(aggregator.dedup_key(variant)).to eq(aggregator.dedup_key(first))
    end

    it "returns different keys when title, venue, or date differs" do
      different_title = build(:event, title: "Comedy Open Mic", venue: dedup_venue, date: date)
      different_venue = build(:event, title: title, venue: other_venue, date: date)
      different_date = build(:event, title: title, venue: dedup_venue, date: today + 2)

      keys = [first, different_title, different_venue, different_date].map { |event| aggregator.dedup_key(event) }

      expect(keys.uniq.size).to eq(4)
    end

    it "uses unknown placeholders when venue or date is missing" do
      no_venue = build(:event, title: title, venue: nil, date: date)
      no_date = build(:event, title: title, venue: dedup_venue, date: nil)

      expect(aggregator.dedup_key(no_venue)).to start_with("unknown|")
      expect(aggregator.dedup_key(no_date)).to include("|unknown|")
    end

    it "composes the key from normalized venue, date, and title" do
      expect(aggregator.dedup_key(first)).to eq("the blue note|#{date}|live jazz night")
    end
  end

  describe '.normalize_prices' do
    [
      ["$10", 1000, false],
      ["10.00", 1000, false],
      ["10", 1000, false],
      ["free", 0, true],
      ["€5", 500, false],
      ["$0", 0, true],
      ["10 USD", 1000, false],
      ["FREE", 0, true],
      ["10.50", 1050, false],
    ].each do |raw_price, expected_cents, expected_free|
      it "normalizes #{raw_price.inspect} to #{expected_cents} cents with free=#{expected_free}" do
        event = build(:event, price: raw_price)

        expect(aggregator.normalize_prices([event])).to eq([event])
        expect(event.price_cents).to eq(expected_cents)
        expect(event.free?).to be(expected_free)
      end
    end

    it "uses the minimum value of a price range" do
      event = build(:event, price: "$10-50")

      aggregator.normalize_prices([event])

      expect(event.price_cents).to eq(1000)
    end

    it "leaves unparseable prices unset" do
      event = build(:event, price: "not-a-price")

      aggregator.normalize_prices([event])

      expect(event.price_cents).to be_nil
    end

    it "normalizes every event in the collection" do
      events = [build(:event, price: "$10"), build(:event, price: "free")]

      aggregator.normalize_prices(events)

      expect(events.map(&:price_cents)).to eq([1000, 0])
    end
  end

  describe '.filter_by_date_range' do
    let(:start_date) { today + 1 }
    let(:end_date) { today + 3 }
    let(:before_range) { build(:event, title: "Before", venue: dedup_venue, date: today) }
    let(:on_start) { build(:event, title: "On start", venue: dedup_venue, date: start_date) }
    let(:inside) { build(:event, title: "Inside", venue: dedup_venue, date: today + 2) }
    let(:on_end) { build(:event, title: "On end", venue: dedup_venue, date: end_date) }
    let(:after_range) { build(:event, title: "After", venue: dedup_venue, date: today + 4) }

    it "keeps events inside the range and excludes events outside it" do
      result = aggregator.filter_by_date_range([before_range, inside, after_range], start_date, end_date)

      expect(result).to eq([inside])
    end

    it "includes events exactly on the boundary dates" do
      result = aggregator.filter_by_date_range([on_start, on_end], start_date, end_date)

      expect(result).to contain_exactly(on_start, on_end)
    end

    it "returns an empty array when no events fall in the range" do
      expect(aggregator.filter_by_date_range([before_range, after_range], start_date, end_date)).to eq([])
    end

    it "drops undated events" do
      undated = build(:event, title: "Undated", venue: dedup_venue, date: nil)

      expect(aggregator.filter_by_date_range([undated, inside], start_date, end_date)).to eq([inside])
    end
  end

  describe '.sort_by_date' do
    let(:earliest) { build(:event, title: "Earliest", venue: dedup_venue, date: today + 1) }
    let(:middle) { build(:event, title: "Middle", venue: dedup_venue, date: today + 2) }
    let(:latest) { build(:event, title: "Latest", venue: dedup_venue, date: today + 3) }

    it "sorts events in ascending order regardless of input order" do
      expect(aggregator.sort_by_date([latest, earliest, middle])).to eq([earliest, middle, latest])
    end

    it "places undated events at the end" do
      undated = build(:event, title: "Undated", venue: dedup_venue, date: nil)

      expect(aggregator.sort_by_date([undated, latest, earliest])).to eq([earliest, latest, undated])
    end
  end

  describe '.format_for_notification' do
    let(:event) do
      build(:event,
            title: "Live Jazz Night",
            venue: dedup_venue,
            date: today + 1,
            time: "7:00 PM",
            price: "$10.00",
            category: "Music",
            url: "https://example.com/jazz")
    end

    it "returns a friendly message when there are no events" do
      expect(aggregator.format_for_notification([])).to eq("No events found for the selected date range.")
    end

    it "includes a date header and every event detail" do
      output = aggregator.format_for_notification([event])
      header = (today + 1).strftime("%A, %B %d")

      expect(output).to start_with("**#{header}**")
      expect(output).to include("**Live Jazz Night**")
      expect(output).to include(dedup_venue.full_address)
      expect(output).to include("🕐 7:00 PM")
      expect(output).to include("💰 $10")
      expect(output).to include("📍 Music")
      expect(output).to include("🔗 https://example.com/jazz")
    end

    it "separates multiple date groups with a divider" do
      second = build(:event, title: "Comedy Open Mic", venue: other_venue, date: today + 2)
      output = aggregator.format_for_notification([event, second])

      expect(output).to include("-" * 40)
      expect(output).to include("**#{(today + 1).strftime('%A, %B %d')}**")
      expect(output).to include("**#{(today + 2).strftime('%A, %B %d')}**")
      expect(output).to include("**Comedy Open Mic**")
    end

    it "groups undated events and omits empty detail lines" do
      undated = build(:event,
                      title: "Mystery Show",
                      venue: dedup_venue,
                      date: nil,
                      time: nil,
                      price: nil,
                      category: nil,
                      url: nil)
      output = aggregator.format_for_notification([undated])

      expect(output).to include("**Undated**")
      expect(output).to include("**Mystery Show**")
      expect(output).not_to include("🕐")
      expect(output).not_to include("💰")
      expect(output).not_to include("📍")
      expect(output).not_to include("🔗")
    end
  end

  describe '.format_summary' do
    let(:paid) do
      build(:event, title: "Paid Show", venue: dedup_venue, date: today + 1,
                    price: "$45.00", category: "Music", source: "Do512")
    end
    let(:free_one) do
      build(:free_event, venue: dedup_venue, date: today + 2, category: "Community", source: "EventBrite")
    end
    let(:free_two) do
      build(:free_event, venue: other_venue, date: today + 3, category: "Community", source: "EventBrite")
    end

    it "returns an empty hash for no events" do
      expect(aggregator.format_summary([])).to eq({})
    end

    it "reports totals and free/paid counts with a plural count string" do
      summary = aggregator.format_summary([paid, free_one, free_two])

      expect(summary[:total]).to eq(3)
      expect(summary[:free_count]).to eq(2)
      expect(summary[:paid_count]).to eq(1)
      expect("#{summary[:total]} events").to eq("3 events")
    end

    it "produces a singular count string for one event" do
      summary = aggregator.format_summary([paid])

      expect(summary[:total]).to eq(1)
      expect("#{summary[:total]} event").to eq("1 event")
    end

    it "tallies categories, sources, and venues by descending count" do
      summary = aggregator.format_summary([paid, free_one, free_two])

      expect(summary[:categories]).to eq([["Community", 2], ["Music", 1]])
      expect(summary[:sources]).to eq([["EventBrite", 2], ["Do512", 1]])
      expect(summary[:venues]).to eq([["The Blue Note", 2], ["The Continental Club", 1]])
    end

    it "computes average price and date range from the events" do
      summary = aggregator.format_summary([paid, free_one, free_two])

      expect(summary[:price_ranges]).to include(free: 2, paid: 1, average_cents: 4500, average_dollars: 45.0)
      expect(summary[:average_price]).to eq(4500.0)
      expect(summary[:date_range]).to eq(from: today + 1, to: today + 3)
    end
  end

  describe '.enrich' do
    # Enrichment geocodes through Venue#geocode!; this codebase has no
    # Geocoder constant, so stub that boundary and wire it into the venue.
    let(:geocoder_class) do
      Class.new do
        def self.lookup(address)
          { lat: 30.2672, lng: -97.7431, address: address }
        end
      end
    end
    let(:coordinates) { { lat: 30.2672, lng: -97.7431 } }
    let(:ungeocoded_venue) { build(:ungeocoded_venue, city: "Austin", address: "100 W 6th St") }
    let(:event) { build(:event, venue: ungeocoded_venue, category: "Live Music Show") }

    before do
      stub_const("Geocoder", geocoder_class)
      allow_any_instance_of(WeeklyLocalEvents::Venue).to receive(:geocode!) do |venue|
        result = Geocoder.lookup(venue.address)
        venue.instance_variable_set(:@lat, result[:lat])
        venue.instance_variable_set(:@lng, result[:lng])
        venue
      end
    end

    it "adds coordinates from the geocoder lookup" do
      expect(Geocoder).to receive(:lookup).with("100 W 6th St").and_return(coordinates)

      expect(aggregator.enrich([event])).to eq([event])
      expect(ungeocoded_venue).to be_geocoded
      expect(ungeocoded_venue.lat).to eq(30.2672)
      expect(ungeocoded_venue.lng).to eq(-97.7431)
    end

    it "does not geocode venues that already have coordinates" do
      geocoded_event = build(:event, venue: dedup_venue)
      expect_any_instance_of(WeeklyLocalEvents::Venue).not_to receive(:geocode!)

      expect(aggregator.enrich([geocoded_event])).to eq([geocoded_event])
    end

    it "silently skips venues whose geocoding fails" do
      allow_any_instance_of(WeeklyLocalEvents::Venue).to receive(:geocode!)
        .and_raise(WeeklyLocalEvents::GeocodeError, "lookup failed")

      expect { aggregator.enrich([event]) }.not_to raise_error
      expect(ungeocoded_venue).not_to be_geocoded
    end

    it "normalizes the event category to the standard set" do
      aggregator.enrich([event])

      expect(event.instance_variable_get(:@category)).to eq("Music")
    end

    it "normalizes a range of category keywords" do
      [
        ["Stand-up Comedy", "Comedy"],
        ["Street Festival", "Festival"],
        ["Football Match", "Sports"],
        ["Art Exhibition", "Art"],
        ["Wine Tasting", "Food & Drink"],
        ["Craft Market", "Market"],
        ["Coding Workshop", "Education"],
        ["Broadway Play", "Theater"],
        ["KidsZone", "Family"],
        ["DJ Night", "Nightlife"],
        ["Hiking Trail", "Outdoor"],
        ["Church Service", "Religious"],
        ["Political Rally", "Politics"],
        ["Hackathon", "Technology"],
        ["Neighbourhood", "Neighbourhood"],
      ].each do |raw_category, normalized|
        categorized = build(:event, venue: dedup_venue, category: raw_category)

        aggregator.enrich([categorized])

        expect(categorized.instance_variable_get(:@category)).to eq(normalized)
      end
    end

    it "caches enrichment state per event" do
      aggregator.enrich([event])

      expect(aggregator.instance_variable_get(:@enriched)[event.object_id]).to be(true)
    end

    it "tolerates events without a venue" do
      venue_less = build(:event, venue: nil, category: "Neighbourhood")

      expect { aggregator.enrich([venue_less]) }.not_to raise_error
      expect(venue_less.instance_variable_get(:@category)).to eq("Neighbourhood")
    end

    it "leaves nil categories nil" do
      uncategorized = build(:event, venue: dedup_venue, category: nil)

      aggregator.enrich([uncategorized])

      expect(uncategorized.instance_variable_get(:@category)).to be_nil
    end
  end
end
