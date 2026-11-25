# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:test) do |t|
  t.rspec_opts = ['--format documentation', '--color']
end

RuboCop::RakeTask.new(:lint) do |t|
  t.options = ['--format progress']
end

task :format do
  sh 'rubocop -a'
end

task default: :test
