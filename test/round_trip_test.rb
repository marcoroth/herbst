# frozen_string_literal: true

require "test_helper"

class Herbst::RoundTripTest < Minitest::Spec
  it "returns nil when the ERB parses into the same tree" do
    document = Herbst::Haml.parse("%p Hello")

    assert_nil Herbst::RoundTrip.difference(document, "<p>Hello</p>\n")
  end

  it "describes the first difference" do
    document = Herbst::Haml.parse("%p Hello")

    assert_equal <<~MESSAGE.chomp, Herbst::RoundTrip.difference(document, "<p>Goodbye</p>\n")
      printed ERB parses into a different tree at document.children[0].body[0].content
        built:  "Hello"
        parsed: "Goodbye"
    MESSAGE
  end

  it "reports parse errors in the ERB" do
    document = Herbst::Haml.parse("%p Hello")

    assert_includes Herbst::RoundTrip.difference(document, "<p>Hello"), "printed ERB has parse errors:"
  end
end
