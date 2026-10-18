# frozen_string_literal: true

require "optparse"

module Herbst
  # The `herbst` command.
  #
  #   herbst convert app/views/posts/show.html.haml   # prints the ERB
  #   herbst convert app/views                        # writes show.html.erb next to show.html.haml
  #
  # A single file is printed to stdout unless `--write` is given. Directories and multiple
  # files are written next to their sources, replacing the `.haml` extension with `.erb`.
  # Existing ERB files are skipped unless `--force` is given. A file without a format gets
  # `html`, so `show.haml` becomes `show.html.erb`, while `welcome.text.haml` keeps its format.
  #
  class CLI
    class Conversion
      attr_reader :path #: String
      attr_reader :warnings #: Array[String]
      attr_reader :error #: String?
      attr_reader :difference #: String?
      attr_accessor :erb #: String?

      #: (String, ?erb: String?, ?warnings: Array[String], ?error: String?, ?difference: String?) -> void
      def initialize(path, erb: nil, warnings: [], error: nil, difference: nil)
        @path = path
        @erb = erb
        @warnings = warnings
        @error = error
        @difference = difference
      end

      #: () -> bool
      def failed?
        !error.nil? || !difference.nil?
      end
    end

    # @rbs @arguments: Array[String]
    # @rbs @stdout: IO
    # @rbs @stderr: IO
    # @rbs @format: bool
    # @rbs @verify: bool
    # @rbs @write: bool
    # @rbs @force: bool
    # @rbs @default_format: String?
    # @rbs @help: bool
    # @rbs @version: bool
    # @rbs @option_parser: OptionParser?

    #: (Array[String], ?stdout: IO, ?stderr: IO) -> void
    def initialize(arguments, stdout: $stdout, stderr: $stderr)
      @arguments = arguments
      @stdout = stdout
      @stderr = stderr
      @format = true
      @verify = true
      @write = false
      @force = false
      @default_format = "html"
      @help = false
      @version = false
    end

    #: () -> Integer
    def run
      command, *paths = option_parser.parse(@arguments)

      return help if @help
      return version if @version

      case command
      when "convert"
        paths.empty? ? help(1, "Missing path: pass the Haml files or directories to convert.") : convert(paths)
      when "help"
        help
      when "version"
        version
      when String
        help(1, "Unknown command: '#{command}'")
      else
        help(1)
      end
    rescue OptionParser::ParseError => e
      help(1, e.message)
    end

    private

    #: (Array[String]) -> Integer
    def convert(paths)
      missing = paths.reject { |path| File.exist?(path) }
      return fail_with("#{missing.join(", ")}: No such file or directory") unless missing.empty?

      files = paths.flat_map { |path| File.directory?(path) ? Dir[File.join(path, "**", "*.haml")] : [path] }.sort
      return fail_with("No .haml files found in #{paths.join(", ")}") if files.empty?

      conversions = files.map { |file| convert_file(file) }
      format(conversions) if @format

      write = @write || paths.size > 1 || paths.any? { |path| File.directory?(path) }
      write ? write_files(conversions) : print_file(conversions.fetch(0))
    end

    #: () -> OptionParser
    def option_parser
      @option_parser ||= OptionParser.new do |parser|
        parser.banner = ""

        parser.on_tail("-v", "--version", "Show the version") { @version = true }
        parser.on_tail("-h", "--help", "Show this message") { @help = true }

        parser.on("--force", "Overwrite existing ERB files (for convert command)") { @force = true }
        parser.on("--no-format", "Don't run the Herb formatter on the output (for convert command)") { @format = false }

        parser.on("--no-verify", "Don't check the ERB parses back into the converted tree (for convert command)") do
          @verify = false
        end

        parser.on("--write", "Write a single file next to its source instead of printing it (for convert command)") do
          @write = true
        end

        parser.on("--default-format FORMAT", "Format for files without one (default: html) (for convert command)") do |format|
          @default_format = format
        end

        parser.on("--no-default-format", "Don't add a format to files without one, as in show.erb (for convert command)") do
          @default_format = nil
        end
      end
    end

    #: (?Integer, ?String?) -> Integer
    def help(exit_code = 0, message = nil)
      io = exit_code.zero? ? @stdout : @stderr

      io.puts message, "" if message
      io.puts <<~HELP
        Herbst 🍂 Unified syntax tree for HTML templating languages.

        Usage:
          bundle exec herbst [command] [options]

        Commands:
          bundle exec herbst convert [paths]    Convert Haml files, or every Haml file in a directory, to ERB.
          bundle exec herbst help               Show this message.
          bundle exec herbst version            Prints the versions of Herbst, Herb and Haml.

        Converting:
          A single file is printed to stdout, unless `--write` is passed:
            bundle exec herbst convert app/views/posts/show.html.haml

          Directories, and several files at once, are written next to their sources:
            bundle exec herbst convert app/views

          Existing ERB files are skipped unless `--force` is passed. The Haml files are kept.

          A file without a format gets html, so show.haml becomes show.html.erb. Pass
          `--default-format FORMAT` for another format, or `--no-default-format` to write show.erb.

        Options:
      HELP
      io.puts option_parser.to_s.delete_prefix("\n").gsub(/^    /, "  "), ""

      exit_code
    end

    #: () -> Integer
    def version
      @stdout.puts "herbst gem v#{VERSION}, herb gem v#{Herb::VERSION}, haml gem v#{::Haml::VERSION}"

      0
    end

    #: (String) -> Conversion
    def convert_file(file)
      converter = Haml::Converter.new
      document = converter.convert(File.read(file, encoding: "UTF-8"))
      erb = IdentityPrinter.print(document)
      difference = RoundTrip.difference(document, erb) if @verify

      Conversion.new(file, erb: erb, warnings: converter.warnings, difference: difference)
    rescue Herbst::Error, ::Haml::Error => e
      Conversion.new(file, error: e.message)
    end

    #: (Array[Conversion]) -> void
    def format(conversions)
      converted = conversions.select(&:erb)
      formatted = Printer.format_all(converted.map { |conversion| conversion.erb.to_s })

      converted.zip(formatted) { |conversion, erb| conversion.erb = erb }
    end

    #: (Conversion) -> Integer
    def print_file(conversion)
      report(conversion)
      @stdout.print(conversion.erb) if conversion.erb

      conversion.failed? ? 1 : 0
    end

    #: (Array[Conversion]) -> Integer
    def write_files(conversions)
      written = 0
      skipped = 0

      conversions.each do |conversion|
        report(conversion)

        erb = conversion.erb
        next unless erb

        target = target_path(conversion.path)

        if File.exist?(target) && !@force
          @stderr.puts "#{conversion.path}: #{target} already exists, skipped (use --force to overwrite)"
          skipped += 1
        else
          File.write(target, erb)
          written += 1
        end
      end

      failed = conversions.count(&:failed?)
      @stderr.puts summary(conversions.size, written, skipped, failed)

      failed.positive? ? 1 : 0
    end

    #: (String) -> String
    def target_path(path)
      base = path.delete_suffix(".haml")
      base = "#{base}.#{@default_format}" if @default_format && !File.basename(base).include?(".")

      "#{base}.erb"
    end

    #: (Conversion) -> void
    def report(conversion)
      conversion.warnings.each { |warning| @stderr.puts "#{conversion.path}: #{warning}" }
      @stderr.puts "#{conversion.path}: #{conversion.error}" if conversion.error
      @stderr.puts "#{conversion.path}: #{conversion.difference}" if conversion.difference
    end

    #: (Integer, Integer, Integer, Integer) -> String
    def summary(total, written, skipped, failed)
      parts = ["Converted #{written} of #{total} #{total == 1 ? "file" : "files"}"]

      parts << "#{skipped} skipped" if skipped.positive?
      parts << "#{failed} failed" if failed.positive?

      "#{parts.join(", ")}."
    end

    #: (String) -> Integer
    def fail_with(message)
      @stderr.puts message

      1
    end
  end
end
