# frozen_string_literal: true

begin
  require "haml"
rescue LoadError
  raise Herbst::Error, "Converting Haml templates requires the haml gem. Add `gem \"haml\"` to your Gemfile."
end

module Herbst
  # Converts Haml templates into Herb's syntax tree and ERB.
  #
  #   Herbst::Haml.parse("%p= greeting")   # => Herb::AST::DocumentNode
  #   Herbst::Haml.to_erb("%p= greeting")  # => "<p><%= greeting %></p>\n"
  #
  # To compile Haml, compile its ERB with Herb::Engine:
  #
  #   Herb::Engine.new(Herbst::Haml.to_erb(source), escape: true).src
  #
  # Use Herbst::Haml::Converter directly to read the warnings of a conversion. The haml gem is
  # only needed when converting Haml, so it isn't a dependency of Herbst.
  #
  module Haml
    #: (String, **untyped) -> Herb::AST::DocumentNode
    def self.parse(source, **options)
      Converter.new(options).convert(source)
    end

    #: (String, ?format: bool, **untyped) -> String
    def self.to_erb(source, format: false, **)
      Printer.print(parse(source, **), format: format)
    end
  end
end

require_relative "haml/attributes"
require_relative "haml/filters"
require_relative "haml/converter"
