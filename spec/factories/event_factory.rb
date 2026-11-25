# frozen_string_literal: true

FactoryBot.define do
  factory :event, class: "WeeklyLocalEvents::Event" do
    title { "Sample Event" }
    description { "A sample event description" }
    date { "2026-12-01" }
    time { "19:00" }
    venue { association(:venue) }
    price { 25.00 }
    url { "https://example.com/event" }
    source { "austin_chronicle" }
    tags { ["music", "live"] }
  end
end
