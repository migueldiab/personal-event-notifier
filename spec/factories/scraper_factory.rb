# frozen_string_literal: true

FactoryBot.define do
  # The registry stores scraper *classes* and builds instances on demand, so
  # this factory returns a BaseScraper subclass rather than an instance.
  factory :test_scraper_class, class: "Class" do
    transient do
      scraper_name { "test_scraper" }
      scraper_events { [] }
      scraper_url { nil }
    end

    initialize_with do
      name_value = scraper_name
      events_value = scraper_events
      url_value = scraper_url

      Class.new(WeeklyLocalEvents::BaseScraper) do
        define_method(:name) { name_value }

        define_method(:events) do
          # Exercises the real HTTP path so WebMock can stub scraper calls.
          fetch(url_value) if url_value
          events_value
        end
      end
    end
  end
end
