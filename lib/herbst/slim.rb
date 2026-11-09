# frozen_string_literal: true

begin
  require "slim"
rescue LoadError
  raise Herbst::Error, "Converting Slim templates requires the slim gem. Add `gem \"slim\"` to your Gemfile."
end

module Herbst
  # Converts Slim templates into Herb's syntax tree and ERB.
  #
  #   Herbst::Slim.parse("p = greeting")   # => Herb::AST::DocumentNode
  #   Herbst::Slim.to_erb("p = greeting")  # => "<p><%= greeting %></p>"
  #
  # The slim gem is only needed when converting Slim, so it isn't a dependency of Herbst.
  #
  module Slim
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

require_relative "slim/parser"
require_relative "slim/converter"
