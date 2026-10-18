# frozen_string_literal: true

require "herb"
require "json"

module Herbst
  # Checks that printed ERB parses back into exactly the tree it was printed from.
  #
  # The ERB is parsed with `track_whitespace: true`, and every node, field, token value and
  # whitespace node is compared. Only source positions and Prism data are ignored, since a
  # built tree doesn't have them.
  #
  #   Herbst::RoundTrip.difference(document, erb) # => nil, or where the trees differ
  #
  module RoundTrip
    POSITIONAL_FIELDS = ["location", "range", "then_keyword", "prism_node", "prism_context", "analyzed_ruby"].freeze #: Array[String]

    #: (Herb::AST::DocumentNode, String) -> String?
    def self.difference(document, erb)
      result = Herb.parse(erb, track_whitespace: true)

      unless result.errors.empty?
        return "printed ERB has parse errors:\n#{result.errors.map { |error| "  #{error.message}" }.join("\n")}"
      end

      tree_difference(comparable(document), comparable(result.value), "document")
    end

    #: (Herb::AST::Node) -> untyped
    def self.comparable(node)
      strip_positions(JSON.parse(node.to_json))
    end

    #: (untyped) -> untyped
    def self.strip_positions(value)
      case value
      when Hash
        value.except(*POSITIONAL_FIELDS).transform_values { |child| strip_positions(child) }
      when Array
        value.map { |child| strip_positions(child) }
      else
        value
      end
    end

    #: (untyped, untyped, String) -> String?
    def self.tree_difference(built, parsed, path)
      return nil if built == parsed

      if built.is_a?(Hash) && parsed.is_a?(Hash) && built["type"] == parsed["type"]
        (built.keys | parsed.keys).each do |key|
          difference = tree_difference(built[key], parsed[key], "#{path}.#{key}")
          return difference if difference
        end
      elsif built.is_a?(Array) && parsed.is_a?(Array) && built.size == parsed.size
        built.each_index do |index|
          difference = tree_difference(built[index], parsed[index], "#{path}[#{index}]")
          return difference if difference
        end
      end

      "printed ERB parses into a different tree at #{path}\n  " \
        "built:  #{built.inspect[0, 300]}\n  " \
        "parsed: #{parsed.inspect[0, 300]}"
    end
  end
end
