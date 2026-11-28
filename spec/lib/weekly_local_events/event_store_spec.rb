# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "weekly_local_events/event_store"

RSpec.describe WeeklyLocalEvents::EventStore do
  let(:dir) { Dir.mktmpdir("eventbrite-store-spec") }
  let(:path) { File.join(dir, "nested", "events.json") }
  let(:store) { described_class.new(path: path) }
  let(:event) do
    {
      id: "12345",
      title: "Austin Wine Festival",
      start_date: "2026-12-05T17:30:00",
      end_date: "2026-12-05T20:30:00",
      venue_name: "1209 E Cesar Chavez St",
      venue_address: "1209 East Cesar Chavez Street, Austin, TX 78702",
      ticket_url: "https://www.eventbrite.com/e/austin-wine-festival-tickets-12345",
      price: "$20.00",
      price_cents: 2000
    }
  end

  after { FileUtils.remove_entry(dir) if dir && File.exist?(dir) }

  describe "#write" do
    it "creates parent directories and persists structured events as JSON" do
      written = store.write([event])

      expect(written).to eq(path)
      data = JSON.parse(File.read(path))
      expect(data["count"]).to eq(1)
      expect(data["events"].first).to include(
        "id" => "12345",
        "title" => "Austin Wine Festival",
        "venue_address" => "1209 East Cesar Chavez Street, Austin, TX 78702",
        "ticket_url" => "https://www.eventbrite.com/e/austin-wine-festival-tickets-12345",
        "price_cents" => 2000
      )
    end

    it "records a generation timestamp" do
      store.write([event])
      expect(JSON.parse(File.read(path))["generated_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "#read" do
    it "returns the persisted events" do
      store.write([event])
      expect(store.read).to eq([event.transform_keys(&:to_s)])
    end

    it "returns an empty array when no file exists" do
      expect(store.read).to eq([])
    end
  end
end
