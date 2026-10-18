# frozen_string_literal: true

require "cgi/escape"
require "haml"
require "temple"

module Herbst
  module Haml
    class Attributes
      include Builder

      # @rbs @warnings: Array[String]

      #: (Array[String]) -> void
      def initialize(warnings)
        @warnings = warnings
      end

      #: (::Haml::Parser::ParseNode) -> Array[Herb::AST::Node]
      def compile(node)
        value = node.value
        dynamic = value[:dynamic_attributes]
        sources = [dynamic.new, dynamic.old].compact

        if value[:object_ref] != :nil
          warn(node, "object references (`[#{value[:object_ref]}]`) are not supported and were dropped")
        end

        hashes = sources.filter_map { |source| ::Haml::AttributeParser.parse(source) }
        return fallback(node, sources) if hashes.size < sources.size || hashes.any? { |hash| hash.any? { |_key, code| code.empty? } }

        values = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[[Symbol, untyped]]]
        value[:attributes].each { |key, static| values[key.to_s] << [:static, static] }
        hashes.each { |hash| hash.each { |key, code| values[key.to_s] << [:dynamic, code] } }

        values.keys.sort.flat_map { |key| compile_attribute(key, values[key]) }
      end

      private

      #: (String, Array[[Symbol, untyped]]) -> Array[Herb::AST::Node]
      def compile_attribute(key, values)
        # Literal-only Ruby (checked by Temple::StaticAnalyzer) is folded into static values.
        values = values.map do |type, value|
          type == :dynamic && literal?(value) ? [:static, eval(value)] : [type, value] # rubocop:disable Security/Eval
        end #: Array[[Symbol, untyped]]

        case key
        when "class"
          compile_joined(key, values, " ") do |code|
            array_literal?(code) ? "#{code}.flatten.select(&:itself).join(\" \")" : code
          end
        when "id"
          compile_joined(key, values, "_") do |code|
            array_literal?(code) ? "#{code}.flatten.select(&:itself).join(\"_\")" : code
          end
        when "data", "aria"
          compile_hash(key, values.fetch(-1))
        else
          compile_single(key, values.fetch(-1))
        end
      end

      #: (String, Array[[Symbol, untyped]], String) { (String) -> String } -> Array[Herb::AST::Node]
      def compile_joined(key, values, separator)
        statics = values.filter_map { |type, value| value if type == :static }
        statics = statics.flat_map { |value| Array(value).flatten }.select(&:itself).map(&:to_s)
        statics = statics.flat_map { |value| value.split(separator) } if separator == " "
        dynamics = values.filter_map { |type, code| yield(code) if type == :dynamic }

        return [] if statics.empty? && dynamics.empty?

        children = [] #: Array[Herb::AST::Node]
        children << literal(escape(statics.uniq.join(separator))) unless statics.empty?
        dynamics.each do |code|
          children << literal(separator) unless children.empty?
          children << erb(code)
        end

        [attribute(key, children)]
      end

      #: (String, [Symbol, untyped]) -> Array[Herb::AST::Node]
      def compile_hash(prefix, pair)
        type, value = pair

        hash = type == :static ? value : ::Haml::AttributeParser.parse(value)

        unless hash.is_a?(Hash)
          return compile_single(prefix, [type, value]) unless type == :dynamic

          return [erb("tag.attributes(#{prefix}: #{value})")]
        end

        hash.sort_by { |key, _| key.to_s }.flat_map do |key, nested|
          name = "#{prefix}-#{key.to_s.tr("_", "-")}"
          nested_type = type == :static || literal?(nested) ? :static : :dynamic
          nested_value = type == :dynamic && nested_type == :static ? eval(nested) : nested # rubocop:disable Security/Eval

          if nested_value.is_a?(Hash) || (nested_type == :dynamic && ::Haml::AttributeParser.parse(nested).is_a?(Hash))
            compile_hash(name, [nested_type, nested_value])
          else
            compile_single(name, [nested_type, nested_value])
          end
        end
      end

      #: (String, [Symbol, untyped]) -> Array[Herb::AST::Node]
      def compile_single(key, pair)
        type, value = pair

        if type == :static
          case value
          when true
            [attribute(key)]
          when false, nil
            []
          else
            [attribute(key, [literal(escape(value.to_s))])]
          end
        elsif boolean?(key)
          [erb("#{key.inspect} if #{value}")]
        else
          [attribute(key, [erb(value)])]
        end
      end

      #: (::Haml::Parser::ParseNode, Array[String]) -> Array[Herb::AST::Node]
      def fallback(node, sources)
        arguments = sources.map { |source| source.strip.delete_prefix("{").delete_suffix("}").strip.delete_suffix(",") }
        warn(node, "dynamic attributes `#{sources.join(" ")}` were converted to `tag.attributes`, which requires Rails 7.1+")

        node.value[:attributes].sort.flat_map { |key, value| compile_single(key, [:static, value]) } + [erb("tag.attributes(#{arguments.join(", ")})")]
      end

      #: (String) -> bool
      def literal?(code)
        Temple::StaticAnalyzer.static?(code)
      end

      #: (String) -> bool
      def array_literal?(code)
        code.strip.start_with?("[")
      end

      #: (String) -> bool
      def boolean?(key)
        ::Haml::BOOLEAN_ATTRIBUTES.include?(key)
      end

      #: (String) -> String
      def escape(value)
        CGI.escapeHTML(value).gsub("<%", "&lt;%")
      end

      #: (::Haml::Parser::ParseNode, String) -> void
      def warn(node, message)
        @warnings << "line #{node.line}: #{message}"
      end
    end
  end
end
