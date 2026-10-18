# frozen_string_literal: true

require "test_helper"

class Herbst::IdentityPrinterTest < Minitest::Spec
  include Herbst::Builder

  SOURCES = [
    %(<!DOCTYPE html>\n<p class="a"   id=b\n  data-x>héllo <%= x %></p >),
    %(<div <%= a %> b="c"><% if x %>y<% elsif z %>w<% else %>v<% end %><br/></div>),
    %(<!-- c --><%# n %><%== raw %><%- trimmed -%>),
    %(<ul><% xs.each do |(a, b)| %><li><%= a %></li><% end %></ul>),
    %(<% case x %>\n<% when 1 %>1<% else %>2<% end %><% case y %><% in [z] %>z<% end %>),
    %(<% begin %>a<% rescue A => e %>b<% rescue %>c<% else %>d<% ensure %>e<% end %>),
    %(<% unless a %>b<% else %>c<% end %><% while a %>b<% end %><% until a %>b<% end %><% for a in b %>c<% end %>),
    %(<%= yield :head %><script>if (a < b) { alert("<%= x %>") }</script><style>p { color: red; }</style>),
    %(<?xml version="1.0"?><![CDATA[ x ]]><input type='text' disabled>)
  ].freeze

  SOURCES.each_with_index do |source, index|
    it "prints a whitespace-tracking parse back to its source (#{index})" do
      assert_equal source, Herbst::IdentityPrinter.print(Herb.parse(source, track_whitespace: true).value)
    end
  end

  it "recovers open tag whitespace from the source" do
    source = %(<p\tclass="a"\n  id="b">x</p>)

    assert_equal source, Herbst::IdentityPrinter.print(Herb.parse(source).value, source: source)
    assert_equal %(<p class="a" id="b">x</p>), Herbst::IdentityPrinter.print(Herb.parse(source).value)
  end

  it "prints trees built without locations" do
    link = element("a", attributes: [attribute("href", [erb("url")])], body: [text("Go")])
    tree = document([link])

    assert_equal %(<a href="<%= url %>">Go</a>), Herbst::IdentityPrinter.print(tree)
  end

  it "prints without Node.js unless formatting" do
    Open3.stub(:capture3, ->(*) { raise "Node.js should not run" }) do
      assert_equal "<p><%= x %></p>\n", Herbst::Haml.to_erb("%p= x")
    end
  end
end
