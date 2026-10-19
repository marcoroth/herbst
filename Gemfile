# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Herb main has the Herb::Engine fix for adjacent statement tags (marcoroth/herb#2814).
# A git-sourced Herb needs a git-sourced Prism to build its C extension.
gem "herb", github: "marcoroth/herb", branch: "main"
gem "prism", github: "ruby/prism", tag: "v1.9.0"

gem "haml", require: false
gem "irb"
gem "minitest", "~> 5.16"
gem "rake", "~> 13.0"
gem "rbs-inline", require: false
gem "rubocop", "~> 1.21"
gem "slim", require: false
gem "steep", require: false
