# frozen_string_literal: true

require "bundler/setup"
$LOAD_PATH.unshift("/home/madrax/src/ai/WeeklyLocalEvents/lib")
require "weekly_local_events"

app = WeeklyLocalEvents::Application.new
result = app.run
puts "Result: #{result.to_s}"
puts "Result.to_h: #{result.to_h}"
puts "Result.total: #{result.total}"
puts "Result.sources: #{result.sources}"
