# frozen_string_literal: true

require_relative "herbst/version"

module Herbst
  autoload :Haml, "#{__dir__}/herbst/haml"
  autoload :Slim, "#{__dir__}/herbst/slim"

  class Error < StandardError; end

  class UnsupportedError < Error
    attr_reader :line #: Integer?

    #: (String, ?Integer?) -> void
    def initialize(message, line = nil)
      @line = line

      super(line ? "line #{line}: #{message}" : message)
    end
  end
end

require_relative "herbst/builder"
require_relative "herbst/identity_printer"
require_relative "herbst/printer"
require_relative "herbst/round_trip"
require_relative "herbst/converter"
require_relative "herbst/cli"
