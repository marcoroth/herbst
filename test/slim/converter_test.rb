# frozen_string_literal: true

require "test_helper"

class Herbst::Slim::ConverterTest < Minitest::Spec
  include ConversionHelper

  it "warns about herb directives in Slim comments" do
    converter = Herbst::Slim::Converter.new
    converter.convert("/ herb:state (count: 0)\np\n  / herb:key item.id\n/ locals: (name:)")

    assert_equal [
      "line 1: `/ herb:state (count: 0)` is a Slim comment, which is dropped when parsing. Use `-# herb:state (count: 0)` to keep the directive",
      "line 3: `/ herb:key item.id` is a Slim comment, which is dropped when parsing. Use `-# herb:key item.id` to keep the directive",
      "line 4: `/ locals: (name:)` is a Slim comment, which is dropped when parsing. Use `-# locals: (name:)` to keep the directive"
    ], converter.warnings
  end

  it "does not warn about other comments or text" do
    converter = Herbst::Slim::Converter.new
    converter.convert("/ a note\n/! herb:state (count: 0)\n| / herb:state (count: 0)\njavascript:\n  / herb:state")

    assert_empty converter.warnings
  end

  it "keeps directives written as Ruby comments" do
    assert_equal "<%# herb:state (count: 0) %>", slim_to_erb("-# herb:state (count: 0)")
    assert_equal "<%# locals: (name:) %>", slim_to_erb("-# locals: (name:)")
  end

  it "converts tags with text" do
    assert_equal "<p>Hello</p>", slim_to_erb("p Hello")
  end

  it "converts shortcuts to a div with class and id" do
    assert_equal %(<div class="a b" id="main"></div>), slim_to_erb("#main.a.b")
  end

  it "only adds whitespace next to block-level elements" do
    assert_equal "<ul>\n  <li>One</li>\n  <li>Two</li>\n</ul>", slim_to_erb("ul\n  li One\n  li Two")
    assert_equal "<p><span>a</span><span>b</span></p>", slim_to_erb("p\n  span a\n  span b")
  end

  it "keeps the whitespace markers" do
    assert_equal "<p><span>a</span> <span>b</span></p>", slim_to_erb("p\n  span> a\n  span b")
    assert_equal "<p>a b</p>", slim_to_erb("p\n  ' a\n  | b")
  end

  it "converts escaped and unescaped output" do
    assert_equal "<%= a %><%== b %>", slim_to_erb("= a\n== b")
    assert_equal "<p><%= a %></p>", slim_to_erb("p = a")
  end

  it "converts interpolation" do
    assert_equal "<p>Hi <%= name %>, <%== raw %>!</p>", slim_to_erb("p Hi \#{name}, \#{{raw}}!")
  end

  it "converts if / elsif / else" do
    slim = "- if a\n  p A\n- elsif b\n  p B\n- else\n  p C"
    assert_equal "<% if a %>\n  <p>A</p>\n<% elsif b %>\n  <p>B</p>\n<% else %>\n  <p>C</p>\n<% end %>", slim_to_erb(slim)
  end

  it "converts case with indented when" do
    assert_equal "<% case x %><% when 1 %>one<% else %>other<% end %>", slim_to_erb("- case x\n  - when 1\n    | one\n  - else\n    | other")
  end

  it "closes block statements without a body, as Slim does" do
    assert_equal "<% if a then b else c %><% end %>", slim_to_erb("- if a then b else c")
  end

  it "moves trailing Ruby comments into ERB comments" do
    assert_equal "<%# note %><% x = 1 %><% if x %>\n  <p>a</p>\n<% end %>", slim_to_erb("- x = 1 # note\n- if x\n  p a")
    assert_equal "<p><%# note %><%= x %></p>", slim_to_erb("p = x # note")
    assert_equal %(<% x = "a # b" %>), slim_to_erb(%(- x = "a # b"))
  end

  it "converts text with HTML in it" do
    assert_equal "<li><アクセス></li>", slim_to_erb("li <アクセス>")
    assert_equal "<p>Hello <code>x</code></p>", slim_to_erb("p Hello <code>x</code>")
  end

  it "converts case / when" do
    slim = "- case x\n- when 1\n  | one\n- else\n  | other"
    assert_equal "<% case x %><% when 1 %>one<% else %>other<% end %>", slim_to_erb(slim)
  end

  it "converts blocks and adds the do Slim adds" do
    assert_equal "<% items.each do |item| %><%= item %><% end %>", slim_to_erb("- items.each do |item|\n  = item")
    assert_equal "<% items.each do %><%= 1 %><% end %>", slim_to_erb("- items.each\n  = 1")
    assert_equal "<%= link_to url do %>Go<% end %>", slim_to_erb("= link_to url do\n  | Go")
  end

  it "expands data and aria hashes like Slim" do
    assert_equal %(<p data-action="click" data-user_id="<%= user.id %>"></p>), slim_to_erb(%(p data={ action: "click", user_id: user.id }))
    assert_equal %(<p aria-label="x" data-a-b="1"></p>), slim_to_erb(%(p aria={ label: "x" } data={ a: { b: 1 } }))
  end

  it "converts attributes like Slim" do
    assert_equal %(<a<% if url == true %> href<% elsif url %> href="<%= url %>"<% end %> title="A &amp; B">x</a>), slim_to_erb(%(a href=url title="A & B" x))
    assert_equal %(<input checked type="checkbox">), slim_to_erb(%(input type="checkbox" checked=true disabled=false))
    assert_equal %(<input <%= "disabled" if off %>>), slim_to_erb("input disabled=off")
    assert_equal %(<p data-id="1"></p>), slim_to_erb("p data-id=1")
  end

  it "merges classes" do
    assert_equal %(<p class="a<% unless (_herbst_attribute = [b].flatten.map(&:to_s).reject(&:empty?).join(" ")).empty? %> <%= _herbst_attribute %><% end %>"></p>), slim_to_erb("p.a class=b")
    assert_equal %(<p class="a b c"></p>), slim_to_erb(%(p.a class=["b", "c"]))
    assert_equal %(<p<% unless (_herbst_attribute = [b, "c"].flatten.map(&:to_s).reject(&:empty?).join(" ")).empty? %> class="<%= _herbst_attribute %>"<% end %>></p>), slim_to_erb(%(p class=[b, "c"]))
    assert_equal %(<p></p>), slim_to_erb(%(p class=nil))
  end

  it "wraps dynamic attributes so falsy values omit them" do
    assert_equal %(<p<% if a == true %> title<% elsif a %> title="<%= a %>"<% end %>></p>), slim_to_erb("p title=a")
    assert_equal %(<p<% if @a == true %> title<% elsif @a %> title="<%== @a %>"<% end %>></p>), slim_to_erb("p title==@a")
  end

  it "evaluates attribute code that cannot be repeated once" do
    expected = %(<p<% if (_herbst_attribute = a.b(1)) == true %> title<% elsif _herbst_attribute %> title="<%= _herbst_attribute %>"<% end %>></p>)

    assert_equal expected, slim_to_erb("p title=a.b(1)")
  end

  it "keeps the spacing around wrapped attributes" do
    expected = %(<a class="b"<% if c == true %> href<% elsif c %> href="<%= c %>"<% end %><% if d == true %> title<% elsif d %> title="<%= d %>"<% end %>></a>)

    assert_equal expected, slim_to_erb("a.b href=c title=d")
  end

  it "does not wrap hash entries or quoted attributes" do
    assert_equal %(<p data-a="<%= b %>"></p>), slim_to_erb("p data={a: b}")
    assert_equal %(<p title="<%= b %>"></p>), slim_to_erb(%(p title="\#{b}"))
  end

  it "keeps raw output for raw class values" do
    raw = %(<% unless (_herbst_attribute = [@a].flatten.map(&:to_s).reject(&:empty?).join(" ")).empty? %> class="<%== _herbst_attribute %>"<% end %>)
    merged = %(<% unless (_herbst_attribute = [[@a].flatten.map(&:to_s).reject(&:empty?).join(" "), [@b].flatten.map(&:to_s).reject(&:empty?).join(" ")].reject(&:empty?).join(" ")).empty? %>)

    assert_equal %(<p#{raw}></p>), slim_to_erb("p class==@a")
    assert_includes slim_to_erb("p class==@a class==@b"), %(#{merged} class="<%== _herbst_attribute %>")
    assert_includes slim_to_erb("p class=@a class==@b"), %(#{merged} class="<%= _herbst_attribute %>")
  end

  it "falls back to tag.attributes for splats" do
    converter = Herbst::Slim::Converter.new
    document = converter.convert("p *attrs")

    assert_equal %(<p <%= tag.attributes(**attrs) %>></p>), Herbst::Printer.print(document, format: false)
    assert_equal 1, converter.warnings.size
  end

  it "converts comments and doctypes" do
    assert_equal "<!DOCTYPE html>\n<!--visible-->", slim_to_erb("doctype html\n/ hidden\n/! visible")
    assert_equal "<!--[if IE]>\n  <p>ie</p>\n<![endif]-->", slim_to_erb("/[if IE]\n  p ie")
  end

  it "converts embedded engines" do
    assert_equal "<script>alert(<%= x %>);</script>", slim_to_erb("javascript:\n  alert(\#{x});")
    assert_equal "<style>p { color: red; }</style>", slim_to_erb("css:\n  p { color: red; }")
    assert_equal "<% x = 1 %>", slim_to_erb("ruby:\n  x = 1")
  end

  it "lets Herb build inline HTML" do
    erb = slim_to_erb(%(<div class="raw">\n  p in\n</div>))

    assert_equal %(<div class="raw">\n<p>in</p>\n</div>), erb
  end

  it "raises for unsupported embedded engines" do
    assert_raises(Herbst::UnsupportedError) { slim_to_erb("markdown:\n  # Hi") }
  end

  it "raises Herbst::Error for Slim syntax errors" do
    assert_raises(Herbst::Error) { slim_to_erb("p(") }
  end
end
