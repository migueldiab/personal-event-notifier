# frozen_string_literal: true

require "spec_helper"

RSpec.describe WeeklyLocalEvents::Notifier do
  subject(:notifier) { described_class.new(config) }

  let(:config) { WeeklyLocalEvents::Config.new }

  describe "#notify" do
    context "when notifications are disabled" do
      before do
        allow(config).to receive(:notifications_enabled?).and_return(false)
      end

      it "does nothing" do
        expect { notifier.notify([]) }.not_to raise_error
      end
    end

    context "when notifications are enabled" do
      before do
        allow(config).to receive(:notifications_enabled?).and_return(true)
        allow(config).to receive(:telegram_bot_token).and_return("test_token")
        allow(config).to receive(:notification_channel_id).and_return("-1004330304115")
        allow(notifier).to receive(:send_telegram_api).and_return(
          WeeklyLocalEvents::TelegramResponse.new(success: true, message_id: 12345)
        )
      end

      it "sends a message to Telegram" do
        events = [
          WeeklyLocalEvents::Event.new(title: "Test Event", date: "2026-12-01", venue: WeeklyLocalEvents::Venue.new(name: "Test Venue"), url: "https://example.com", source: "test"),
        ]
        expect { notifier.notify(events) }.not_to raise_error
      end
    end
  end
end
