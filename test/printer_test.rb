# frozen_string_literal: true

require "test_helper"

class Herbst::PrinterTest < Minitest::Spec
  it "formats with the Herb formatter" do
    assert_equal "<div>\n  <p class=\"a\">x</p>\n</div>\n", Herbst::Printer.format(%(<div><p class="a">x</p></div>\n))
  end

  it "formats many sources in one run" do
    sources = [%(<div><p>a</p></div>\n), %(<ul><li>b</li></ul>\n), %(<div><p>unclosed\n)]

    assert_equal ["<div>\n  <p>a</p>\n</div>\n", "<ul>\n  <li>b</li>\n</ul>\n", sources.last], Herbst::Printer.format_all(sources)
  end
end
