# frozen_string_literal: true

require "test_helper"

class Herbst::Haml::ConverterTest < Minitest::Spec
  include ConversionHelper

  it "converts tags with static text" do
    assert_equal "<p>Hello</p>\n", to_erb("%p Hello")
  end

  it "converts implicit divs with class and id" do
    assert_equal %(<div class="a b" id="main"></div>\n), to_erb("#main.a.b")
  end

  it "converts nested tags" do
    assert_equal "<ul>\n  <li>One</li>\n  <li>Two</li>\n</ul>\n", to_erb("%ul\n  %li One\n  %li Two")
  end

  it "converts void and self-closing tags" do
    assert_equal "<br>\n<foo />\n", to_erb("%br\n%foo/")
  end

  it "converts escaped and unescaped scripts" do
    assert_equal "<%= a %>\n<%== b %>\n<%= c %>\n", to_erb("= a\n!= b\n&= c")
  end

  it "converts tag scripts" do
    assert_equal "<p><%= a %></p>\n<p><%== b %></p>\n", to_erb("%p= a\n%p!= b")
  end

  it "converts interpolation in plain text and tags" do
    assert_equal "Hi <%= name %>!\n<p>Hi <%= name %>!</p>\n", to_erb("Hi \#{name}!\n%p Hi \#{name}!")
  end

  it "escapes ERB delimiters in text" do
    assert_equal %(<p>a <%== "<%" %> b</p>\n), to_erb("%p a <% b")
  end

  it "converts silent scripts" do
    assert_equal "<% x = 1 %>\n", to_erb("- x = 1")
  end

  it "converts if / elsif / else" do
    haml = "- if a\n  A\n- elsif b\n  B\n- else\n  C"
    assert_equal "<% if a %>\n  A\n<% elsif b %>\n  B\n<% else %>\n  C\n<% end %>\n", to_erb(haml)
  end

  it "converts unless / else" do
    assert_equal "<% unless a %>\n  A\n<% else %>\n  B\n<% end %>\n", to_erb("- unless a\n  A\n- else\n  B")
  end

  it "converts case / when / else" do
    haml = "- case x\n- when 1\n  one\n- else\n  other"
    assert_equal "<% case x %>\n<% when 1 %>\n  one\n<% else %>\n  other\n<% end %>\n", to_erb(haml)
  end

  it "converts begin / rescue / ensure" do
    haml = "- begin\n  a\n- rescue => e\n  b\n- ensure\n  c"
    assert_equal "<% begin %>\n  a\n<% rescue => e %>\n  b\n<% ensure %>\n  c\n<% end %>\n", to_erb(haml)
  end

  it "converts blocks" do
    assert_equal "<% xs.each do |x| %>\n  <%= x %>\n<% end %>\n", to_erb("- xs.each do |x|\n  = x")
    assert_equal "<%= link_to url do %>\n  Go\n<% end %>\n", to_erb("= link_to url do\n  Go")
  end

  it "converts while loops" do
    assert_equal "<% while x %>\n  a\n<% end %>\n", to_erb("- while x\n  a")
  end

  it "uses Herb's void and raw text elements" do
    assert_equal "<keygen>\n", to_erb("%keygen")
    assert_equal "<iframe>a <%= b %></iframe>\n", to_erb("%iframe a \#{b}")
  end

  it "converts static and dynamic attributes" do
    assert_equal %(<a href="<%= url %>" title="A &amp; B">x</a>\n), to_erb(%(%a{href: url, title: "A & B"} x))
    assert_equal %(<a href="/x" title="<%= t %>"></a>\n), to_erb(%(%a(href="/x" title=t)))
  end

  it "merges static and dynamic classes" do
    assert_equal %(<p class="<%= ["a", (b)].flat_map { |value| value.is_a?(String) ? value.split(" ") : value.is_a?(Array) ? value.flatten.select { |item| item } : value ? [value] : [] }.map(&:to_s).uniq.join(" ") %>"></p>\n), to_erb("%p.a{class: b}")
    assert_equal %(<p class="a b c"></p>\n), to_erb(%(%p.a{class: ["b", "c"]}))
    assert_includes to_erb(%(%p{class: [b, "c"]})), %((_herbst_attribute = ([b, "c"])).is_a?(String))
  end

  it "converts boolean attributes" do
    assert_equal %(<input checked <%= "disabled" if d %>>\n),
                 to_erb("%input{checked: true, disabled: d, required: false}")
  end

  it "expands data attributes" do
    assert_equal %(<p data-a-b="1" data-c="<%= c %>"></p>\n), to_erb("%p{data: {a_b: 1, c: c}}")
  end

  it "splits interpolated attribute strings into text and ERB" do
    assert_equal %(<button onclick="remove(<%= m.id %>)"></button>\n), to_erb(%(%button{onclick: "remove(\#{m.id})"}))
    assert_equal %(<a href="/a/<%= b %>/c/<%= d %>"></a>\n), to_erb(%(%a{href: "/a/\#{b}/c/\#{d}"}))
    assert_equal %(<a title="<%= b("c") %>!"></a>\n), to_erb(%(%a{title: "\#{b("c")}!"}))
    assert_equal %(<a title="<%= b %>"></a>\n), to_erb(%(%a{title: "\#{b}"}))
  end

  it "escapes the text of split attribute strings" do
    assert_equal %(<a title="a&amp;b &quot;<%= c %>&quot;"></a>\n), to_erb(%(%a{title: "a&b \\"\#{c}\\""}))
  end

  it "splits interpolated strings in data attributes" do
    assert_equal %(<a data-url="/a/<%= b %>"></a>\n), to_erb(%(%a{data: {url: "/a/\#{b}"}}))
  end

  it "keeps other attribute code as a single expression" do
    assert_equal %(<a title="<%= foo("\#{b}") %>"></a>\n), to_erb(%(%a{title: foo("\#{b}")}))
    assert_equal %(<a title="<%= "a\#{b}" + c %>"></a>\n), to_erb(%(%a{title: "a\#{b}" + c}))
    assert_equal %(<a title="<%= %Q(a\#{b}) %>"></a>\n), to_erb(%(%a{title: %Q(a\#{b})}))
    assert_equal %(<a title="<%= "a\#@b" %>"></a>\n), to_erb(%(%a{title: "a\#@b"}))
    assert_equal %(<a title="<%= "\#{a; b}" %>"></a>\n), to_erb(%(%a{title: "\#{a; b}"}))
    assert_equal %(<input <%= "disabled" if "\#{a}" %>>\n), to_erb(%(%input{disabled: "\#{a}"}))
  end

  it "falls back to tag.attributes for splats" do
    converter = Herbst::Haml::Converter.new
    document = converter.convert("%p{**opts}")

    assert_equal %(<p <%= tag.attributes(**opts) %>></p>\n), Herbst::Printer.print(document, format: false)
    assert_equal 1, converter.warnings.size
  end

  it "converts html and haml comments" do
    assert_equal "<!-- hi -->\n<%# secret %>\n", to_erb("/ hi\n-# secret")
  end

  it "converts conditional comments" do
    assert_equal "<!--[if IE]> ie <![endif]-->\n", to_erb("/[if IE] ie")
  end

  it "converts doctypes" do
    assert_equal "<!DOCTYPE html>\n", to_erb("!!! 5")
  end

  it "converts whitespace removal" do
    assert_equal "<p>a</p><img><p>b</p>\n", to_erb("%p a\n%img>\n%p b")
    assert_equal "<p><span>a</span></p>\n", to_erb("%p<\n  %span a")
  end

  it "does not add whitespace after scripts inside a tag with <" do
    assert_equal "<span><%= a %>&nbsp;\n  b</span>\n", to_erb("%span<\n  = a\n  &nbsp;\n  b")
  end

  it "drops falsy values from class arrays" do
    assert_equal %(<p class="<%= ["a", ([x && "b"])].flat_map { |value| value.is_a?(String) ? value.split(" ") : value.is_a?(Array) ? value.flatten.select { |item| item } : value ? [value] : [] }.map(&:to_s).uniq.join(" ") %>"></p>\n), to_erb(%(%p.a{class: [x && "b"]}))
  end

  it "converts yield" do
    document = Herbst::Haml.parse("= yield\n= yield :head")

    assert_equal [Herb::AST::ERBYieldNode] * 2, document.children.grep_v(Herb::AST::HTMLTextNode).map(&:class)
  end

  it "converts destructured block parameters" do
    block = Herbst::Haml.parse("- pairs.each do |(key, value)|\n  = key").children.first

    assert_equal(["key", "value"], block.block_arguments.map { |argument| argument.name.value })
  end

  it "converts for loops" do
    assert_equal "<% for item in items %>\n  <p><%= item %></p>\n<% end %>\n", to_erb("- for item in items\n  %p= item")
  end

  it "converts text with HTML in it" do
    assert_equal "<p>Hello <code>x</code></p>\n", to_erb("%p Hello <code>x</code>")
  end

  it "converts scoped filters" do
    assert_equal "<style scoped>\n  a { color: red; }\n</style>\n", to_erb(":scoped_css\n  a { color: red; }")
    assert_equal "<script scoped>\n  alert(1);\n</script>\n", to_erb(":scoped_javascript\n  alert(1);")
  end

  it "keeps interpolation and indentation in scoped filters" do
    assert_equal "<div>\n  <style scoped>\n    a { color: <%== b %>; }\n  </style>\n</div>\n", to_erb("%div\n  :scoped_css\n    a { color: \#{b}; }")
  end

  it "moves content nested in a void element after it" do
    assert_equal "<br>\n  text\n\n", to_erb("%br\n  text")
  end

  it "escapes a literal %> in text and comments" do
    assert_equal %(<p>a <%== "%\\>" %> b</p>\n), to_erb("%p a %> b")
    assert_equal "<%# a % > b %>\n", to_erb("-# a %> b")
  end

  it "converts elements inside script, textarea and conditional comments" do
    assert_equal %(<script type="text/ng-template">\n  <p>x</p>\n</script>\n), to_erb(%(%script{type: "text/ng-template"}\n  %p x))
    assert_equal "<textarea><span>x</span></textarea>\n", to_erb("%textarea\n  %span x")
    assert_equal %(<!--[if IE]>\n  <meta content="x">\n<![endif]-->\n), to_erb(%(/[if IE]\n  %meta{content: "x"}))
  end

  it "keeps a data value that isn't a hash literal as one attribute" do
    assert_equal %(<p data-a="<%= {b: 1}.to_json %>"></p>\n), to_erb("%p{data: {a: {b: 1}.to_json}}")
  end

  it "only gives a block parameters when its call is the first statement" do
    assert_equal "<% list = items.map do |item| %>\n  <%= item %>\n<% end %>\n", to_erb("- list = items.map do |item|\n  = item")
  end

  it "reads ERB in an open tag as an attribute name when a valued attribute follows" do
    assert_equal %(<input <%= "checked" if c %> data-autosubmit name="x">\n), to_erb(%(%input{checked: c, data: {autosubmit: true}, name: "x"}))
  end

  it "converts filters" do
    assert_equal "<script>\n  alert(<%== x %>);\n</script>\n", to_erb(":javascript\n  alert(\#{x});")
    assert_equal "<style>\n  p { color: red; }\n</style>\n", to_erb(":css\n  p { color: red; }")
    assert_equal "<% x = 1 %>\n", to_erb(":ruby\n  x = 1")
    assert_equal "<p><%= y %></p>\n", to_erb(":erb\n  <p><%= y %></p>")
  end

  it "raises for unsupported filters" do
    error = assert_raises(Herbst::UnsupportedError) { to_erb(":markdown\n  # Hi") }
    assert_equal 1, error.line
  end
end
