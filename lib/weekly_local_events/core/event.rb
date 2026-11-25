# frozen_string_literal: true

require "dry/struct"
require "dry/types"

module WeeklyLocalEvents
  module Core
    class Event < Dry::Struct
      attribute :id, Types::String
      attribute :title, Types::String
      attribute :event_type, Types::String
      attribute :date, Types::Params::DateTime
      attribute :location, Types::String
      attribute :source, Types::String
      attribute :description, Types::String.optional, default: ""
      attribute :url, Types::String.optional, default: ""
      attribute :broadcast_info, Types::String.optional, default: ""

      def self.from_hash(hash)
        new(hash.transform_keys(&:to_sym))
      end
    end
  end
end
