# frozen_string_literal: true

require "test_helper"

class Herbst::Haml::RoundTripTest < Minitest::Spec
  include ConversionHelper

  Dir[File.join(ConversionHelper::FIXTURES, "*.haml")].each do |path|
    it "round-trips #{File.basename(path)}" do
      document = Herbst::Haml.parse(File.read(path))

      assert_round_trip(document, Herbst::Printer.print(document, format: false))
    end
  end

  it "reports where the trees differ" do
    document = Herbst::Haml.parse("%p Hello")
    error = assert_raises(Minitest::Assertion) { assert_round_trip(document, "<p>Goodbye</p>\n") }

    assert_includes error.message, %(document.children[0].body[0].content\n  built:  "Hello"\n  parsed: "Goodbye")
  end
end
