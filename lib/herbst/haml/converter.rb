# frozen_string_literal: true

module Herbst
  module Haml
    # Converts the tree produced by Haml::Parser into a Herb AST.
    #
    # The resulting tree prints to ERB that renders the same HTML as the Haml
    # template (modulo insignificant whitespace).
    #
    class Converter < Herbst::Converter
      MID_BLOCK_KEYWORDS = ::Haml::Parser::MID_BLOCK_KEYWORDS - ["end"] #: Array[String]
      ESCAPED_INTERPOLATION = /\AHaml::Util\.escape_html_safe\(\((.*)\)\.to_s\)\z/m #: Regexp

      # @rbs!
      #   type haml_clause = [::Haml::Parser::ParseNode, Array[::Haml::Parser::ParseNode]]

      # @rbs @options: Hash[Symbol, untyped]
      # @rbs @attributes: Attributes
      # @rbs @filters: Filters
      # @rbs @nuke_inner: Array[bool?]

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        super()

        @options = { escape_html: true }.merge(options)
        @attributes = Attributes.new(@warnings)
        @filters = Filters.new(self)
        @nuke_inner = [false]
      end

      #: (String) -> Herb::AST::DocumentNode
      def convert(source)
        @attributes.declared = declared_names(source)
        root = ::Haml::Parser.new(@options).call(source)
        children = join(root.children, 0)

        children << text("\n") unless children.empty?

        finish(document(children))
      rescue ::Haml::Error => e
        line = e.line
        raise Herbst::Error, line ? "line #{line + 1}: #{e.message}" : e.message
      end

      #: (Array[::Haml::Parser::ParseNode], Integer) -> Array[Herb::AST::Node]
      def join(nodes, depth)
        result = [] #: Array[Herb::AST::Node]
        previous = nil #: ::Haml::Parser::ParseNode?

        nodes.each do |node|
          converted = convert_node(node, depth)
          converted = [converted] unless converted.is_a?(Array)
          next if converted.empty?

          result << text(newline(depth)) if previous && whitespace_between?(previous, node)
          result.concat(converted)
          previous = node
        end

        result
      end

      #: (Array[::Haml::Parser::ParseNode], Integer, ?nuke_edges: bool) -> Array[Herb::AST::Node]
      def block_body(nodes, depth, nuke_edges: false)
        children = join(nodes, depth + 1)
        return children if children.empty? || nuke_edges

        [text(newline(depth + 1)), *children, text(newline(depth))]
      end

      #: (String, escape: bool?) -> Array[Herb::AST::Node]
      def interpolate(literal, escape:)
        parts = ::Haml::StringSplitter.compile(literal)

        parts.flat_map do |type, value|
          next text_nodes(value) if type == :static

          if (match = value.match(ESCAPED_INTERPOLATION))
            erb(match[1])
          else
            erb(value, opening: escape ? "<%=" : "<%==")
          end
        end
      rescue StandardError
        [erb(literal, opening: escape ? "<%=" : "<%==")]
      end

      private

      #: (::Haml::Parser::ParseNode, Integer) -> (Herb::AST::Node | Array[Herb::AST::Node])
      def convert_node(node, depth)
        case node.type
        when :plain
          text_nodes(node.value[:text])
        when :script
          convert_script(node, depth)
        when :silent_script
          convert_silent_script(node, depth)
        when :tag
          convert_tag(node, depth)
        when :comment
          convert_comment(node, depth)
        when :doctype
          convert_doctype(node)
        when :haml_comment
          convert_haml_comment(node)
        when :filter
          @filters.convert(node, depth)
        else
          raise Herbst::Error, "Unexpected Haml node type: #{node.type}"
        end
      end

      #: (::Haml::Parser::ParseNode, Integer) -> (Herb::AST::Node | Array[Herb::AST::Node])
      def convert_script(node, depth)
        value = node.value
        opening = value[:escape_html] ? "<%=" : "<%=="

        if value[:escape_interpolation] || value[:text].include?("Haml::Util.escape_html_safe")
          return interpolate(value[:text], escape: value[:escape_interpolation])
        end

        return erb(value[:text], opening: opening) if node.children.empty?

        erb_block(value[:text], block_body(node.children, depth), opening: opening)
      end

      #: (::Haml::Parser::ParseNode, Integer) -> Herb::AST::Node
      def convert_silent_script(node, depth)
        code = node.value[:text]
        return erb(code, opening: "<%") if node.children.empty?

        main, clauses = segments(node)

        converted_clauses = clauses.map do |clause, children|
          [clause.value[:text], clause.value[:keyword], block_body(children, depth), clause.line] #: Herbst::Converter::clause
        end

        control(code, node.value[:keyword] || keyword(code), block_body(main, depth), converted_clauses, depth, line: node.line)
      end

      #: (::Haml::Parser::ParseNode) -> [Array[::Haml::Parser::ParseNode], Array[haml_clause]]
      def segments(node)
        main = node.children.take_while { |child| !mid_block?(child) }
        groups = node.children.drop(main.size).slice_before { |child| mid_block?(child) }
        clauses = groups.map { |group| [group.fetch(0), group.drop(1)] } #: Array[haml_clause]

        [main, clauses]
      end

      #: (::Haml::Parser::ParseNode) -> bool
      def mid_block?(node)
        node.type == :silent_script && MID_BLOCK_KEYWORDS.include?(node.value[:keyword])
      end

      #: (::Haml::Parser::ParseNode, Integer) -> (Herb::AST::HTMLElementNode | Array[Herb::AST::Node])
      def convert_tag(node, depth)
        value = node.value
        attributes = @attributes.compile(node)
        self_closing = value[:self_closing] && node.children.empty?

        body =
          if !node.children.empty?
            with_nuke_inner(value[:nuke_inner_whitespace]) do
              block_body(node.children, depth, nuke_edges: value[:nuke_inner_whitespace])
            end
          elsif value[:value].nil? || value[:value].empty?
            [] #: Array[Herb::AST::Node]
          elsif value[:parse]
            if value[:escape_interpolation] || value[:value].include?("Haml::Util.escape_html_safe")
              interpolate(value[:value], escape: value[:escape_interpolation])
            else
              [erb(value[:value], opening: value[:escape_html] ? "<%=" : "<%==")]
            end
          else
            text_nodes(value[:value])
          end

        return [element(value[:name], attributes: attributes), *body] if Herb::HTML::Util.void_element?(value[:name]) && !body.empty?

        element(value[:name], attributes: attributes, body: body, self_closing: self_closing)
      end

      #: (::Haml::Parser::ParseNode, Integer) -> (Herb::AST::Node | Array[Herb::AST::Node])
      def convert_comment(node, depth)
        value = node.value
        body =
          if !node.children.empty?
            block_body(node.children, depth)
          elsif value[:parse]
            [text(" "), *interpolate(value[:text], escape: true), text(" ")]
          else
            [literal(" #{value[:text]} ")]
          end

        if value[:conditional]
          return [text("<!--#{value[:conditional]}><!-->"), *body, text("<!--<![endif]-->")] if value[:revealed]

          return comment([literal("#{value[:conditional]}>"), *body, literal("<![endif]")])
        end

        comment(body)
      end

      #: (::Haml::Parser::ParseNode) -> (Herb::AST::HTMLDoctypeNode | Array[Herb::AST::Node])
      def convert_doctype(node)
        type = node.value[:type].to_s.downcase
        return [] if type == "xml"

        doctype(" html")
      end

      #: (::Haml::Parser::ParseNode) -> (Herb::AST::ERBCommentNode | Array[Herb::AST::Node])
      def convert_haml_comment(node)
        text = node.value[:text].to_s
        return [] if text.strip.empty?

        erb_comment(text.gsub("%>", "% >"))
      end

      #: (::Haml::Parser::ParseNode) -> bool
      def nuke_whitespace?(node)
        node.type == :tag && node.value[:nuke_outer_whitespace]
      end

      #: (::Haml::Parser::ParseNode, ::Haml::Parser::ParseNode) -> bool
      def whitespace_between?(previous, node)
        return false if nuke_whitespace?(previous) || nuke_whitespace?(node)
        return false if previous.type == :script && previous.children.empty? && @nuke_inner.last

        true
      end

      #: [T] (bool?) { () -> T } -> T
      def with_nuke_inner(value)
        @nuke_inner.push(value)

        yield
      ensure
        @nuke_inner.pop
      end
    end
  end
end
