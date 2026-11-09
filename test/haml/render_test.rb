# frozen_string_literal: true

require "test_helper"
require "haml"
require "herb/engine"

class Herbst::Haml::RenderTest < Minitest::Spec
  include ConversionHelper

  class Scope
    def title = "Herbst <3"
    def name = "<World>"
    def extra = "y"
    def role = :a
    def url = "/path?a=1&b=2"
    def raw_html = "<em>raw</em>"
    def admin? = false
    def user? = true
    def items = ["one", "<two>"]
    def risky = raise("boom & bust")
    def identifier = "<1> & 'two'"
  end

  it "renders page.haml like Haml" do
    source = File.read(File.join(FIXTURES, "page.haml"))

    expected = Haml::Template.new { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Haml.to_erb(source), escape: true).src)

    assert_equal normalize(expected), normalize(actual)
  end

  it "renders split attribute interpolation like Haml" do
    source = %(%button{onclick: "remove(\#{identifier}, 'a&b')", data: {url: "/items/\#{identifier}"}} Remove)

    expected = Haml::Template.new { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Haml.to_erb(source), escape: true).src)

    assert_equal normalize(expected), normalize(actual)
  end

  it "renders scoped filters like their unscoped filters with a scoped attribute" do
    { "css" => "style", "javascript" => "script" }.each do |filter, tag|
      expected = Haml::Template.new { ":#{filter}\n  a { color: \#{extra}; }" }.render(Scope.new).sub("<#{tag}>", "<#{tag} scoped>")
      actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Haml.to_erb(":scoped_#{filter}\n  a { color: \#{extra}; }"), escape: true).src)

      assert_equal normalize(expected), normalize(actual)
    end
  end

  private

  def normalize(html)
    html.gsub(/\s+/, " ").gsub(/>\s+/, ">").gsub(/\s+</, "<").strip
  end
end
