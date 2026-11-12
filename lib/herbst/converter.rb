# frozen_string_literal: true

module Herbst
  class Converter
    include Builder

    INDENT = "  " #: String
    DECLARATION = /^\s*-#\s*(?:herb:state|locals:)\s*(\(.*\))\s*$/ #: Regexp

    # @rbs!
    #   type clause = [String, String?, Array[Herb::AST::Node], Integer?]

    attr_reader :warnings #: Array[String]

    # @rbs @markup: bool

    #: () -> void
    def initialize
      @warnings = []
      @markup = false
    end

    #: (String) -> Herb::AST::DocumentNode
    def convert(source)
      raise NotImplementedError, "#{self.class} must implement `convert`"
    end

    #: (String) -> Array[Herb::AST::Node]
    def text_nodes(value)
      @markup = true if value.match?(%r{<[\p{L}/!?]})

      value.split(/(<%|%>)/).reject(&:empty?).map do |part|
        case part
        when "<%"
          erb('"<%"', opening: "<%==")
        when "%>"
          erb('"%\>"', opening: "<%==")
        else
          text(part)
        end
      end
    end

    #: (Integer?, String) -> void
    def warn(line, message)
      @warnings << (line ? "line #{line}: #{message}" : message)
    end

    private

    #: (String) -> Array[Symbol]
    def declared_names(source)
      source.scan(DECLARATION).flatten.flat_map do |parameters|
        definition = Prism.parse("def declaration#{parameters}; end").value.statements.body.first

        next [] unless definition.is_a?(Prism::DefNode)

        definition.parameters&.keywords&.map(&:name) || []
      end
    end

    #: (Herb::AST::DocumentNode) -> Herb::AST::DocumentNode
    def finish(document)
      document = merge_texts!(document)
      return document unless @markup

      Herb.parse(IdentityPrinter.print(document), track_whitespace: true).value
    end

    #: (Integer) -> String
    def newline(depth)
      "\n#{INDENT * depth}"
    end

    #: (String) -> String?
    def keyword(code)
      code[/\A\s*(if|unless|case|begin|while|until|for|elsif|else|when|in|rescue|ensure)\b/, 1]
    end

    #: (String, String?, Array[Herb::AST::Node], Array[clause], Integer, ?line: Integer?) -> Herb::AST::Node
    def control(code, keyword, body, clauses, depth, line: nil)
      case keyword
      when "if"
        control_if(code, body, clauses)
      when "unless"
        control_unless(code, body, clauses)
      when "case"
        control_case(code, body, clauses, depth, line)
      when "begin"
        control_begin(code, body, clauses)
      when "while"
        clauses.empty? ? erb_while(code, body) : control_block(code, body, clauses)
      when "until"
        clauses.empty? ? erb_until(code, body) : control_block(code, body, clauses)
      when "for"
        clauses.empty? ? erb_for(code, body) : control_block(code, body, clauses)
      else
        control_block(code, body, clauses)
      end
    end

    #: (String, Array[Herb::AST::Node], Array[clause]) -> Herb::AST::ERBIfNode
    def control_if(code, body, clauses)
      subsequent = nil #: (Herb::AST::ERBIfNode | Herb::AST::ERBElseNode)?

      clauses.reverse_each do |clause_code, clause_keyword, clause_body, clause_line|
        subsequent =
          case clause_keyword
          when "else"
            erb_else(clause_body)
          when "elsif"
            erb_if(clause_code, clause_body, subsequent: subsequent, end_node: nil)
          else
            unsupported_clause(clause_keyword, "if", clause_line)
          end
      end

      erb_if(code, body, subsequent: subsequent)
    end

    #: (String, Array[Herb::AST::Node], Array[clause]) -> Herb::AST::ERBUnlessNode
    def control_unless(code, body, clauses)
      clauses.each do |_code, clause_keyword, _body, clause_line|
        unsupported_clause(clause_keyword, "unless", clause_line) unless clause_keyword == "else"
      end

      else_clause = clauses.find { |clause| clause[1] == "else" }

      erb_unless(code, body, else_clause: else_clause && erb_else(else_clause[2]))
    end

    #: (String, Array[Herb::AST::Node], Array[clause], Integer, Integer?) -> Herb::AST::ERBCaseNode
    def control_case(code, body, clauses, depth, line)
      unless body.all? { |node| node.is_a?(Herb::AST::HTMLTextNode) && node.content.to_s.strip.empty? }
        warn(line, "content between `case` and the first `when` was dropped")
      end

      conditions = clauses.filter_map do |clause_code, clause_keyword, clause_body, clause_line|
        case clause_keyword
        when "when"
          erb_when(clause_code, clause_body)
        when "else"
          nil
        else
          unsupported_clause(clause_keyword, "case", clause_line)
        end
      end

      else_clause = clauses.find { |clause| clause[1] == "else" }
      node = erb_case(code, conditions, else_clause: else_clause && erb_else(else_clause[2]))
      first = conditions.first&.statements&.first

      node.children << text(newline(depth)) if first.is_a?(Herb::AST::HTMLTextNode) && first.content.to_s.start_with?("\n")

      node
    end

    #: (String, Array[Herb::AST::Node], Array[clause]) -> Herb::AST::ERBBeginNode
    def control_begin(code, body, clauses)
      else_clause = clauses.find { |clause| clause[1] == "else" }
      ensure_clause = clauses.find { |clause| clause[1] == "ensure" }

      rescue_clause = nil #: Herb::AST::ERBRescueNode?

      clauses.select { |clause| clause[1] == "rescue" }.reverse_each do |clause_code, _keyword, clause_body, _line|
        rescue_clause = erb_rescue(clause_code, clause_body, subsequent: rescue_clause)
      end

      erb_begin(
        code, body,
        rescue_clause: rescue_clause,
        else_clause: else_clause && erb_else(else_clause[2]),
        ensure_clause: ensure_clause && erb_ensure(ensure_clause[2])
      )
    end

    #: (String, Array[Herb::AST::Node], Array[clause]) -> Herb::AST::ERBBlockNode
    def control_block(code, body, clauses)
      body = body.dup

      clauses.each do |clause_code, _keyword, clause_body, _line|
        body << erb(clause_code, opening: "<%")
        body.concat(clause_body)
      end

      erb_block(code, body)
    end

    #: (String?, String, Integer?) -> bot
    def unsupported_clause(clause_keyword, keyword, line)
      raise Herbst::UnsupportedError.new("`#{clause_keyword}` is not supported inside `#{keyword}`", line)
    end
  end
end
