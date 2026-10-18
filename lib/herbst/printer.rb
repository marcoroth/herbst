# frozen_string_literal: true

require "open3"
require "tmpdir"

module Herbst
  module Printer
    FORMATTER = ["npx", "--yes", "@herb-tools/formatter@#{Herb::VERSION}"].freeze #: Array[String]

    class Error < Herbst::Error; end

    #: (Herb::AST::DocumentNode, ?format: bool) -> String
    def self.print(document, format: true)
      erb = IdentityPrinter.print(document)

      format ? format(erb) : erb
    end

    #: (Array[Herb::AST::DocumentNode], ?format: bool) -> Array[String]
    def self.print_all(documents, format: true)
      sources = documents.map { |document| IdentityPrinter.print(document) }

      format ? format_all(sources) : sources
    end

    #: (String) -> String
    def self.format(source)
      run("-", stdin_data: source)
    end

    #: (Array[String]) -> Array[String]
    def self.format_all(sources)
      Dir.mktmpdir("herbst") do |directory|
        paths = sources.each_with_index.map do |source, index|
          File.join(directory, "#{index}.html.erb").tap { |path| File.write(path, source) }
        end

        run(directory, chdir: directory) unless paths.empty?

        paths.map { |path| File.read(path, encoding: Encoding::UTF_8) }
      end
    end

    #: (*String, **untyped) -> String
    def self.run(*, **)
      stdout, stderr, status = Open3.capture3(*FORMATTER, *, **)
      raise Error, "Herb formatter failed:\n#{stderr}" unless status.success?

      stdout.force_encoding(Encoding::UTF_8)
    rescue Errno::ENOENT
      raise Error, "Node.js is required to format ERB (could not run `npx`)"
    end
  end
end
