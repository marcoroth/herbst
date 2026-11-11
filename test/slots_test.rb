# frozen_string_literal: true

require "test_helper"
require "slim"
require "haml"
require "herb/engine"
require "herb/engine/slots/visitor"
require "herb/engine/slots/schema_compiler"

class Herbst::SlotsTest < Minitest::Spec
  it "keeps a client read for Slim attributes that read declared state" do
    slots = slim_slots("-# herb:state (count: 0)\np title=count x")

    assert_includes slots[:markup], %(data-herb-slot="0:element 1:attribute:title")
    assert_equal({ "count" => [1] }, slots[:reads])
    assert_equal({ "count" => [{ "index" => 0, "node_path" => [2] }] }, slots[:server])
  end

  it "keeps a client read for Slim boolean attributes that read declared state" do
    slots = slim_slots("-# herb:state (open: false)\nbutton disabled=open x")

    assert_includes slots[:markup], %(data-herb-slot="0:element 1:attribute:disabled")
    assert_equal({ "open" => [1] }, slots[:reads])
  end

  it "reads computed Slim attributes on the server" do
    slots = slim_slots("-# herb:state (count: 0)\np title=count.to_s x")

    assert_includes slots[:markup], %(data-herb-slot="0:element 1:attribute:title")
    assert_empty slots[:reads]
    assert_equal ["count"], slots[:server].keys
  end

  it "reads Slim classes on the server" do
    assert_includes slim_slots("-# herb:state (count: 0)\np class=count x")[:markup], %(data-herb-slot="0:element 1:attribute:class")
    assert_includes slim_slots("-# herb:state (count: 0)\n.a class=count x")[:markup], %(data-herb-slot="0:attribute_interpolation:class")
    assert_empty slim_slots("-# herb:state (count: 0)\np class=count x")[:reads]
  end

  it "keeps a client read for split Haml attribute strings" do
    slots = haml_slots("-# herb:state (count: 0)\n%button{onclick: \"remove(\#{count})\"} x")

    assert_includes slots[:markup], %(data-herb-slot="0:attribute_interpolation:onclick")
    assert_equal({ "count" => [0] }, slots[:reads])
    assert_empty slots[:server]
  end

  it "keeps a client read for Haml attributes and declared boolean attributes" do
    assert_equal({ "count" => [0] }, haml_slots("-# herb:state (count: 0)\n%p{title: count} x")[:reads])

    slots = haml_slots("-# herb:state (open: false)\n%button{disabled: open} x")

    assert_includes slots[:markup], %(data-herb-slot="0:element 1:attribute:disabled")
    assert_equal({ "open" => [1] }, slots[:reads])
  end

  it "reads Haml classes on the server" do
    assert_empty haml_slots("-# herb:state (count: 0)\n%p{class: count} x")[:reads]
  end

  private

  def slim_slots(source)
    slots(Herbst::Slim.to_erb(source))
  end

  def haml_slots(source)
    slots(Herbst::Haml.to_erb(source))
  end

  def slots(erb)
    result = Herb::Engine::Slots::SchemaCompiler.call(
      erb,
      filename: "app/views/x/show.html.erb", mode: :client, visitors: -> { [] }, engine: Herb::Engine, options: { escape: true }
    )
    states = result.manifest.fetch("states")

    { markup: result.static_markup, reads: states.fetch("reads"), server: states.fetch("server").fetch("reads") }
  end
end
