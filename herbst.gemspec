# frozen_string_literal: true

require_relative "lib/herbst/version"

Gem::Specification.new do |spec|
  spec.name = "herbst"
  spec.version = Herbst::VERSION
  spec.authors = ["Marco Roth"]
  spec.email = ["marco.roth@intergga.ch"]

  spec.summary = "Herb Syntax Tree - Unified syntax tree for HTML templating languages"
  spec.description = "Herbst provides tooling to translate Haml, Slim, and other HTML templating languages into the unified syntax tree used by Herb, enabling HTML-aware tooling across different HTML templating languages."
  spec.homepage = "https://github.com/marcoroth/herbst"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/marcoroth/herbst"
  spec.metadata["changelog_uri"] = "https://github.com/marcoroth/herbst/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "herbst.gemspec",
    "LICENSE.txt",
    "Rakefile",
    "README.md",
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "exe/*"
  ]

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "haml", ">= 6"
  spec.add_dependency "herb", ">= 0.11"
end
