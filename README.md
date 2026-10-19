<h2 align="center">🍂 Herbst</h2>

<h4 align="center">Herb Syntax Tree</h4>

<div align="center">Unified syntax tree for HTML templating languages.</div><br/>

## What is Herbst?

Herbst (German for "autumn") provides tooling to translate various HTML templating languages like Haml, Slim, and others into the same unified syntax tree used by [Herb](https://herb-tools.dev).

## Why Herbst?

Herb's tooling (the linter, formatter, language server and `Herb::Engine`) works on Herb's syntax tree, which Herb builds from HTML+ERB. Herbst builds the same tree from other templating languages, so you can:

- **Convert** Haml and Slim templates to ERB, one file or a whole `app/views` at a time
- **Compile** them with `Herb::Engine`, by converting them to ERB first
- **Use** Herb's HTML-aware tooling on templates that aren't written in ERB

All of these languages render HTML in the end, so they can all share the same syntax tree.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add herbst
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install herbst
```

## Usage

Herbst is currently in early development and supports converting Haml and Slim to ERB. Add the `haml` or `slim` gem for the languages you convert, since Herbst doesn't depend on either.

Converting and printing ERB is pure Ruby. Formatting the output (`format: true`, and the default for the CLI) runs the Herb formatter through `npx`, so it requires Node.js.

```ruby
require "herbst"

Herbst::Haml.parse("%p= greeting")   # => Herb::AST::DocumentNode
Herbst::Haml.to_erb("%p= greeting")  # => "<p><%= greeting %></p>\n"
Herbst::Haml.to_erb(source, format: true)

Herbst::Slim.parse("p = greeting")     # => Herb::AST::DocumentNode
Herbst::Slim.to_erb("p = greeting")    # => "<p><%= greeting %></p>"

Herbst::IdentityPrinter.print(Herb.parse(erb, track_whitespace: true).value)
```

Herbst doesn't compile templates. To compile Haml or Slim, compile its ERB with `Herb::Engine`:

```ruby
Herb::Engine.new(Herbst::Haml.to_erb(source), escape: true).src
```

From the command line:

```bash
exe/herbst convert app/views/posts/show.html.haml   # prints the ERB
exe/herbst convert app/views                        # writes show.html.erb next to show.html.haml or .slim
```

A single file is printed unless you pass `--write`. Directories, and several files at once, are written next to their sources with the `.haml` or `.slim` extension replaced by `.erb`, so `show.html.haml` becomes `show.html.erb`. A file without a format gets `html`, so `show.haml` becomes `show.html.erb`. Pass `--default-format FORMAT` for another format, or `--no-default-format` to write `show.erb`. The Haml and Slim files are kept, and existing ERB files are skipped unless you pass `--force`. Pass `--no-format` to skip the Herb formatter.

Constructs that cannot be converted exactly (for example splatted attribute hashes, which become `tag.attributes(...)`) are reported as warnings. Files that can't be converted, for example because they use an unsupported filter such as `:markdown`, are reported and the remaining files are still converted.

The CLI also checks that the ERB parses back into exactly the tree Herbst built, and reports any difference. Pass `--no-verify` to skip the check. The same check is available as `Herbst::RoundTrip.difference(document, erb)`. The CLI exits with status 1 when a file fails to convert or the check finds a difference.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marcoroth/herbst. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/marcoroth/herbst/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Herbst project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/marcoroth/herbst/blob/main/CODE_OF_CONDUCT.md).
