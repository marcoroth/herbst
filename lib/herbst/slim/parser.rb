# frozen_string_literal: true

module Herbst
  module Slim
    class Parser < ::Slim::Parser
      DIRECTIVE = %r{\A/\s*((?:herb:|locals:).*)\z} #: Regexp

      # Rails reads strict locals from the template source, so a Slim comment like `/# locals: (...)`
      # declares them. Like Rails, the locals can continue on the following lines.
      STRICT_LOCALS = %r{\A/[ \t]*#[ \t]+(locals:[ \t]+\(.*?\))[ \t]*$}m #: Regexp

      attr_reader :dropped_directives #: Array[[Integer, String]]
      attr_reader :strict_locals #: String?

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        super

        @dropped_directives = []
        @strict_locals = nil
      end

      protected

      #: () -> void
      def parse_comment_block
        directive = @line[DIRECTIVE, 1]
        @dropped_directives << [@lineno, directive.strip] if directive
        first = @line
        remaining = @lines.dup

        super
        return if @strict_locals

        # The comment is `first` plus the lines `super` consumed from `@lines`.
        @strict_locals = [first, *remaining.first(remaining.size - @lines.size)].join("\n")[STRICT_LOCALS, 1]
      end
    end
  end
end
