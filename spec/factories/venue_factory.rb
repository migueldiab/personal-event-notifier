# frozen_string_literal: true

FactoryBot.define do
  factory :venue, class: "WeeklyLocalEvents::Venue" do
    name { Faker::Company.name }
    address { Faker::Address.street_address }
    city { 'Austin' }
    state { 'TX' }
    zip { Faker::Address.zip_code }
    lat { 30.2672 }
    lng { -97.7431 }
    website { Faker::Internet.url }
    phone { Faker::PhoneNumber.phone_number }

    factory :austin_venue do
      city { 'Austin' }
      state { 'TX' }
      zip { '78701' }
    end
  end
end
