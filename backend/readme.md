### What's here?

This [`backend`](.) folder contains the implementation in Ruby. Source code moves through five phases: **Lexer → Parser → Type Checker → Declarator → Interpreter.** The phases are numbered folders, in run order.

- **`backend.rb`**: the entry point. Requires everything in load order, then exposes the `Backend` module's convenience methods (`Backend.lex`, `Backend.parse`, `Backend.interp`, and their `_file` counterparts).
- **`cli.rb`** / **`repl.rb`**: `Backend::CLI` (the `bin/prog` commands) and `Backend::REPL`.
- **`1_lexer/`** … **`5_interpreter/`**: one folder per pipeline phase. `5_interpreter/` also holds the scope hierarchy (`scopes.rb`: Global, Type, Instance, Func, Route, …), the error classes, the DOM renderer, the hot reloader, and the browser assets — everything the executor needs at runtime.
- **`proxies/`**: the Ruby class behind a built-in `.prog` type (`proxies/array.rb` ↔ `backend/array.prog`), which `@ruby` proxy methods delegate into.
- **`shared/`**: constants, mixins, and helpers pulled in across phases (`constants.rb`, `helpers.rb`, `ascii.rb`, `ruby_proxies.rb`, `error_formatter.rb`, `documenter.rb`, …).

The two Ruby modules: **`Backend::`** is the engine (the 10 pipeline/tool classes, each with `include Prog`); **`Prog::`** is everything the engine reads and makes (the AST, the scope hierarchy, the built-in value types, the errors, the constants).

---

### Running Your Own Programs With Ruby

Call `run` with source code and it handles lexing, parsing, and execution:

```ruby
require './backend/backend'

interpreter = Backend::Interpreter.new
result      = interpreter.run "'Hello, World!'" # => Hello, World!
```

You can also step through each phase manually:

```ruby
require './backend/backend'

lexer       = Backend::Lexer.new "'Hello, World!'"
lexemes     = lexer.output       # => array of Lexemes

parser      = Backend::Parser.new lexemes
expressions = parser.output      # => array of Expressions

interpreter       = Backend::Interpreter.new
interpreter.input = expressions
result            = interpreter.output # => Hello, World!
```

Or use the `Backend` module convenience methods:

```ruby
require './backend/backend'

source      = '"Hello, Again!"'
lexemes     = Backend.lex source        # => array of Lexemes
expressions = Backend.parse source      # => array of Expressions
result      = Backend.interp source     # => Hello, Again!

source_file = './my_program.prog'
lexemes     = Backend.lex_file source_file
expressions = Backend.parse_file source_file
result      = Backend.interp_file source_file
```

### Running Your Own Programs By Command Line

This is the quickest way to run code:

```bash
bundle exec bin/prog file.prog
```

You can also use `bin/prog interp` for direct source as string evaluation:

```bash
bundle exec bin/prog interp "4 + 8"
```

For the full list of subcommands (parsing/lexing/declaration inspection, the REPL, etc.), run:

```bash
bundle exec bin/prog --help
```
