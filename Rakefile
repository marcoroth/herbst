# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create
RuboCop::RakeTask.new

desc "Generate RBS signatures from the inline annotations"
task :rbs do
  sh "bundle exec rbs-inline --opt-out --output=sig/ lib/"
end

desc "Type check with Steep"
task :steep do
  sh "bundle exec steep check"
end

task default: [:test, :rubocop, :steep]
