# frozen_string_literal: true

require "haml"

module Herbst
  module Haml
    # Converts the tree produced by Haml::Parser into a Herb AST.
    #
    # The resulting tree prints to ERB that renders the same HTML as the Haml
    # template (modulo insignificant whitespace).
    #
    class Converter
      include Builder

      INDENT = "  " #: String
      MID_BLOCK_KEYWORDS = ::Haml::Parser::MID_BLOCK_KEYWORDS - ["end"] #: Array[String]
      ESCAPED_INTERPOLATION = /\AHaml::Util\.escape_html_safe\(\((.*)\)\.to_s\)\z/m #: Regexp

      attr_reader :warnings #: Array[String]

      # @rbs!
      #   type clause = [::Haml::Parser::ParseNode, Array[::Haml::Parser::ParseNode]]

      # @rbs @options: Hash[Symbol, untyped]
      # @rbs @attributes: Attributes
      # @rbs @filters: Filters
      # @rbs @nuke_inner: Array[bool?]
      # @rbs @markup: bool

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        @options = { escape_html: true }.merge(options)
        @warnings = []
        @attributes = Attributes.new(@warnings)
        @filters = Filters.new(self)
        @nuke_inner = [false]
        @markup = false
      end

      #: (String) -> Herb::AST::DocumentNode
      def convert(source)
        root = ::Haml::Parser.new(@options).call(source)
        children = join(root.children, 0)
        children << text("\n") unless children.empty?
        document = merge_texts!(document(children))

        # Text with HTML in it, like `Hello <code>x</code>`, prints as markup, so Herb builds the
        # elements it contains from the printed ERB.
        @markup ? Herb.parse(IdentityPrinter.print(document), track_whitespace: true).value : document
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

      # A literal `<%` or `%>` in text would open or close an ERB tag, so they are printed through ERB.
      #: (String) -> Array[Herb::AST::Node]
      def text_nodes(value)
        @markup = true if value.match?(%r{<[A-Za-z/!?]})

        value.split(/(<%|%>)/).reject(&:empty?).map do |part|
          case part
          when "<%" then erb('"<%"', opening: "<%==")
          when "%>" then erb('"%\>"', opening: "<%==")
          else text(part)
          end
        end
      end

      #: (::Haml::Parser::ParseNode, String) -> void
      def warn(node, message)
        @warnings << "line #{node.line}: #{message}"
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

        case node.value[:keyword]
        when "if"
          convert_if(code, main, clauses, depth)
        when "unless"
          convert_unless(code, main, clauses, depth)
        when "case"
          convert_case(code, main, clauses, depth)
        when "begin"
          convert_begin(code, main, clauses, depth)
        else
          if clauses.empty? && code.match?(/\A\s*while\b/)
            erb_while(code, block_body(main, depth))
          elsif clauses.empty? && code.match?(/\A\s*until\b/)
            erb_until(code, block_body(main, depth))
          elsif clauses.empty? && code.match?(/\A\s*for\b/)
            erb_for(code, block_body(main, depth))
          else
            convert_block(code, main, clauses, depth)
          end
        end
      end

      #: (::Haml::Parser::ParseNode) -> [Array[::Haml::Parser::ParseNode], Array[clause]]
      def segments(node)
        main = node.children.take_while { |child| !mid_block?(child) }
        groups = node.children.drop(main.size).slice_before { |child| mid_block?(child) }
        clauses = groups.map { |group| [group.fetch(0), group.drop(1)] } #: Array[clause]

        [main, clauses]
      end

      #: (::Haml::Parser::ParseNode) -> bool
      def mid_block?(node)
        node.type == :silent_script && MID_BLOCK_KEYWORDS.include?(node.value[:keyword])
      end

      #: (String, Array[::Haml::Parser::ParseNode], Array[clause], Integer) -> Herb::AST::ERBIfNode
      def convert_if(code, main, clauses, depth)
        subsequent = nil #: (Herb::AST::ERBIfNode | Herb::AST::ERBElseNode)?

        clauses.reverse_each do |clause, children|
          subsequent =
            case clause.value[:keyword]
            when "else"
              erb_else(block_body(children, depth))
            when "elsif"
              erb_if(clause.value[:text], block_body(children, depth), subsequent: subsequent, end_node: nil)
            else
              unsupported_clause(clause, "if")
            end
        end

        erb_if(code, block_body(main, depth), subsequent: subsequent)
      end

      #: (String, Array[::Haml::Parser::ParseNode], Array[clause], Integer) -> Herb::AST::ERBUnlessNode
      def convert_unless(code, main, clauses, depth)
        clauses.map(&:first).each { |clause| unsupported_clause(clause, "unless") unless clause.value[:keyword] == "else" }
        else_clause = clauses.find { |clause, _| clause.value[:keyword] == "else" }

        erb_unless(code, block_body(main, depth), else_clause: else_clause && erb_else(block_body(else_clause[1], depth)))
      end

      #: (String, Array[::Haml::Parser::ParseNode], Array[clause], Integer) -> Herb::AST::ERBCaseNode
      def convert_case(code, main, clauses, depth)
        main.each { |child| warn(child, "content between `case` and the first `when` was dropped") }

        conditions = clauses.select { |clause, _| clause.value[:keyword] == "when" }.map do |clause, children|
          erb_when(clause.value[:text], block_body(children, depth))
        end

        else_clause = clauses.find { |clause, _| clause.value[:keyword] == "else" }

        node = erb_case(code, conditions, else_clause: else_clause && erb_else(block_body(else_clause[1], depth)))
        node.children << text(newline(depth))

        node
      end

      #: (String, Array[::Haml::Parser::ParseNode], Array[clause], Integer) -> Herb::AST::ERBBeginNode
      def convert_begin(code, main, clauses, depth)
        rescues = clauses.select { |clause, _| clause.value[:keyword] == "rescue" }
        else_clause = clauses.find { |clause, _| clause.value[:keyword] == "else" }
        ensure_clause = clauses.find { |clause, _| clause.value[:keyword] == "ensure" }

        rescue_clause = nil #: Herb::AST::ERBRescueNode?

        rescues.reverse_each do |clause, children|
          rescue_clause = erb_rescue(clause.value[:text], block_body(children, depth), subsequent: rescue_clause)
        end

        erb_begin(
          code, block_body(main, depth),
          rescue_clause: rescue_clause,
          else_clause: else_clause && erb_else(block_body(else_clause[1], depth)),
          ensure_clause: ensure_clause && erb_ensure(block_body(ensure_clause[1], depth))
        )
      end

      #: (String, Array[::Haml::Parser::ParseNode], Array[clause], Integer) -> Herb::AST::ERBBlockNode
      def convert_block(code, main, clauses, depth)
        body = block_body(main, depth)

        clauses.each do |clause, children|
          body << erb(clause.value[:text], opening: "<%")
          body.concat(block_body(children, depth))
        end

        erb_block(code, body)
      end

      #: (::Haml::Parser::ParseNode, String) -> bot
      def unsupported_clause(clause, keyword)
        raise Herbst::UnsupportedError.new("`#{clause.value[:keyword]}` is not supported inside `#{keyword}`", clause.line)
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

        # A void element can't have children, so browsers (and Herb) read what Haml nests in one,
        # as in `%br` followed by an indented line, as the element's next siblings.
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

      #: (Integer) -> String
      def newline(depth)
        "\n#{INDENT * depth}"
      end
    end
  end
end
