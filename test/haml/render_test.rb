# frozen_string_literal: true

require "test_helper"
require "haml"
require "herb/engine"

class Herbst::Haml::RenderTest < Minitest::Spec
  include ConversionHelper

  class ValueScope
    attr_reader :value

    def initialize(value)
      @value = value
    end
  end

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

  [
    "%p{class: value}", ".a{class: value}", ".a.a{class: [value, \"a\"]}", "%p{class: [value, \"x\"]}", "%p(class=value)", "%p{id: value}", "#a{id: value}",
    "%p{id: [value, \"x\"]}", "%p{class: value, id: value}", ".a{class: \"b\"}{class: value}", "%p{class: nil}", "%p{id: nil}", "%p{title: nil}", "%p{title: false}", "%p{title: true}"
  ].each do |source|
    it "renders `#{source}` like Haml" do
      [nil, false, true, "", "x", "a<b", ["a", nil], [["b"], "c"]].each { |value| assert_renders_like_haml(source, value) }
    end
  end

  [
    "%p{data: value}", "%p{aria: value}", "%p{data: {a: value}}", "%p{data: {a_b: value}}", "%p{data: {a: {b: value}}}", "%p{aria: {a: value}}", "%p{data: nil}", "%p{data: true}",
    "%p{\"data-a\": value}", "%input{disabled: value}", "%input{checked: true, disabled: value}", "%input{checked: value, type: \"a\"}", "%p(disabled=value)", "%input{disabled: \"\#{value}\"}"
  ].each do |source|
    it "renders `#{source}` like Haml" do
      [nil, false, true, "", "x", "a<b", ["a", nil], { z: 1, a_b: "<" }, { a: { c: nil, d: true } }].each { |value| assert_renders_like_haml(source, value) }
    end
  end

  [
    "%p(title)", "%p{data: \"x\"}", "%p{data: {a: 1}}{data: {b: value}}", "%p{\"foo\": value, \"bar\": value}", "%p{title: \"a\#{value}\"}",
    "%a{href: value, class: \"b\"}", "%p{title: value, \"data-x\": 1}", "%p= value", "= value", "!= value", "%p \#{value}", "~ value", "&= value", "%p! \#{value}"
  ].each do |source|
    it "renders `#{source}` like Haml" do
      [nil, false, true, "", "x", "a<b", ["a", nil], { z: 1, a_b: "<" }].each { |value| assert_renders_like_haml(source, value) }
    end
  end

  private

  def assert_renders_like_haml(source, value)
    expected = Haml::Template.new { source }.render(ValueScope.new(value))
    actual = ValueScope.new(value).instance_eval(Herb::Engine.new(Herbst::Haml.to_erb(source), escape: true).src)

    assert_equal normalize(expected), normalize(actual.force_encoding(Encoding::UTF_8))
  end

  def normalize(html)
    html.gsub(/\s+/, " ").gsub(/>\s+/, ">").gsub(/\s+</, "<").strip
  end
end
