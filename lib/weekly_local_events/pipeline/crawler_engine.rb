# frozen_string_literal: true

require "nokogiri"

module WeeklyLocalEvents
  module Pipeline
    module CrawlerEngine
      def self.for_source(source)
        case source
        when "austinchronicle"
          AustinChronicleParser
        when "do512"
          Do512Parser
        when "communityimpact"
          CommunityImpactParser
        else
          raise ArgumentError, "Unknown source: #{source}"
        end
      end

      class AustinChronicleParser
        BASE_URL = "https://www.austinchronicle.com/calendar"

        def fetch
          # Placeholder: implement actual scraping
          []
        end
      end

      class Do512Parser
        BASE_URL = "https://www.do512.com"

        def fetch
          # Placeholder: implement actual scraping
          []
        end
      end

      class CommunityImpactParser
        BASE_URL = "https://www.communityimpact.com"

        def fetch
          # Placeholder: implement actual scraping
          []
        end
      end
    end
  end
end
