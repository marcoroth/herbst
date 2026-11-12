# frozen_string_literal: true

require "cgi/escape"
require "temple"

module Herbst
  module Haml
    class Attributes
      include Builder

      attr_writer :declared #: Array[Symbol]

      # @rbs @warnings: Array[String]
      # @rbs @declared: Array[Symbol]

      #: (Array[String]) -> void
      def initialize(warnings)
        @warnings = warnings
        @declared = []
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
          compile_class(values)
        when "id"
          compile_id(values)
        when "data", "aria"
          compile_hash(key, values.fetch(-1))
        else
          compile_single(key, values.fetch(-1))
        end
      end

      #: (Array[[Symbol, untyped]]) -> Array[Herb::AST::Node]
      def compile_class(values)
        if static?(values)
          return [attribute("class", [literal(escape(::Haml::AttributeBuilder.build_class(false, *values.map(&:last))))])]
        end

        [attribute("class", [erb(values.one? ? single_class(values.fetch(0).last) : merged_classes(values))])]
      end

      #: (Array[[Symbol, untyped]]) -> Array[Herb::AST::Node]
      def compile_id(values)
        return [attribute("id", [literal(escape(::Haml::AttributeBuilder.build_id(false, *values.map(&:last))))])] if static?(values)

        [attribute("id", [erb("#{ruby_list(values)}.flatten.select { |item| item }.join(\"_\")")])]
      end

      #: (String) -> String
      def single_class(code)
        value = ATTRIBUTE_VALUE

        "(#{value} = (#{code})).is_a?(String) ? #{value} : #{value}.is_a?(Array) ? #{value}.flatten.select { |item| item }.map(&:to_s).uniq.join(\" \") : #{value} ? #{value}.to_s : \"\""
      end

      #: (Array[[Symbol, untyped]]) -> String
      def merged_classes(values)
        "#{ruby_list(values)}.flat_map { |value| value.is_a?(String) ? value.split(\" \") : value.is_a?(Array) ? value.flatten.select { |item| item } : value ? [value] : [] }.map(&:to_s).uniq.join(\" \")"
      end

      #: (Array[[Symbol, untyped]]) -> String
      def ruby_list(values)
        "[#{values.map { |type, value| type == :static ? value.inspect : "(#{value})" }.join(", ")}]"
      end

      #: (Array[[Symbol, untyped]]) -> bool
      def static?(values)
        values.all? { |type, _value| type == :static }
      end

      #: (String, [Symbol, untyped]) -> Array[Herb::AST::Node]
      def compile_hash(prefix, pair)
        type, value = pair

        hash = type == :static ? value : ::Haml::AttributeParser.parse(value)

        unless hash.is_a?(Hash)
          return compile_single(prefix, [type, value]) unless type == :dynamic

          return [conditional_attribute(prefix, value, true, declared: @declared, expansion: :haml)]
        end

        hash.sort_by { |key, _| key.to_s }.flat_map do |key, nested|
          name = "#{prefix}-#{key.to_s.tr("_", "-")}"
          nested_type = type == :static || literal?(nested) ? :static : :dynamic
          nested_value = type == :dynamic && nested_type == :static ? eval(nested) : nested # rubocop:disable Security/Eval

          if nested_value.is_a?(Hash) || (nested_type == :dynamic && ::Haml::AttributeParser.parse(nested).is_a?(Hash))
            compile_hash(name, [nested_type, nested_value])
          else
            compile_single(name, [nested_type, nested_value], expansion: :haml)
          end
        end
      end

      #: (String, [Symbol, untyped], ?expansion: Symbol?) -> Array[Herb::AST::Node]
      def compile_single(key, pair, expansion: nil)
        type, value = pair

        if type == :static
          return [attribute(key, [literal(escape(value.to_s))])] unless boolean?(key)

          case value
          when true
            [attribute(key)]
          when false, nil
            []
          else
            [attribute(key, [literal(escape(value.to_s))])]
          end
        else
          split = split_interpolation(value)
          return [attribute(key, split)] if split
          return [attribute(key, [erb(value)])] unless boolean?(key)

          [conditional_attribute(key, value, true, declared: @declared, expansion: expansion)]
        end
      end

      #: (String) -> Array[Herb::AST::Node]?
      def split_interpolation(code)
        result = Prism.parse(code)
        statements = result.value.statements.body
        string = statements.first

        return nil unless result.success? && statements.one? && string.is_a?(Prism::InterpolatedStringNode) && string.opening == "\""

        string.parts.map do |part|
          case part
          when Prism::StringNode
            literal(escape(part.unescaped))
          when Prism::EmbeddedStatementsNode
            body = part.statements&.body
            return nil unless body&.one?

            erb(body.first.slice)
          else
            return nil
          end
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
      def boolean?(key)
        ::Haml::BOOLEAN_ATTRIBUTES.include?(key) || key.start_with?("data-", "aria-") || ["data", "aria"].include?(key)
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
