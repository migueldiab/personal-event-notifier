# frozen_string_literal: true

require "dry/struct"
require "dry/types"

module WeeklyLocalEvents
  module Core
    class Config < Dry::Struct
      attribute :telegram_channel_id, Types::String
      attribute :telegram_token, Types::String.optional, default: ""
      attribute :time_zone, Types::String, default: "America/Chicago"
      attribute :lookahead_days, Types::Integer, default: 7
      attribute :sources, Types::Array.of(Types::String),
                default: %w[austinchronicle do512 communityimpact]
      attribute :interests, Types::Array.of(Types::String),
                default: %w[Oscars "Rock & Roll Hall of Fame" SXSW
                            "Edinburgh Fringe" "Macy's Parade"
                            "Rio Carnival" "Notting Hill Carnival"
                            Olympics Oktoberfest]

      def self.load(path: nil)
        if path && File.exist?(path)
          YAML.load_file(path)
        else
          defaults
        end
      end

      def self.defaults
        {
          "telegram_channel_id" => ENV.fetch("TELEGRAM_CHANNEL_ID", ""),
          "telegram_token" => ENV.fetch("TELEGRAM_TOKEN", ""),
          "time_zone" => "America/Chicago",
          "lookahead_days" => 7,
          "sources" => %w[austinchronicle do512 communityimpact],
          "interests" => %w[Oscars "Rock & Roll Hall of Fame" SXSW
                            "Edinburgh Fringe" "Macy's Parade"
                            "Rio Carnival" "Notting Hill Carnival"
                            Olympics Oktoberfest]
        }
      end
    end
  end
end
