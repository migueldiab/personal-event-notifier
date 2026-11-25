# frozen_string_literal: true

# require "rspec"
require "spec_helper"
require "tempfile"
require "yaml"

# require_relative "../../lib/weekly_local_events"

RSpec.describe WeeklyLocalEvents::Config do
  let(:config_path) { Tempfile.new(["config", ".yml"]).path }
  let(:yaml_content) do
    {
      "notification_channel_id" => "-1004330304115",
      "telegram_bot_token" => "123456:ABC-DEF",
      "sites" => %w[austin_chronicle do512],
      "log_level" => "DEBUG",
      "date_range_days" => 14,
      "request_timeout" => 60,
      "request_delay" => 5,
      "max_retries" => 5,
    }
  end

  before do
    File.write(config_path, yaml_content.to_yaml)
    allow(File).to receive(:expand_path).with("~/.hermes/weekly_local_events/config.yml")
      .and_return(config_path)
  end

  after do
    File.delete(config_path) if File.exist?(config_path)
  end

  describe "#initialize" do
    it "loads config from YAML file" do
      config = described_class.new
      expect(config.sites).to eq(%w[austin_chronicle do512])
      expect(config.log_level).to eq("DEBUG")
      expect(config.date_range_days).to eq(14)
      expect(config.request_timeout).to eq(60)
      expect(config.request_delay).to eq(5)
      expect(config.max_retries).to eq(5)
    end

    it "uses default values when YAML keys are missing" do
      File.write(config_path, {
        "notification_channel_id" => "-1004330304115",
        "telegram_bot_token" => "123456:ABC-DEF",
      }.to_yaml)

      config = described_class.new
      expect(config.sites).to eq(%w[austin_chronicle do512 community_impact])
      expect(config.log_level).to eq("INFO")
      expect(config.date_range_days).to eq(7)
      expect(config.request_timeout).to eq(30)
      expect(config.request_delay).to eq(2)
      expect(config.max_retries).to eq(3)
    end

    it "validates required keys are present" do
      File.write(config_path, { "notification_channel_id" => "-1004330304115" }.to_yaml)

      expect { described_class.new }.to raise_error(
        WeeklyLocalEvents::ConfigError,
        /Required config key 'telegram_bot_token'/
      )
    end

    it "raises ConfigError for invalid YAML" do
      File.write(config_path, "{ invalid yaml: [broken")

      expect { described_class.new }.to raise_error(
        WeeklyLocalEvents::ConfigError,
        /Invalid YAML/
      )
    end
  end

  describe "ENV overrides" do
    around do |example|
      original = ENV["TELEGRAM_BOT_TOKEN"]
      ENV["TELEGRAM_BOT_TOKEN"] = "env_override_token"
      example.run
      ENV["TELEGRAM_BOT_TOKEN"] = original
    end

    it "ENV variables override YAML values" do
      config = described_class.new
      expect(config.telegram_bot_token).to eq("env_override_token")
    end
  end

  describe "#logger" do
    it "returns a Logger with the configured level" do
      config = described_class.new
      expect(config.logger).to be_a(Logger)
      expect(config.logger.level).to eq(Logger::DEBUG)
    end
  end

  describe "fallback to ENV" do
    before do
      File.write(config_path, {
        "notification_channel_id" => "env_channel",
        "telegram_bot_token" => "env_token",
      }.to_yaml)
    end

    it "falls back to ENV when YAML key is nil" do
      allow(File).to receive(:expand_path)
        .with("~/.hermes/weekly_local_events/config.yml")
        .and_return(config_path)

      config = described_class.new
      expect(config.telegram_bot_token).to eq("env_token")
    end
  end
end
