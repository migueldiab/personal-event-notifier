# frozen_string_literal: true

# Factory definitions used by the Aggregator specs.
#
# Events store their price as a display string, so the :price factories build a
# small value object whose #to_s is that display value. This keeps
# `association :price` realistic while still producing objects the production
# Event model accepts.
module WeeklyLocalEvents
  # Value object returned by the :price factories.
  class Price
    ATTRIBUTES = %i[amount currency display is_free].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(amount:, currency: "USD", display: nil, is_free: false)
      @amount = amount
      @currency = currency
      @display = display || default_display(amount, currency)
      @is_free = is_free
    end

    def to_s
      display
    end

    def to_h
      ATTRIBUTES.to_h { |attribute| [attribute, public_send(attribute)] }
    end

    def [](attribute)
      to_h[attribute.to_sym]
    end

    def free?
      is_free
    end

    private

    def default_display(amount, currency)
      prefix = currency == "USD" ? "$" : "#{currency} "
      "#{prefix}#{"%.2f" % amount}"
    end
  end
end

FactoryBot.define do
  factory :price, class: "WeeklyLocalEvents::Price" do
    amount { 10.0 }
    currency { "USD" }
    display { "$10.00" }
    is_free { false }

    initialize_with do
      WeeklyLocalEvents::Price.new(
        amount: amount,
        currency: currency,
        display: display,
        is_free: is_free
      )
    end

    factory :free_price do
      amount { 0.0 }
      display { "Free" }
      is_free { true }
    end

    factory :premium_price do
      amount { 45.0 }
      display { "$45.00" }
    end

    factory :euro_price do
      amount { 5.0 }
      currency { "EUR" }
      display { "€5.00" }
    end
  end

  factory :venue, class: "WeeklyLocalEvents::Venue" do
    sequence(:name) { |n| "The Blue Note #{n}" }
    sequence(:address) { |n| "#{100 + n} W 6th St" }
    city { "Austin" }
    state { "TX" }
    zip { "78701" }
    lat { 30.2672 }
    lng { -97.7431 }
    website { "https://thebluenote.example.com" }
    phone { "512-555-0100" }

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
        phone: phone
      )
    end

    factory :austin_venue do
      city { "Austin" }
      state { "TX" }
      zip { "78701" }
      lat { 30.2672 }
      lng { -97.7431 }
    end

    factory :dallas_venue do
      sequence(:name) { |n| "The Loft Dallas #{n}" }
      address { "2019 N Lamar St" }
      city { "Dallas" }
      zip { "75202" }
      lat { 32.7767 }
      lng { -96.7970 }
    end

    factory :ungeocoded_venue do
      sequence(:name) { |n| "Mystery Hall #{n}" }
      lat { nil }
      lng { nil }
    end
  end

  factory :event, class: "WeeklyLocalEvents::Event" do
    transient do
      original { nil }
    end

    sequence(:title) { |n| "Live Jazz Night #{n}" }
    association :venue, strategy: :build
    sequence(:date) { |n| Date.today + n }
    description { "An intimate evening of live music in the heart of the city." }
    association :price, strategy: :build
    is_free do
      case price
      when WeeklyLocalEvents::Price then price.is_free
      when Hash then price[:is_free] || false
      else false
      end
    end
    sequence(:url) { |n| "https://www.eventbrite.com/e/live-jazz-night-#{n}" }
    source { "EventBrite" }
    time { "7:00 PM" }
    category { "Music" }
    tags { %w[jazz live-music] }
    currency { "USD" }

    initialize_with do
      # Reference every declared attribute so FactoryBot does not try to
      # assign them again through setters (these models are immutable).
      values = {
        title: title,
        description: description,
        date: date,
        venue: venue,
        price: price,
        is_free: is_free,
        url: url,
        source: source,
        time: time,
        category: category,
        tags: tags,
        currency: currency,
      }

      price_object = values[:price]
      price_value = case price_object
                    when WeeklyLocalEvents::Price then price_object.display
                    when Hash then price_object[:display]
                    else price_object.to_s
                    end
      currency_value = case price_object
                       when WeeklyLocalEvents::Price then price_object.currency
                       when Hash then price_object[:currency] || values[:currency]
                       else values[:currency]
                       end
      attributes = {
        title: original ? "#{original.title}!" : values[:title],
        description: values[:description],
        date: original ? original.date : values[:date],
        time: values[:time],
        venue: original ? original.venue : values[:venue],
        price: original ? original.price : price_value,
        currency: currency_value,
        url: values[:url],
        source: values[:source],
        category: values[:category],
        is_free: values[:is_free],
        tags: values[:tags],
      }

      supported = WeeklyLocalEvents::Event.instance_method(:initialize).parameters.map(&:last)
      WeeklyLocalEvents::Event.new(**attributes.select { |key, _| supported.include?(key) })
    end

    factory :free_event do
      title { "Free Community Concert" }
      association :price, factory: :free_price, strategy: :build
      category { "Community" }
    end

    factory :paid_event do
      title { "Headliner Live Show" }
      association :price, factory: :premium_price, strategy: :build
      source { "Do512" }
    end

    # Pass `original: an_event` to copy the venue/date/title dedup fields.
    factory :duplicate_event

    factory :past_event do
      sequence(:date) { |n| Date.today - n }
    end
  end
end
