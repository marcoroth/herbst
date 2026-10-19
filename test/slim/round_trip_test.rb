# frozen_string_literal: true

require "test_helper"

class Herbst::Slim::RoundTripTest < Minitest::Spec
  include ConversionHelper

  Dir[File.join(ConversionHelper::SLIM_FIXTURES, "*.slim")].each do |path|
    it "round-trips #{File.basename(path)}" do
      document = Herbst::Slim.parse(File.read(path))

      assert_round_trip(document, Herbst::Printer.print(document, format: false))
    end
  end
end
