# frozen_string_literal: true

require "test_helper"
require "slim"

class Herbst::Slim::RenderTest < Minitest::Spec
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
  end

  class ValueScope
    attr_reader :values, :value

    def initialize(value)
      @value = value
      @values = value
    end

    def shift_value = values.shift
  end

  it "renders page.slim like Slim" do
    source = File.read(File.join(SLIM_FIXTURES, "page.slim"))

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal without_block_whitespace(expected), without_block_whitespace(actual.force_encoding(Encoding::UTF_8))
  end

  [nil, false, true, "", "a<b"].each do |value|
    it "renders dynamic attributes like Slim for #{value.inspect}" do
      assert_renders_like_slim("p.a title=value id=value href=@value data-b=value", value)
    end
  end

  it "renders raw dynamic attributes escaped, since Herb escapes all attribute output" do
    source = "p title==value"

    assert_equal %(<p title="a<b"></p>), Slim::Template.new(format: :html) { source }.render(ValueScope.new("a<b"))
    assert_equal %(<p title="a&lt;b"></p>), ValueScope.new("a<b").instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)
  end

  [
    "p class=value", ".a class=value", ".a.b class=value class=value", "p class=value class=\"z\"", "p class=value class=value",
    "p class=\"\#{value}\"", ".a class=\"\#{value}\"", "p class=\"b \#{value}\"", "p class=\"\#{value}\" class=value", "p class=[value, \"c\"]",
    "p class=value id=\"a\"", "p class=nil", ".a class=\"\""
  ].each do |source|
    it "renders `#{source}` like Slim" do
      [nil, false, true, "", "x", "a<b", [], ["a", nil, ""], [["b"], "c"]].each do |value|
        assert_renders_like_slim(source, value)
      end
    end
  end

  ["p class=(\"a&b\")", "p class==(\"a&b\")", "p.c class==(\"a&b\")", "p.c class=(\"a&b\")"].each do |source|
    it "renders the static class `#{source}` like Slim" do
      assert_renders_like_slim(source, nil)
    end
  end

  it "evaluates attribute code once like Slim" do
    ["p title=values.shift", "p title=shift_value"].each do |source|
      expected = Slim::Template.new(format: :html) { source }.render(ValueScope.new([nil, "b"]))
      actual = ValueScope.new([nil, "b"]).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

      assert_equal expected, actual
    end
  end

  private

  def assert_renders_like_slim(source, value)
    expected = Slim::Template.new(format: :html) { source }.render(ValueScope.new(value))
    actual = ValueScope.new(value).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal expected, actual.force_encoding(Encoding::UTF_8)
  end

  def without_block_whitespace(html)
    parts = html.split(/(<[^>]*>)/)

    parts.each_with_index.map do |part, index|
      next part if part.start_with?("<")

      part = part.sub(/\A\s+/, "") if index.positive? && block_tag?(parts[index - 1])
      block_tag?(parts[index + 1]) ? part.sub(/\s+\z/, "") : part
    end.join
  end

  def block_tag?(tag)
    return false unless tag

    name = tag[%r{\A</?([a-zA-Z][\w-]*)}, 1]
    tag.start_with?("<!DOCTYPE") || (name && !Herb::HTML::Elements::INLINE_ELEMENTS.include?(name.downcase))
  end
end
