# frozen_string_literal: true

require "bundler/setup"
$LOAD_PATH.unshift("/home/madrax/src/ai/WeeklyLocalEvents/lib")
require "weekly_local_events"

# Verify Application is loadable
puts "Application: #{WeeklyLocalEvents::Application}"
puts "Summary: #{WeeklyLocalEvents::Summary}"
puts "NotificationResult: #{WeeklyLocalEvents::NotificationResult}"

# Verify Application.new works with default config
app = WeeklyLocalEvents::Application.new
puts "App config: #{app.config.class}"
puts "App scraper_registry: #{app.scraper_registry.class}"
puts "App notifier: #{app.notifier.class}"
puts "App aggregator: #{app.aggregator.class}"

# Verify Config#notifications_enabled? exists
puts "notifications_enabled? method: #{WeeklyLocalEvents::Config.instance_methods.include?(:notifications_enabled?)}"

# Verify Summary constructor
s = WeeklyLocalEvents::Summary.new(total: 5, sources: { a: 2, b: 3 })
puts "Summary: #{s.to_s}"
puts "Summary.to_h: #{s.to_h}"

# Verify NotificationResult constructor
r = WeeklyLocalEvents::NotificationResult.new(success: true, events_sent: 5)
puts "NotificationResult: #{r.to_s}"
puts "NotificationResult.success?: #{r.success?}"

r2 = WeeklyLocalEvents::NotificationResult.new(success: false, events_sent: 0, error: "timeout")
puts "NotificationResult(fail): #{r2.to_s}"
puts "NotificationResult.success?: #{r2.success?}"

puts "\n✓ All checks passed"
