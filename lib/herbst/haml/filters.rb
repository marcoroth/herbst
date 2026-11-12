# frozen_string_literal: true

require "cgi/escape"
require "herb"

module Herbst
  module Haml
    class Filters
      include Builder

      # @rbs @converter: Converter

      #: (Converter) -> void
      def initialize(converter)
        @converter = converter
      end

      #: (::Haml::Parser::ParseNode, Integer) -> (Herb::AST::Node | Array[Herb::AST::Node])
      def convert(node, depth)
        name = node.value[:name]
        source = node.value[:text].to_s.rstrip

        case name
        when "javascript"
          element("script", body: wrapped(source, depth))
        when "css"
          element("style", body: wrapped(source, depth))
        when "scoped_javascript"
          element("script", attributes: [attribute("scoped")], body: wrapped(source, depth))
        when "scoped_css"
          element("style", attributes: [attribute("scoped")], body: wrapped(source, depth))
        when "plain", "preserve"
          text_nodes(source)
        when "escaped"
          @converter.text_nodes(CGI.escapeHTML(source))
        when "ruby"
          erb(source, opening: "<%")
        when "erb"
          Herb.parse(source).value.children
        when "cdata"
          [text("<![CDATA["), *wrapped(source, depth), text("]]>")]
        else
          raise Herbst::UnsupportedError.new("the `:#{name}` filter is not supported", node.line)
        end
      end

      private

      #: (String, Integer) -> Array[Herb::AST::Node]
      def wrapped(source, depth)
        indent = Converter::INDENT * (depth + 1)
        body = source.gsub(/^(?=.)/, indent)

        [text("\n"), *text_nodes(body), text("\n#{Converter::INDENT * depth}")]
      end

      #: (String) -> Array[Herb::AST::Node]
      def text_nodes(source)
        return @converter.text_nodes(source) unless ::Haml::Util.contains_interpolation?(source)

        @converter.interpolate(::Haml::Util.unescape_interpolation(source), escape: false)
      end
    end
  end
end
