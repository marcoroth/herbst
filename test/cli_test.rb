# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

class Herbst::CLITest < Minitest::Spec
  EXE = File.expand_path("../exe/herbst", __dir__)

  before do
    @directory = Dir.mktmpdir
  end

  after do
    FileUtils.rm_rf(@directory)
  end

  def write(path, content)
    full_path = File.join(@directory, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  def read(path)
    File.read(File.join(@directory, path))
  end

  def herbst(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Herbst::CLI.new(["convert", *arguments, "--no-format"], stdout: stdout, stderr: stderr).run

    [stdout.string, stderr.string, status]
  end

  it "prints a single file" do
    stdout, stderr, status = herbst(write("page.html.haml", "%p Hello\n"))

    assert_equal 0, status
    assert_equal "<p>Hello</p>\n", stdout
    assert_empty stderr
    refute File.exist?(File.join(@directory, "page.html.erb"))
  end

  it "writes a single file with --write" do
    stdout, stderr, status = herbst(write("page.html.haml", "%p Hello\n"), "--write")

    assert_equal 0, status
    assert_empty stdout
    assert_equal "Converted 1 of 1 file.\n", stderr
    assert_equal "<p>Hello</p>\n", read("page.html.erb")
  end

  it "writes every Haml file in a directory next to its source" do
    write("views/posts/index.html.haml", "%ul\n  %li One\n")
    write("views/posts/_post.html.haml", "%p= post.title\n")
    write("views/layouts/application.html.haml", "%body= yield\n")

    stdout, stderr, status = herbst(File.join(@directory, "views"))

    assert_equal 0, status
    assert_empty stdout
    assert_equal "Converted 3 of 3 files.\n", stderr
    assert_equal "<ul>\n  <li>One</li>\n</ul>\n", read("views/posts/index.html.erb")
    assert_equal "<p><%= post.title %></p>\n", read("views/posts/_post.html.erb")
    assert_equal "<body><%= yield %></body>\n", read("views/layouts/application.html.erb")
  end

  it "adds another default format, or none, to files without one" do
    write("views/posts/show.haml", "%p Show\n")

    herbst(File.join(@directory, "views"), "--default-format", "turbo_stream")
    herbst(File.join(@directory, "views"), "--no-default-format")

    assert_equal "<p>Show</p>\n", read("views/posts/show.turbo_stream.erb")
    assert_equal "<p>Show</p>\n", read("views/posts/show.erb")
  end

  it "adds html to files without a format" do
    write("views/posts/show.haml", "%p Show\n")
    write("views/posts/_post.haml", "%p Post\n")
    write("views/posts/index.html.haml", "%p Index\n")
    write("views/user_mailer/welcome.text.haml", "Welcome!\n")

    _stdout, _stderr, status = herbst(File.join(@directory, "views"))

    assert_equal 0, status
    assert_equal "<p>Show</p>\n", read("views/posts/show.html.erb")
    assert_equal "<p>Post</p>\n", read("views/posts/_post.html.erb")
    assert_equal "<p>Index</p>\n", read("views/posts/index.html.erb")
    assert_equal "Welcome!\n", read("views/user_mailer/welcome.text.erb")
  end

  it "never writes over the file it converts" do
    path = write("page.txt", "%p Hello\n")

    _stdout, _stderr, status = herbst(path, "--write", "--force")

    assert_equal 0, status
    assert_equal "%p Hello\n", read("page.txt")
    assert_equal "<p>Hello</p>\n", read("page.txt.erb")
  end

  it "skips existing ERB files unless forced" do
    write("views/page.html.haml", "%p Hello\n")
    write("views/page.html.erb", "existing\n")

    _stdout, stderr, status = herbst(File.join(@directory, "views"))

    assert_equal 0, status
    assert_includes stderr, "page.html.erb already exists, skipped (use --force to overwrite)"
    assert_includes stderr, "Converted 0 of 1 file, 1 skipped."
    assert_equal "existing\n", read("views/page.html.erb")

    _stdout, _stderr, status = herbst(File.join(@directory, "views"), "--force")

    assert_equal 0, status
    assert_equal "<p>Hello</p>\n", read("views/page.html.erb")
  end

  it "keeps converting after a file fails and exits with status 1" do
    write("views/good.html.haml", "%p Good\n")
    bad = write("views/bad.html.haml", ":markdown\n  # Bad\n")

    _stdout, stderr, status = herbst(File.join(@directory, "views"))

    assert_equal 1, status
    assert_includes stderr, "#{bad}: line 1: the `:markdown` filter is not supported"
    assert_includes stderr, "Converted 1 of 2 files, 1 failed."
    assert_equal "<p>Good</p>\n", read("views/good.html.erb")
    refute File.exist?(File.join(@directory, "views/bad.html.erb"))
  end

  it "reports a difference from the round-trip check and exits with status 1" do
    path = write("page.html.haml", "%p Hello\n")

    Herbst::RoundTrip.stub(:difference, "printed ERB parses into a different tree at document") do
      stdout, stderr, status = herbst(path)

      assert_equal 1, status
      assert_equal "<p>Hello</p>\n", stdout
      assert_includes stderr, "#{path}: printed ERB parses into a different tree at document"
    end

    Herbst::RoundTrip.stub(:difference, ->(*) { flunk "the check should not run" }) do
      _stdout, _stderr, status = herbst(path, "--no-verify")

      assert_equal 0, status
    end
  end

  it "reports missing paths" do
    _stdout, stderr, status = herbst(File.join(@directory, "missing"))

    assert_equal 1, status
    assert_includes stderr, "missing: No such file or directory"
  end

  it "reports directories without Haml files" do
    _stdout, stderr, status = herbst(@directory)

    assert_equal 1, status
    assert_includes stderr, "No .haml files found"
  end

  def run_cli(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Herbst::CLI.new(arguments, stdout: stdout, stderr: stderr).run

    [stdout.string, stderr.string, status]
  end

  it "prints the help" do
    ["help", "--help", "-h"].each do |argument|
      stdout, stderr, status = run_cli(argument)

      assert_equal 0, status
      assert_empty stderr
      assert_includes stdout, "Usage:\n  bundle exec herbst [command] [options]"
      assert_includes stdout, "bundle exec herbst convert [paths]"
      assert_includes stdout, "      --no-format "
    end
  end

  it "prints the help to stderr without a command" do
    stdout, stderr, status = run_cli

    assert_equal 1, status
    assert_empty stdout
    assert_includes stderr, "Usage:\n  bundle exec herbst [command] [options]"
  end

  it "prints the help after an unknown command" do
    _stdout, stderr, status = run_cli("compile", "page.haml")

    assert_equal 1, status
    assert stderr.start_with?("Unknown command: 'compile'\n\nHerbst")
  end

  it "prints the help after an unknown option" do
    _stdout, stderr, status = run_cli("convert", "page.haml", "--nope")

    assert_equal 1, status
    assert stderr.start_with?("invalid option: --nope\n\nHerbst")
  end

  it "asks for a path when converting nothing" do
    _stdout, stderr, status = run_cli("convert")

    assert_equal 1, status
    assert stderr.start_with?("Missing path: pass the Haml files or directories to convert.\n\nHerbst")
  end

  it "prints the versions" do
    ["version", "--version", "-v"].each do |argument|
      stdout, _stderr, status = run_cli(argument)

      assert_equal 0, status
      assert_equal "herbst gem v#{Herbst::VERSION}, herb gem v#{Herb::VERSION}, haml gem v#{Haml::VERSION}\n", stdout
    end
  end

  it "runs from the executable" do
    path = write("page.html.haml", "%p Hello\n")
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXE, "convert", path, "--no-format")

    assert_predicate status, :success?
    assert_equal "<p>Hello</p>\n", stdout
    assert_empty stderr
  end
end
