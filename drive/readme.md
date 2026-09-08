### What's here?

This [`drive`](.) folder contains the implementation of Drive in Ruby. Source code moves through five phases: **Lexer → Parser → Type Checker → Declarator → Interpreter.** The phases are numbered folders, in run order.

- **`drive.rb`**: the entry point. Requires everything in load order, then exposes the `Drive` module's convenience methods (`Drive.lex`, `Drive.parse`, `Drive.interp`, and their `_file` counterparts).
- **`cli.rb`** / **`repl.rb`**: `Drive::CLI` (the `bin/drive` commands) and `Drive::REPL`.
- **`1_lexer/`** … **`5_interpreter/`**: one folder per pipeline phase. `5_interpreter/` also holds the scope hierarchy (`scopes.rb`: Global, Type, Instance, Func, Route, …), the error classes, the DOM renderer, the hot reloader, and the browser assets — everything the executor needs at runtime.
- **`backings/`**: the Ruby class behind a built-in `.tape` type (`backings/array.rb` ↔ `tapes/array.tape`), which `@ruby` proxy methods delegate into.
- **`shared/`**: constants, mixins, and helpers pulled in across phases (`constants.rb`, `helpers.rb`, `ascii.rb`, `ruby_proxies.rb`, `error_formatter.rb`, `documenter.rb`, …).

The two Ruby modules: **`Drive::`** is the engine (the 10 pipeline/tool classes, each with `include Tape`); **`Tape::`** is everything the engine reads and makes (the AST, the scope hierarchy, the built-in value types, the errors, the constants).

---

### Running Your Own Programs With Ruby

Call `run` with source code and it handles lexing, parsing, and execution:

```ruby
require './drive/drive'

interpreter = Drive::Interpreter.new
result      = interpreter.run "'Hello, World!'" # => Hello, World!
```

You can also step through each phase manually:

```ruby
require './drive/drive'

lexer       = Drive::Lexer.new "'Hello, World!'"
lexemes     = lexer.output       # => array of Lexemes

parser      = Drive::Parser.new lexemes
expressions = parser.output      # => array of Expressions

interpreter       = Drive::Interpreter.new
interpreter.input = expressions
result            = interpreter.output # => Hello, World!
```

Or use the `Drive` module convenience methods:

```ruby
require './drive/drive'

source      = '"Hello, Again!"'
lexemes     = Drive.lex source        # => array of Lexemes
expressions = Drive.parse source      # => array of Expressions
result      = Drive.interp source     # => Hello, Again!

source_file = './my_program.tape'
lexemes     = Drive.lex_file source_file
expressions = Drive.parse_file source_file
result      = Drive.interp_file source_file
```

### Running Your Own Programs By Command Line

This is the quickest way to run code:

```bash
bundle exec bin/drive file.tape
```

You can also use `bin/drive interp` for direct source as string evaluation:

```bash
bundle exec bin/drive interp "4 + 8"
```

For the full list of subcommands (parsing/lexing/declaration inspection, the REPL, etc.), run:

```bash
bundle exec bin/drive --help
```
