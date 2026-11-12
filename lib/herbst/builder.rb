# frozen_string_literal: true

require "herb"
require "herb/html/util"
require "prism"

module Herbst
  module Builder
    #: (String, String) -> Herb::Token
    def token(type, value)
      Herb::Token.from(type, value)
    end

    #: (Array[Herb::AST::Node]) -> Herb::AST::DocumentNode
    def document(children)
      Herb::AST::DocumentNode.build(children: children)
    end

    #: (String) -> Herb::AST::HTMLTextNode
    def text(content)
      Herb::AST::HTMLTextNode.build(content: +content)
    end

    #: (String) -> Herb::AST::LiteralNode
    def literal(content)
      Herb::AST::LiteralNode.build(content: +content)
    end

    #: (?String) -> Herb::AST::WhitespaceNode
    def whitespace(value = " ")
      Herb::AST::WhitespaceNode.build(value: token("TOKEN_WHITESPACE", value))
    end

    #: (String, ?opening: String) -> (Herb::AST::ERBContentNode | Herb::AST::ERBYieldNode)
    def erb(code, opening: "<%=")
      return Herb::AST::ERBYieldNode.build(**erb_tag(opening, code)) if yield?(code)

      Herb::AST::ERBContentNode.build(**erb_tag(opening, code), parsed: true, valid: Prism.parse(code).errors.empty?)
    end

    #: (String) -> bool
    def yield?(code)
      code.include?("yield") && !Prism.parse(code).value.breadth_first_search { |node| node.is_a?(Prism::YieldNode) }.nil?
    end

    #: (String) -> Herb::AST::ERBCommentNode
    def erb_comment(content)
      Herb::AST::ERBCommentNode.build(**erb_tag("<%#", content))
    end

    #: () -> Herb::AST::ERBEndNode
    def erb_end
      Herb::AST::ERBEndNode.build(**erb_tag("<%", "end"))
    end

    #: (String, Array[Herb::AST::Node], ?subsequent: (Herb::AST::ERBIfNode | Herb::AST::ERBElseNode)?, ?end_node: Herb::AST::ERBEndNode?) -> Herb::AST::ERBIfNode
    def erb_if(code, statements, subsequent: nil, end_node: erb_end)
      Herb::AST::ERBIfNode.build(**erb_tag("<%", code), statements: statements, subsequent: subsequent, end_node: end_node)
    end

    #: (String, Array[Herb::AST::Node], ?else_clause: Herb::AST::ERBElseNode?) -> Herb::AST::ERBUnlessNode
    def erb_unless(code, statements, else_clause: nil)
      Herb::AST::ERBUnlessNode.build(**erb_tag("<%", code), statements: statements, else_clause: else_clause, end_node: erb_end)
    end

    #: (Array[Herb::AST::Node]) -> Herb::AST::ERBElseNode
    def erb_else(statements)
      Herb::AST::ERBElseNode.build(**erb_tag("<%", "else"), statements: statements)
    end

    #: (String, Array[Herb::AST::ERBWhenNode], ?else_clause: Herb::AST::ERBElseNode?) -> Herb::AST::ERBCaseNode
    def erb_case(code, conditions, else_clause: nil)
      Herb::AST::ERBCaseNode.build(**erb_tag("<%", code), conditions: conditions, else_clause: else_clause, end_node: erb_end)
    end

    #: (String, Array[Herb::AST::Node]) -> Herb::AST::ERBWhenNode
    def erb_when(code, statements)
      Herb::AST::ERBWhenNode.build(**erb_tag("<%", code), statements: statements)
    end

    #: (String, Array[Herb::AST::Node], ?rescue_clause: Herb::AST::ERBRescueNode?, ?else_clause: Herb::AST::ERBElseNode?, ?ensure_clause: Herb::AST::ERBEnsureNode?) -> Herb::AST::ERBBeginNode
    def erb_begin(code, statements, rescue_clause: nil, else_clause: nil, ensure_clause: nil)
      Herb::AST::ERBBeginNode.build(
        **erb_tag("<%", code),
        statements: statements,
        rescue_clause: rescue_clause,
        else_clause: else_clause,
        ensure_clause: ensure_clause,
        end_node: erb_end
      )
    end

    #: (String, Array[Herb::AST::Node], ?subsequent: Herb::AST::ERBRescueNode?) -> Herb::AST::ERBRescueNode
    def erb_rescue(code, statements, subsequent: nil)
      Herb::AST::ERBRescueNode.build(**erb_tag("<%", code), statements: statements, subsequent: subsequent)
    end

    #: (Array[Herb::AST::Node]) -> Herb::AST::ERBEnsureNode
    def erb_ensure(statements)
      Herb::AST::ERBEnsureNode.build(**erb_tag("<%", "ensure"), statements: statements)
    end

    #: (String, Array[Herb::AST::Node]) -> Herb::AST::ERBWhileNode
    def erb_while(code, statements)
      Herb::AST::ERBWhileNode.build(**erb_tag("<%", code), statements: statements, end_node: erb_end)
    end

    #: (String, Array[Herb::AST::Node]) -> Herb::AST::ERBUntilNode
    def erb_until(code, statements)
      Herb::AST::ERBUntilNode.build(**erb_tag("<%", code), statements: statements, end_node: erb_end)
    end

    #: (String, Array[Herb::AST::Node]) -> Herb::AST::ERBForNode
    def erb_for(code, statements)
      Herb::AST::ERBForNode.build(**erb_tag("<%", code), statements: statements, end_node: erb_end)
    end

    #: (String, Array[Herb::AST::Node], ?opening: String) -> Herb::AST::ERBBlockNode
    def erb_block(code, body, opening: "<%")
      Herb::AST::ERBBlockNode.build(**erb_tag(opening, code), body: body, block_arguments: block_arguments(code), end_node: erb_end)
    end

    #: (String) -> Array[Herb::AST::RubyParameterNode]
    def block_arguments(code)
      # Like Herb, only a block passed to the first statement's method call has parameters, so
      # `items.each do |item|` has them and `list = items.map do |item|` doesn't.
      call = Prism.parse("#{code}\nend").value.statements.body.first
      return [] unless call.is_a?(Prism::CallNode)

      block = call.block
      return [] unless block.is_a?(Prism::BlockNode)

      block_parameters = block.parameters
      return [] unless block_parameters.is_a?(Prism::BlockParametersNode)

      parameters = block_parameters.parameters
      return [] unless parameters

      all = [*parameters.requireds, *parameters.optionals, parameters.rest, *parameters.posts, *parameters.keywords, parameters.keyword_rest, parameters.block].compact
      all = all.flat_map { |parameter| destructured(parameter) }

      all.filter_map { |parameter| ruby_parameter(parameter) }
    end

    #: (Prism::node) -> Herb::AST::RubyParameterNode?
    def ruby_parameter(parameter)
      case parameter
      when Prism::RequiredParameterNode
        ruby_parameter_node(parameter.name, "positional", true)
      when Prism::OptionalParameterNode
        ruby_parameter_node(parameter.name, "positional", false, parameter.value)
      when Prism::RestParameterNode
        ruby_parameter_node(parameter.name, "rest", false)
      when Prism::RequiredKeywordParameterNode
        ruby_parameter_node(parameter.name, "keyword", true)
      when Prism::OptionalKeywordParameterNode
        ruby_parameter_node(parameter.name, "keyword", false, parameter.value)
      when Prism::KeywordRestParameterNode
        ruby_parameter_node(parameter.name, "keyword_rest", false)
      when Prism::BlockParameterNode
        ruby_parameter_node(parameter.name, "block", false)
      end
    end

    #: (Symbol?, String, bool, ?Prism::node?) -> Herb::AST::RubyParameterNode?
    def ruby_parameter_node(name, kind, required, value = nil)
      return unless name

      default = Herb::AST::RubyLiteralNode.build(content: +value.slice) if value

      Herb::AST::RubyParameterNode.build(
        name: token("TOKEN_IDENTIFIER", name.to_s), default_value: default, kind: +kind, required: required
      )
    end

    #: (String, ?attributes: Array[Herb::AST::Node], ?body: Array[Herb::AST::Node], ?self_closing: bool) -> Herb::AST::HTMLElementNode
    def element(name, attributes: [], body: [], self_closing: false)
      void = Herb::HTML::Util.void_element?(name)

      self_closing &&= !void

      children = open_tag_children(attributes)
      children << whitespace if self_closing

      open_tag = Herb::AST::HTMLOpenTagNode.build(
        tag_opening: token("TOKEN_HTML_TAG_START", "<"),
        tag_name: token("TOKEN_IDENTIFIER", name),
        tag_closing: self_closing ? token("TOKEN_HTML_TAG_SELF_CLOSE", "/>") : token("TOKEN_HTML_TAG_END", ">"),
        children: children,
        is_void: self_closing
      )

      if Herb::HTML::Util.raw_text_element?(name)
        body = merge_literals(body.map do |node|
          node.is_a?(Herb::AST::HTMLTextNode) ? literal(node.content.to_s) : node
        end)
      end

      # Herb reads the content of elements like `<script>` and `<textarea>` as text and ERB, so Herb
      # builds one that contains anything else, like the templates in `<script type="text/ng-template">`.
      if Herb::HTML::Util.raw_text_element?(name) || Herb::HTML::Util.rcdata_element?(name)
        text_only = body.all? do |node|
          node.is_a?(Herb::AST::LiteralNode) || node.is_a?(Herb::AST::HTMLTextNode) || node.is_a?(Herb::AST::ERBContentNode)
        end

        unless text_only
          source = IdentityPrinter.print(element(name, attributes: attributes, body: []).tap { |node| node.body.replace(body) })

          return Herb.parse(source, track_whitespace: true).value.children.fetch(0) #: Herb::AST::HTMLElementNode
        end
      end

      close_tag = unless void || self_closing
                    Herb::AST::HTMLCloseTagNode.build(
                      tag_opening: token("TOKEN_HTML_TAG_START_CLOSE", "</"),
                      tag_name: token("TOKEN_IDENTIFIER", name),
                      tag_closing: token("TOKEN_HTML_TAG_END", ">")
                    )
                  end

      Herb::AST::HTMLElementNode.build(
        open_tag: open_tag,
        tag_name: token("TOKEN_IDENTIFIER", name),
        body: body,
        close_tag: close_tag,
        is_void: void || self_closing,
        element_source: "HTML"
      )
    end

    #: (String | Herb::AST::ERBContentNode, ?Array[Herb::AST::Node]?) -> Herb::AST::HTMLAttributeNode
    def attribute(name, value = nil)
      name_node = Herb::AST::HTMLAttributeNameNode.build(children: [name.is_a?(String) ? literal(name) : name])
      return Herb::AST::HTMLAttributeNode.build(name: name_node) if value.nil?

      Herb::AST::HTMLAttributeNode.build(
        name: name_node,
        equals: token("TOKEN_EQUALS", "="),
        value: Herb::AST::HTMLAttributeValueNode.build(
          open_quote: token("TOKEN_QUOTE", '"'),
          children: merge_literals(value),
          close_quote: token("TOKEN_QUOTE", '"'),
          quoted: true
        )
      )
    end

    #: (Array[Herb::AST::Node]) -> Herb::AST::HTMLCommentNode
    def comment(children)
      children = children.map { |node| node.is_a?(Herb::AST::HTMLTextNode) ? literal(node.content.to_s) : node }

      # Herb doesn't parse elements inside a comment, so Herb builds a comment that contains any.
      unless children.all? { |node| node.is_a?(Herb::AST::LiteralNode) || node.is_a?(Herb::AST::ERBContentNode) }
        source = "<!--#{children.map { |node| IdentityPrinter.print(node) }.join}-->"

        return Herb.parse(source, track_whitespace: true).value.children.fetch(0) #: Herb::AST::HTMLCommentNode
      end

      Herb::AST::HTMLCommentNode.build(
        comment_start: token("TOKEN_HTML_COMMENT_START", "<!--"),
        children: merge_literals(children),
        comment_end: token("TOKEN_HTML_COMMENT_END", "-->")
      )
    end

    #: (String) -> Herb::AST::HTMLDoctypeNode
    def doctype(content)
      Herb::AST::HTMLDoctypeNode.build(
        tag_opening: token("TOKEN_HTML_DOCTYPE", "<!DOCTYPE"),
        children: [literal(content)],
        tag_closing: token("TOKEN_HTML_TAG_END", ">")
      )
    end

    #: (String) -> Herb::AST::XMLDeclarationNode
    def xml_declaration(content)
      Herb::AST::XMLDeclarationNode.build(
        tag_opening: token("TOKEN_XML_DECLARATION", "<?xml"),
        children: [literal(content)],
        tag_closing: token("TOKEN_XML_DECLARATION_END", "?>")
      )
    end

    #: (Prism::node) -> Array[Prism::node]
    def destructured(parameter)
      return [parameter] unless parameter.is_a?(Prism::MultiTargetNode)

      [*parameter.lefts, *parameter.rights].flat_map { |target| destructured(target) }
    end

    #: (Array[Herb::AST::Node]) -> Array[Herb::AST::Node]
    def open_tag_children(attributes)
      attributes.each_with_index.flat_map do |node, index|
        next [node] if node.is_a?(Herb::AST::ERBIfNode) || node.is_a?(Herb::AST::ERBUnlessNode)

        # Herb reads ERB in an open tag as an attribute name when an attribute with a value follows it.
        valued = attributes.drop(index + 1).any? { |following| following.is_a?(Herb::AST::HTMLAttributeNode) && following.equals }

        if node.is_a?(Herb::AST::ERBContentNode) && valued
          [whitespace, attribute(node)]
        else
          [whitespace, node]
        end
      end
    end

    #: [T < Herb::AST::Node] (T) -> T
    def merge_texts!(node)
      node.instance_variables.each do |name|
        value = node.instance_variable_get(name)

        if value.is_a?(Array)
          value.each { |child| merge_texts!(child) if child.is_a?(Herb::AST::Node) }
          value.replace(merge_adjacent_texts(value))
        elsif value.is_a?(Herb::AST::Node)
          merge_texts!(value)
        end
      end

      node
    end

    #: (Array[Herb::AST::Node]) -> Array[Herb::AST::Node]
    def merge_adjacent_texts(nodes)
      nodes.each_with_object([]) do |node, merged|
        last = merged.last

        if node.is_a?(Herb::AST::HTMLTextNode) && last.is_a?(Herb::AST::HTMLTextNode)
          merged[-1] = text(last.content.to_s + node.content.to_s)
        else
          merged << node
        end
      end
    end

    #: (Array[Herb::AST::Node]) -> Array[Herb::AST::Node]
    def merge_literals(nodes)
      nodes.each_with_object([]) do |node, merged|
        next if node.is_a?(Herb::AST::LiteralNode) && node.content.to_s.empty?

        last = merged.last

        if node.is_a?(Herb::AST::LiteralNode) && last.is_a?(Herb::AST::LiteralNode)
          merged[-1] = literal(last.content.to_s + node.content.to_s)
        else
          merged << node
        end
      end
    end

    #: (String, String) -> { tag_opening: Herb::Token, content: Herb::Token, tag_closing: Herb::Token }
    def erb_tag(opening, code)
      {
        tag_opening: token("TOKEN_ERB_START", opening),
        content: token("TOKEN_ERB_CONTENT", " #{code.strip} "),
        tag_closing: token("TOKEN_ERB_END", "%>"),
      }
    end
  end
end
