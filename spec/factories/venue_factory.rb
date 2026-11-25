# frozen_string_literal: true

FactoryBot.define do
  factory :venue, class: "WeeklyLocalEvents::Venue" do
    name { "ACL Live" }
    address { "310 W 5th St" }
    city { "Austin" }
    state { "TX" }
    zip { "78701" }
    phone { "512-542-8255" }
    url { "https://aclive.com" }
  end
end
