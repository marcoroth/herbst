# frozen_string_literal: true

module Herbst
  module Slim
    class Parser < ::Slim::Parser
      DIRECTIVE = %r{\A/\s*((?:herb:|locals:).*)\z} #: Regexp

      attr_reader :dropped_directives #: Array[[Integer, String]]

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        super

        @dropped_directives = []
      end

      protected

      #: () -> void
      def parse_comment_block
        directive = @line[DIRECTIVE, 1]
        @dropped_directives << [@lineno, directive.strip] if directive

        super
      end
    end
  end
end
