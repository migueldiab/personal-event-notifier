# frozen_string_literal: true

FactoryBot.define do
  factory :venue, class: "WeeklyLocalEvents::Venue" do
    name { "Test Venue" }
    address { "123 Main St" }
    city { "Austin" }
    state { "TX" }
    zip { "78701" }
    lat { 30.2672 }
    lng { -97.7431 }
    website { "https://example.com" }
    phone { "555-1234" }

    initialize_with do
      WeeklyLocalEvents::Venue.new(
        name: name,
        address: address,
        city: city,
        state: state,
        zip: zip,
        lat: lat,
        lng: lng,
        website: website,
        phone: phone,
        url: nil,
      )
    end

    to_create { |instance, attrs| instance.initialize(**attrs) }

    factory :austin_venue do
      city { "Austin" }
      state { "TX" }
      zip { "78701" }
    end
  end
end