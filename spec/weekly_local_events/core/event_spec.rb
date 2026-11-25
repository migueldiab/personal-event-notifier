# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Core::Event do
  let(:attributes) do
    {
      id: "abc123",
      title: "Oscars 2027",
      event_type: "awards",
      date: "2027-03-07 20:00:00 -0600",
      location: "Dolby Theatre, Los Angeles",
      source: "austinchronicle",
      description: "The Academy Awards ceremony.",
      url: "https://example.com/oscars",
      broadcast_info: "ABC, 8:00 PM EST"
    }
  end

  subject { described_class.new(attributes) }

  it "creates an event from a hash" do
    expect(subject.id).to eq("abc123")
    expect(subject.title).to eq("Oscars 2027")
    expect(subject.location).to eq("Dolby Theatre, Los Angeles")
  end

  it "has a default empty description" do
    event = described_class.new(attributes.merge(description: nil))
    expect(event.description).to eq("")
  end

  it "has a default empty url" do
    event = described_class.new(attributes.merge(url: nil))
    expect(event.url).to eq("")
  end
end
