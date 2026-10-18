# frozen_string_literal: true

require "herb"

# This printer is meant to move into Herb. Once the installed herb gem ships it, use Herb's
# printer and skip the copy below.
if defined?(Herb::Printer::IdentityPrinter)
  Herbst::IdentityPrinter = Herb::Printer::IdentityPrinter # steep:ignore
  return
end

module Herbst
  class IdentityPrinter < Herb::Visitor
    # @rbs!
    #   interface _ERBTag
    #     def tag_opening: () -> Herb::Token?
    #     def content: () -> Herb::Token?
    #     def tag_closing: () -> Herb::Token?
    #   end
    #
    #   interface _Delimited
    #     def tag_opening: () -> Herb::Token?
    #     def children: () -> Array[Herb::AST::Node]
    #     def tag_closing: () -> Herb::Token?
    #   end

    # @rbs @source: String?
    # @rbs @output: String
    # @rbs @line_offsets: Array[Integer]?

    #: (Herb::AST::Node, ?source: String?) -> String
    def self.print(node, source: nil)
      new(source: source).print(node)
    end

    #: (?source: String?) -> void
    def initialize(source: nil)
      super()

      @source = source
      @output = +""
    end

    #: (Herb::AST::Node) -> String
    def print(node)
      visit(node)

      @output
    end

    #: (Herb::AST::DocumentNode) -> void
    def visit_document_node(node)
      visit_all(node.children)
    end

    #: (Herb::AST::LiteralNode) -> void
    def visit_literal_node(node)
      write(node.content)
    end

    #: (Herb::AST::HTMLTextNode) -> void
    def visit_html_text_node(node)
      write(node.content)
    end

    #: (Herb::AST::WhitespaceNode) -> void
    def visit_whitespace_node(node)
      write(node.value&.value)
    end

    #: (Herb::AST::HTMLOpenTagNode) -> void
    def visit_html_open_tag_node(node)
      write(node.tag_opening&.value)
      write(node.tag_name&.value)

      previous_end = (node.tag_name || node.tag_opening)&.location&.end

      node.children.each do |child|
        if previous_end && !child.is_a?(Herb::AST::WhitespaceNode) && !ends_with_whitespace?
          write(separator_between(previous_end, child.location.start))
        end

        visit(child)

        previous_end = child.location.end
      end

      write(node.tag_closing&.value)
    end

    #: (Herb::AST::HTMLConditionalOpenTagNode) -> void
    def visit_html_conditional_open_tag_node(node)
      visit(node.conditional)
    end

    #: (Herb::AST::HTMLCloseTagNode) -> void
    def visit_html_close_tag_node(node)
      write(node.tag_opening&.value)

      children = node.children || []

      if node.tag_name
        start = node.tag_name.location.start
        finish = node.tag_name.location.end

        visit_all(children.select { |child| child.location.end <= start })
        write(node.tag_name.value)
        visit_all(children.select { |child| child.location.start >= finish })
      else
        visit_all(children)
      end

      write(node.tag_closing&.value)
    end

    #: (Herb::AST::HTMLOmittedCloseTagNode) -> void
    def visit_html_omitted_close_tag_node(_node); end

    #: (Herb::AST::HTMLVirtualCloseTagNode) -> void
    def visit_html_virtual_close_tag_node(_node); end

    #: (Herb::AST::HTMLElementNode) -> void
    def visit_html_element_node(node)
      visit(node.open_tag)
      visit_all(node.body)
      visit(node.close_tag)
    end

    #: (Herb::AST::HTMLConditionalElementNode) -> void
    def visit_html_conditional_element_node(node)
      visit(node.open_conditional)
      visit_all(node.body)
      visit(node.close_conditional)
    end

    #: (Herb::AST::HTMLAttributeNode) -> void
    def visit_html_attribute_node(node)
      visit(node.name)
      write(node.equals&.value)
      visit(node.value) if node.equals
    end

    #: (Herb::AST::HTMLAttributeNameNode) -> void
    def visit_html_attribute_name_node(node)
      visit_all(node.children || [])
    end

    #: (Herb::AST::HTMLAttributeValueNode) -> void
    def visit_html_attribute_value_node(node)
      write(node.open_quote&.value || '"') if node.quoted
      visit_all(node.children)
      write(node.close_quote&.value || '"') if node.quoted
    end

    #: (Herb::AST::RubyLiteralNode) -> void
    def visit_ruby_literal_node(node)
      write(node.content)
    end

    #: (Herb::AST::RubyHTMLAttributesSplatNode) -> void
    def visit_ruby_html_attributes_splat_node(node)
      write(node.content)
    end

    #: (Herb::AST::HTMLCommentNode) -> void
    def visit_html_comment_node(node)
      write(node.comment_start&.value)
      visit_all(node.children)
      write(node.comment_end&.value)
    end

    #: (Herb::AST::HTMLDoctypeNode) -> void
    def visit_html_doctype_node(node)
      print_delimited(node)
    end

    #: (Herb::AST::XMLDeclarationNode) -> void
    def visit_xml_declaration_node(node)
      print_delimited(node)
    end

    #: (Herb::AST::CDATANode) -> void
    def visit_cdata_node(node)
      print_delimited(node)
    end

    #: (Herb::AST::XMLProcessingInstructionNode) -> void
    def visit_xml_processing_instruction_node(node)
      write(node.tag_opening&.value)
      write(node.target&.value)
      visit_all(node.children)
      write(node.tag_closing&.value)
    end

    #: (Herb::AST::ERBOpenTagNode) -> void
    def visit_erb_open_tag_node(node)
      print_erb(node)
    end

    #: (Herb::AST::ERBContentNode) -> void
    def visit_erb_content_node(node)
      print_erb(node)
    end

    #: (Herb::AST::ERBCommentNode) -> void
    def visit_erb_comment_node(node)
      print_erb(node)
    end

    #: (Herb::AST::ERBIfNode) -> void
    def visit_erb_if_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.subsequent)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBElseNode) -> void
    def visit_erb_else_node(node)
      print_erb(node)
      visit_all(node.statements)
    end

    #: (Herb::AST::ERBEndNode) -> void
    def visit_erb_end_node(node)
      print_erb(node)
    end

    #: (Herb::AST::ERBBlockNode) -> void
    def visit_erb_block_node(node)
      print_erb(node)
      visit_all(node.body)
      visit(node.rescue_clause)
      visit(node.else_clause)
      visit(node.ensure_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBIterationBlockNode) -> void
    def visit_erb_iteration_block_node(node)
      print_erb(node)
      visit_all(node.body)
      visit(node.rescue_clause)
      visit(node.else_clause)
      visit(node.ensure_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBCaseNode) -> void
    def visit_erb_case_node(node)
      print_erb(node)
      visit_all(node.children)
      visit_all(node.conditions)
      visit(node.else_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBWhenNode) -> void
    def visit_erb_when_node(node)
      print_erb(node)
      visit_all(node.statements)
    end

    #: (Herb::AST::ERBWhileNode) -> void
    def visit_erb_while_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBUntilNode) -> void
    def visit_erb_until_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBForNode) -> void
    def visit_erb_for_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBBeginNode) -> void
    def visit_erb_begin_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.rescue_clause)
      visit(node.else_clause)
      visit(node.ensure_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBRescueNode) -> void
    def visit_erb_rescue_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.subsequent)
    end

    #: (Herb::AST::ERBEnsureNode) -> void
    def visit_erb_ensure_node(node)
      print_erb(node)
      visit_all(node.statements)
    end

    #: (Herb::AST::ERBUnlessNode) -> void
    def visit_erb_unless_node(node)
      print_erb(node)
      visit_all(node.statements)
      visit(node.else_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::ERBRenderNode) -> void
    def visit_erb_render_node(node)
      print_erb(node)
      return unless node.end_node

      visit_all(node.body)
      visit(node.rescue_clause)
      visit(node.else_clause)
      visit(node.ensure_clause)
      visit(node.end_node)
    end

    #: (Herb::AST::RubyRenderKeywordsNode) -> void
    def visit_ruby_render_keywords_node(_node)
      # extracted metadata, nothing to print
    end

    #: (Herb::AST::RubyRenderLocalNode) -> void
    def visit_ruby_render_local_node(_node)
      # extracted metadata, nothing to print
    end

    #: (Herb::AST::ERBStrictLocalsNode) -> void
    def visit_erb_strict_locals_node(node)
      print_erb(node)
    end

    #: (Herb::AST::HerbDirectiveNode) -> void
    def visit_herb_directive_node(node)
      print_erb(node)
    end

    #: (Herb::AST::HerbStateDirectiveNode) -> void
    def visit_herb_state_directive_node(node)
      print_erb(node)
    end

    #: (Herb::AST::HerbStateDeclarationNode) -> void
    def visit_herb_state_declaration_node(_node)
      # extracted metadata, nothing to print
    end

    #: (Herb::AST::RubyParameterNode) -> void
    def visit_ruby_parameter_node(_node)
      # extracted metadata, nothing to print
    end

    #: (Herb::AST::ERBYieldNode) -> void
    def visit_erb_yield_node(node)
      print_erb(node)
    end

    #: (Herb::AST::ERBInNode) -> void
    def visit_erb_in_node(node)
      print_erb(node)
      visit_all(node.statements)
    end

    #: (Herb::AST::ERBCaseMatchNode) -> void
    def visit_erb_case_match_node(node)
      print_erb(node)
      visit_all(node.children)
      visit_all(node.conditions)
      visit(node.else_clause)
      visit(node.end_node)
    end

    private

    #: (String?) -> void
    def write(value)
      @output << value if value
    end

    #: () -> bool
    def ends_with_whitespace?
      @output.match?(/\s\z/)
    end

    #: (_ERBTag) -> void
    def print_erb(node)
      write(node.tag_opening&.value)
      write(node.content&.value)
      write(node.tag_closing&.value)
    end

    #: (_Delimited) -> void
    def print_delimited(node)
      write(node.tag_opening&.value)
      visit_all(node.children)
      write(node.tag_closing&.value)
    end

    #: (Herb::Position, Herb::Position) -> String
    def separator_between(from, to)
      return "" unless (from <=> to)&.negative?

      source = @source
      return " " unless source

      separator = slice_between(source, from, to)

      separator.nil? || separator.empty? || !separator.strip.empty? ? " " : separator
    end

    #: (String, Herb::Position, Herb::Position) -> String?
    def slice_between(source, from, to)
      start = offset(source, from)
      finish = offset(source, to)
      return nil if start.nil? || finish.nil? || start > finish

      source.byteslice(start, finish - start)
    end

    #: (String, Herb::Position) -> Integer?
    def offset(source, position)
      line_offsets = @line_offsets ||= source.each_line.with_object([0]) { |line, offsets| offsets << (offsets.last + line.bytesize) }
      line_start = line_offsets[position.line - 1]

      line_start && (line_start + position.column)
    end
  end
end
