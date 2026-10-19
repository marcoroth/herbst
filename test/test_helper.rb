# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "herbst"
require "minitest/autorun"

module ConversionHelper
  FIXTURES = File.expand_path("fixtures/haml", __dir__)
  SLIM_FIXTURES = File.expand_path("fixtures/slim", __dir__)

  def to_erb(haml)
    document = Herbst::Haml.parse(haml)
    erb = Herbst::Printer.print(document, format: false)
    assert_round_trip(document, erb)
    erb
  end

  def slim_to_erb(slim)
    document = Herbst::Slim.parse(slim)
    erb = Herbst::Printer.print(document, format: false)
    assert_round_trip(document, erb)
    erb
  end

  def assert_round_trip(document, erb)
    difference = Herbst::RoundTrip.difference(document, erb)

    assert_nil difference, "#{difference}\n#{erb}"
  end
end
