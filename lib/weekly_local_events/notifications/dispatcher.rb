# frozen_string_literal: true

require "telegram/bot"

module WeeklyLocalEvents
  module Notifications
    class Dispatcher
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def dispatch(events)
        return if events.empty?
        return if config.telegram_channel_id.empty?

        message = build_message(events)
        Telegram::Bot::Client.run(token: config.telegram_token) do |bot|
          bot.execute(Telegram::Bot::Types::SendMessage.new(
            chat_id: config.telegram_channel_id,
            text: message,
            parse_mode: "HTML"
          ))
        end
      end

      private

      def build_message(events)
        lines = ["📅 *Upcoming Events (next #{config.lookahead_days} days):*"]
        lines << ""
        events.each do |event|
          lines << "*#{event.title}*"
          lines << "📆 #{event.date}"
          lines << "📍 #{event.location}"
          lines << "📺 #{event.broadcast_info}" unless event.broadcast_info.empty?
          lines << ""
        end
        lines.join("\n")
      end
    end
  end
end
