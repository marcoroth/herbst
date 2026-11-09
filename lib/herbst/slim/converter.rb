# frozen_string_literal: true

require "cgi/escape"
require "herb"
require "herb/html/util"
require "temple"

module Herbst
  module Slim
    class Converter < Herbst::Converter
      HYPHEN_ATTRIBUTES = ["data", "aria"].freeze #: Array[String]

      # @rbs @options: Hash[Symbol, untyped]

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        super()

        @options = { default_tag: "div" }.merge(options)
      end

      #: (String) -> Herb::AST::DocumentNode
      def convert(source)
        parser = Parser.new(@options)
        expression = parser.call(source)
        parser.dropped_directives.each { |line, directive| warn_dropped_directive(line, directive) }
        children = join(prepare([expression]), 0)

        finish(document(children))
      rescue ::Slim::Parser::SyntaxError => e
        raise Herbst::Error, e.message
      end

      private

      #: (Integer, String) -> void
      def warn_dropped_directive(line, directive)
        warn(line, "`/ #{directive}` is a Slim comment, which is dropped when parsing. Use `-# #{directive}` to keep the directive")
      end

      #: (Array[untyped]) -> Array[untyped]
      def prepare(expressions)
        items = expressions.flat_map { |expression| flatten(expression) }
        grouped = [] #: Array[untyped]

        items.each do |item|
          if control?(item) && item[2].match?(::Slim::EndInserter::END_RE)
            warn(nil, "`- #{item[2].strip}` was dropped, since Slim closes blocks itself")
          elsif clause?(item) && grouped.last&.first == :herbst_control
            grouped.last[3] << item
          elsif control?(item)
            clauses = [] #: Array[untyped]
            grouped << [:herbst_control, item[2], item[3], clauses]
          else
            grouped << item
          end
        end

        grouped
      end

      #: (untyped) -> Array[untyped]
      def flatten(expression)
        return [] if expression.nil? || expression == [:newline]
        return expression.drop(1).flat_map { |child| flatten(child) } if expression.first == :multi

        [expression]
      end

      #: (untyped) -> bool
      def control?(item)
        item[0] == :slim && item[1] == :control
      end

      #: (untyped) -> bool
      def clause?(item)
        control?(item) && item[2].match?(::Slim::EndInserter::ELSE_RE)
      end

      #: (Array[untyped], Integer) -> Array[Herb::AST::Node]
      def join(items, depth)
        result = [] #: Array[Herb::AST::Node]
        previous = nil #: untyped

        items.each do |item|
          converted = convert_item(item, depth)
          next if converted.empty?

          result << text(newline(depth)) if previous && (block?(previous) || block?(item))
          result.concat(converted)
          previous = item
        end

        result
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def body(expression, depth)
        items = prepare([expression])
        children = join(items, depth + 1)
        return children if children.empty?

        children.unshift(text(newline(depth + 1))) if block?(items.first)
        children.push(text(newline(depth))) if block?(items.last)

        children
      end

      #: (untyped) -> bool
      def block?(item)
        return false unless item[0] == :html

        case item[1]
        when :tag
          !Herb::HTML::Elements::INLINE_ELEMENTS.include?(item[2].to_s)
        when :doctype
          true
        else
          false
        end
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_item(item, depth)
        case item[0]
        when :static
          text_nodes(item[1])
        when :html
          convert_html(item, depth)
        when :slim
          convert_slim(item, depth)
        when :herbst_control
          convert_control(item[1], item[2], item[3], depth)
        else
          unexpected(item)
        end
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_html(item, depth)
        case item[1]
        when :tag
          convert_tag(item, depth)
        when :doctype
          convert_doctype(item[2])
        when :comment
          [comment(convert_text(item[2]))]
        when :condcomment
          [comment([literal("[#{item[2]}]>"), *body(item[3], depth), literal("<![endif]")])]
        else
          unexpected(item)
        end
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_slim(item, depth)
        case item[1]
        when :text
          convert_text(item[3])
        when :interpolate
          interpolate(item[2])
        when :output
          convert_output(item, depth)
        when :embedded
          convert_embedded(item, depth)
        else
          unexpected(item)
        end
      end

      #: (untyped) -> bot
      def unexpected(item)
        raise Herbst::Error, "Unexpected Slim expression: #{item.inspect}"
      end

      #: (untyped) -> Array[Herb::AST::Node]
      def convert_text(expression)
        flatten(expression).flat_map do |item|
          item[0] == :slim && item[1] == :interpolate ? interpolate(item[2]) : convert_item(item, 0)
        end
      end

      #: (String, ?escape_static: bool) -> Array[Herb::AST::Node]
      def interpolate(string, escape_static: false)
        parts = ::Slim::Interpolation.new.call([:slim, :interpolate, string])

        flatten(parts).flat_map do |part|
          if part[0] == :static
            text_nodes(escape_static ? CGI.escapeHTML(part[1]) : part[1])
          else
            [erb(part[3], opening: part[2] ? "<%=" : "<%==")]
          end
        end
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_tag(item, depth)
        _html, _tag, name, attributes, content = item
        raise Herbst::UnsupportedError, "a splat that sets the tag name, as in `*{tag: ...}`, is not supported" if name == "*"

        attributes = convert_attributes(attributes)

        if Herb::HTML::Util.void_element?(name.to_s)
          return [element(name.to_s, attributes: attributes), *join(prepare([content]), depth)]
        end

        children = content.nil? ? [] : body(content, depth) #: Array[Herb::AST::Node]

        [element(name.to_s, attributes: attributes, body: children, self_closing: content.nil?)]
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_output(item, depth)
        _slim, _output, escape, code, content = item
        code, comment = split_comment(code)
        opening = escape ? "<%=" : "<%=="
        children = body(content, depth)

        return [*comment_nodes(comment), erb(code, opening: opening)] if children.empty? && !opens_block?(code)

        [*comment_nodes(comment), erb_block(block_code(code), children, opening: opening)]
      end

      #: (String, untyped, Array[untyped], Integer) -> Array[Herb::AST::Node]
      def convert_control(code, content, clause_items, depth)
        code, comment = split_comment(code)
        return comment_nodes(comment) if code.empty?

        content, clause_items = nested_clauses(content) if keyword(code) == "case" && clause_items.empty?

        children = body(content, depth)
        return [*comment_nodes(comment), erb(code, opening: "<%")] if children.empty? && clause_items.empty? && !code.match?(::Slim::EndInserter::IF_RE)

        clauses = clause_items.map do |clause|
          clause_code, clause_comment = split_comment(clause[2])
          [clause_code, keyword(clause_code), [*comment_nodes(clause_comment), *body(clause[3], depth)], nil] #: Herbst::Converter::clause
        end

        [*comment_nodes(comment), control(block_code(code), keyword(code), children, clauses, depth)]
      end

      # Slim also accepts the `- when` lines of a `- case` indented under it.
      #
      #: (untyped) -> [untyped, Array[untyped]]
      def nested_clauses(content)
        items = prepare([content])
        first = items.first
        return [content, []] unless items.size == 1 && first[0] == :herbst_control && ["when", "in"].include?(keyword(first[1]))

        [[:multi], [[:slim, :control, first[1], first[2]], *first[3]]]
      end

      # Slim compiles each line of code onto its own line of Ruby, but in ERB the next tag follows on
      # the same line, where a trailing comment would swallow it. The comment moves into an ERB comment.
      #
      #: (String) -> [String, String?]
      def split_comment(code)
        comment = Prism.parse(code).comments.last
        return [code, nil] unless comment && code.byteslice(comment.location.end_offset, code.bytesize).to_s.strip.empty?

        [code.byteslice(0, comment.location.start_offset).to_s.rstrip, comment.slice.delete_prefix("#").strip]
      end

      #: (String?) -> Array[Herb::AST::Node]
      def comment_nodes(comment)
        comment.nil? || comment.empty? ? [] : [erb_comment(comment.gsub("%>", "% >"))]
      end

      #: (String) -> bool
      def opens_block?(code)
        code.match?(/\bdo\s*(\|[^|]*\|)?\s*\z/)
      end

      #: (String) -> String
      def block_code(code)
        code.match?(::Slim::DoInserter::BLOCK_REGEX) ? code : "#{code} do"
      end

      #: (String) -> Array[Herb::AST::Node]
      def convert_doctype(type)
        html = Temple::HTML::Fast.new(format: :html).call([:html, :doctype, type])[1]

        Herb.parse(html, track_whitespace: true).value.children
      rescue Temple::FilterError => e
        raise Herbst::UnsupportedError, "`doctype #{type}` is not supported: #{e.message}"
      end

      #: (untyped, Integer) -> Array[Herb::AST::Node]
      def convert_embedded(item, depth)
        _slim, _embedded, engine, content, attributes = item
        source = flatten(content).filter_map { |part| part[2] if part[1] == :interpolate }.join

        case engine
        when "javascript"
          [element("script", attributes: convert_attributes(attributes), body: embedded_body(source, depth))]
        when "css"
          [element("style", attributes: convert_attributes(attributes), body: embedded_body(source, depth))]
        when "ruby"
          [erb(source, opening: "<%")]
        else
          raise Herbst::UnsupportedError, "the `#{engine}:` embedded engine is not supported"
        end
      end

      #: (String, Integer) -> Array[Herb::AST::Node]
      def embedded_body(source, _depth)
        interpolate(source)
      end

      #: (untyped) -> Array[Herb::AST::Node]
      def convert_attributes(expression)
        values = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[untyped]]
        splats = [] #: Array[String]

        expression.drop(2).each do |attribute|
          if attribute[1] == :splat
            splats << attribute[2]
          else
            values[attribute[2].to_s] << attribute[3]
          end
        end

        nodes = values.keys.sort.flat_map do |name|
          name == "class" ? convert_class(values.fetch(name)) : convert_attribute(name, values.fetch(name).fetch(-1))
        end

        nodes + splats.map do |code|
          warn(nil, "`*#{code}` was converted to `tag.attributes`, which requires Rails 7.1+")
          erb("tag.attributes(**#{code})")
        end
      end

      #: (Array[untyped]) -> Array[Herb::AST::Node]
      def convert_class(values)
        parts = values.filter_map do |value|
          nodes = class_value(value)
          nodes unless nodes.empty?
        end

        return [] if parts.empty?

        [attribute("class", parts.flat_map.with_index { |nodes, index| index.zero? ? nodes : [literal(" "), *nodes] })]
      end

      #: (untyped) -> Array[Herb::AST::Node]
      def class_value(value)
        case value[0]
        when :static
          value[1].to_s.empty? ? [] : [literal(value[1].to_s)]
        when :escape
          attribute_value(value[2][2], value[1])
        when :slim
          _slim, _attrvalue, escape, code = value
          return [literal(static_class(code))] if Temple::StaticAnalyzer.static?(code)

          code = "#{code}.flatten.map(&:to_s).reject(&:empty?).join(\" \")" if code.strip.start_with?("[")
          [erb(code, opening: escape ? "<%=" : "<%==")]
        else
          []
        end
      end

      #: (String, bool) -> Array[Herb::AST::Node]
      def attribute_value(string, escape)
        interpolate(string, escape_static: escape).map do |node|
          node.is_a?(Herb::AST::HTMLTextNode) ? literal(node.content.to_s) : node
        end
      end

      #: (String) -> String
      def static_class(code)
        value = eval(code) # rubocop:disable Security/Eval
        value = Array(value).flatten.map(&:to_s).reject(&:empty?).join(" ") if value.is_a?(Array)

        CGI.escapeHTML(value.to_s)
      end

      #: (String, untyped) -> Array[Herb::AST::Node]
      def convert_attribute(name, value)
        case value[0]
        when :static
          [attribute(name, [literal(value[1].to_s)])]
        when :multi
          [attribute(name)]
        when :escape
          [attribute(name, attribute_value(value[2][2], value[1]))]
        when :slim
          if HYPHEN_ATTRIBUTES.include?(name) && value[3].strip.start_with?("{")
            convert_hash_attribute(name, value[2], value[3])
          else
            convert_code_attribute(name, value[2], value[3])
          end
        else
          unexpected(value)
        end
      end

      #: (String, bool, String) -> Array[Herb::AST::Node]
      def convert_hash_attribute(name, escape, code)
        entries = hash_entries(code)

        unless entries
          warn(nil, "`#{name}=#{code}` was converted to `tag.attributes`, which requires Rails 7.1+")
          return [erb("tag.attributes(#{name}: #{code})")]
        end

        entries.flat_map do |key, value|
          if value.strip.start_with?("{")
            convert_hash_attribute("#{name}-#{key}", escape, value)
          else
            convert_code_attribute("#{name}-#{key}", escape, value)
          end
        end
      end

      #: (String) -> Array[[String, String]]?
      def hash_entries(code)
        hash = Prism.parse(code).value.statements.body.first
        return nil unless hash.is_a?(Prism::HashNode)

        entries = [] #: Array[[String, String]]

        hash.elements.each do |element|
          return nil unless element.is_a?(Prism::AssocNode)

          key = element.key
          return nil unless key.is_a?(Prism::SymbolNode) || key.is_a?(Prism::StringNode)

          entries << [key.unescaped, element.value.slice]
        end

        entries
      end

      #: (String, bool, String) -> Array[Herb::AST::Node]
      def convert_code_attribute(name, escape, code)
        case code.strip
        when "true"
          [attribute(name)]
        when "false", "nil"
          []
        else
          if Temple::StaticAnalyzer.static?(code)
            value = eval(code) # rubocop:disable Security/Eval
            return convert_code_attribute(name, escape, value.inspect) if [true, false, nil].include?(value)

            return [attribute(name, [literal(escape ? CGI.escapeHTML(value.to_s) : value.to_s)])]
          end

          if Herb::HTML::Util.boolean_attribute?(name)
            [erb("#{name.inspect} if #{code}")]
          else
            [attribute(name, [erb(code, opening: escape ? "<%=" : "<%==")])]
          end
        end
      end
    end
  end
end
