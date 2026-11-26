# frozen_string_literal: true

FactoryBot.define do
  factory :event, class: "WeeklyLocalEvents::Event" do
    initialize_with do
      WeeklyLocalEvents::Event.new(
        title: Faker::Lorem.sentence,
        description: Faker::Lorem.paragraph,
        date: Faker::Date.between(from: Date.today, to: Date.today + 7),
        time: "7:00 PM",
        venue: association(:venue),
        price: Faker::Commerce.price,
        currency: "USD",
        url: Faker::Internet.url,
        source: "test",
        image_url: Faker::Avatar.image,
        category: %w[music comedy festival sports].sample,
        tags: [Faker::Lorem.word],
      )
    end
  end

  factory :free_event, class: "WeeklyLocalEvents::Event" do
    initialize_with do
      WeeklyLocalEvents::Event.new(
        title: Faker::Lorem.sentence,
        date: Faker::Date.between(from: Date.today, to: Date.today + 7),
        venue: build(:venue),
        url: Faker::Internet.url,
        source: "test",
        price: "Free",
      )
    end
  end
end
