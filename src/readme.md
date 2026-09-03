### What's here?

This [`src`](.) folder contains the implementation of Tape in Ruby. Source code moves through five phases: **Lexer → Parser → Type Checker → Declarator → Interpreter.** `Interpreter` (`src/runtime/interpreter.rb`) is the entry point: it owns a `Lexer` and `Parser`, drives all five phases via `run(source)`, and holds all execution state.

Rather than listing individual files here (they move around; check the directory itself for the current contents), here's what each one is for:

- **`compiler/`**: turns Tape source into a type-checked AST (tokenizing, parsing, static type checking, and the forward-declaration pass that lets code reference a function or type before its own definition).
- **`runtime/`**: executes that AST (the interpreter itself, the scope hierarchy: Global, Type, Instance, Func, Route, etc., and runtime error definitions).
- **`external/ruby/`**: Ruby-backed implementations of Tape's built-in types (`String`, `Array`, `Number`, etc.) that Tape-level proxy methods delegate into.
- **`systems/`**: larger subsystems layered on top of the interpreter, e.g. HTML rendering.
- **`shared/`**: constants and helper functions used across every phase.
- **`tape.rb`**: the entry point. Requires everything and exposes the `Tape` module's convenience methods (`Tape.lex`, `Tape.parse`, `Tape.interp`, and their `_file` counterparts).

---

### Running Your Own Programs With Ruby

Call `run` with source code and it handles lexing, parsing, and execution:

```ruby
require './src/tape'

interpreter = Tape::Interpreter.new
result      = interpreter.run "'Hello, World!'" # => Hello, World!
```

You can also step through each phase manually:

```ruby
require './src/tape'

lexer       = Tape::Lexer.new "'Hello, World!'"
lexemes     = lexer.output       # => array of Lexemes

parser      = Tape::Parser.new lexemes
expressions = parser.output      # => array of Expressions

interpreter       = Tape::Interpreter.new
interpreter.input = expressions
result            = interpreter.output # => Hello, World!
```

Or use the `Tape` module convenience methods:

```ruby
require './src/tape'

source      = '"Hello, Again!"'
lexemes     = Tape.lex source        # => array of Lexemes
expressions = Tape.parse source      # => array of Expressions
result      = Tape.interp source     # => Hello, Again!

source_file = './my_program.tape'
lexemes     = Tape.lex_file source_file
expressions = Tape.parse_file source_file
result      = Tape.interp_file source_file
```

### Running Your Own Programs By Command Line

This is the quickest way to run code:

```bash
bundle exec bin/tape file.tape
```

You can also use `bin/tape interp` for direct source as string evaluation:

```bash
bundle exec bin/tape interp "4 + 8"
```

For the full list of subcommands (parsing/lexing/declaration inspection, the REPL, etc.), run:

```bash
bundle exec bin/tape --help
```
