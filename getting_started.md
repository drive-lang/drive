### Quick Start

> Requires Ruby `3.4.1` or higher, and Bundler

```bash
git clone https://github.com/figgleforth/tape-lang.git
cd tape-lang
bundle install
bundle exec bin/tape learn/examples/hello.tape # => Hello, Tape!
```

### Table of Contents
 
- [Project Structure](#project-structure)
- [Extending the Language](#extending-the-language)

### Project Structure

- [`src/readme`](src/readme.md) details the architecture and contains instructions for running your own programs
- [`learn`](learn) contains more useful code examples
- [`examples`](learn/examples) contains code examples written in Tape
- [`tapes`](tapes) contains code for the Tape standard library
- [`src`](src) contains code implementing Tape
    - [Lexer](src/compiler/lexer.rb) – Source code to Lexemes
    - [Parser](src/compiler/parser.rb) – Lexemes to Expressions
    - [Type_Checker](src/compiler/type_checker.rb) – Basic type annotation checking
    - [Interpreter](src/runtime/interpreter.rb) – Entry point; `run(source)` lexes, parses, and executes

### Extending the Language

Pipeline: **Lexer → Parser → Type_Checker → Interpreter**. Methods: `lex_*` / `parse_*` / `interp_*`. New phase? Same convention, wire into `Interpreter#run`.

#### Adding a new construct

1. **Lex it** — [`lexer.rb`](src/compiler/lexer.rb)`#output` is one big `if/elsif` dispatching on the current char(s). Add a branch (or a `lex_*` helper called from one) that sets `token.type`/`token.value`.
   1. `l0`/`c0`/`l1`/`c1`/`source_file` are set automatically around every branch — you don't touch them here.
   2. Add any new symbols/keywords to the relevant list in [`constants.rb`](src/shared/constants.rb) (`RESERVED`, `PERCENT_LITERALS`, an operator list, etc.) so they're recognized/reserved.
2. **Add an AST node** — a new `Tape::Foo_Expr < Expression` in [`expressions.rb`](src/compiler/expressions.rb). Only add `attr_accessor`s for what's structurally new; `value`/`type`/`l0..c1`/`source_file` are inherited.
3. **Parse it** — add a branch to `Parser#begin_expression` (prefix position) or `#complete_expression` (infix/postfix position) in [`parser.rb`](src/compiler/parser.rb), dispatching on `curr?`/`peek`, calling a new `parse_foo_expr`. Build the `Foo_Expr`, set its location (see below), return it.
4. **Type-check it (optional)** — only if it introduces a new literal type or call shape worth statically checking. Extend `infer_type`/`check` in [`type_checker.rb`](src/compiler/type_checker.rb). Most constructs skip this — the static checker only handles literal type mismatches.
5. **Interpret it** — add a case to `Interpreter#interpret`'s dispatch and a new `interp_foo` in [`interpreter.rb`](src/runtime/interpreter.rb) that walks the `Foo_Expr` and produces a runtime value (an `Tape::*` instance, a Ruby primitive, `nil`, etc.).
6. **Test it** — `lexer_test.rb` → `parser_test.rb` → `interpreter_test.rb`/`pipeline_test.rb`, matching the phase you touched.

Worked examples: percent literals (`#parse_percent_literal_expr`/`#interp_percent_literal`), Statement (`#parse_statement_expr`/`#interp_statement`).

#### Lexeme/expression location (`l0`, `c0`, `l1`, `c1`)

1. Lexer sets these on every `Lexeme` for free — nothing to do there.
2. `Expression`s don't get location for free. `Foo_Expr.new(some_lexeme)` only copies `value`/`lexeme`.
3. Save `start = curr_lexeme` before consuming anything to get the construct's first lexeme's location
4. Build the expr, then `copy_location expr, start` before returning. Copies all four fields from one point — not a span.
   1. Or build the location yourself as a span between two lexemes.
5. Need a span (first lexeme → last)? Call `copy_location expr, start` first, then manually overwrite `l1`/`c1`/`source_file` from the closing lexeme. Pattern: `parse_struct` in `parser.rb` (search `Manually tracking location`).

#### Ruby-backed types (`Foo {}` + `Tape::Foo`)

Two files, independently optional — pure-Tape types skip #2, rare Ruby-only types skip #1:

1. **`tapes/foo.tape`** — the Tape-level declaration (`Foo { ... }`). A method that defers to Ruby is just `some_method (; @ruby )`.
2. **`src/external/ruby/foo.rb`** — `class Foo < Tape::Instance` (or `< Tape::Type`), inside `module Tape`. `extend Ruby_Proxies` + `proxy :method_name` for 1:1 delegation ([`ruby_proxies.rb`](src/shared/ruby_proxies.rb)), or hand-write `def proxy_method_name(...)` for custom logic. `@ruby` calls `proxy_#{method_name}` on the backing instance.
3. **Register the Ruby file** — `require_relative 'external/ruby/foo'` in [`src/tape.rb`](src/tape.rb)'s "External Ruby-backed built-ins" block (after `runtime/scopes`).
4. **Load the Tape file** — `@load 'tapes/foo.tape'` in [`tapes/global.tape`](tapes/global.tape) for always-on, or leave opt-in for the user's own program to `@load` (e.g. `tapes/database.tape`).
5. Nothing else — matching Tape type ↔ Ruby class is by name, dynamic at construction time (next section).

#### Linking an instance to its runtime type

1. `Interpreter#find_ruby_class_for_type(type)` walks `type.types` (most-derived first), returns the first Ruby constant `Tape::#{type_name}` that's a `Class < Tape::Instance`.
2. `Interpreter#build_instance_of_type(type, expr)` calls #1: found → `ruby_class.new`; not found → `Tape::Instance.new(type.name)`.
3. Either way: `instance.enclosing_scope = type`, `.tag` bound if any, then the type's own Tape-level body runs on it.
4. This is automatic — no manual registration call for the common case.
5. One manual hook exists: `Interpreter#link_instance_to_type(instance, type_name)`, used only by intrinsics built directly in Ruby (numbers, bools) that skip `build_instance_of_type` entirely — looks up `type_name` in the global scope, sets `instance.enclosing_scope`.

#### Instance/Type without a backing `Tape::Class`

1. Perfectly valid — most user `Type { }`s have no Ruby class; `build_instance_of_type` falls back to plain `Tape::Instance.new(type.name)`.
2. A plain `Tape::Instance` works normally for everything declared in Tape — `declarations` hash, methods, `Self(;)`, composition, structs.
3. Only `@ruby` breaks:
   - Outside a `Func` scope → `Tape::Invalid_Ruby_Proxy_Directive_Usage`.
   - Instance doesn't `respond_to?("proxy_#{method_name}")` (no Ruby class, or Ruby class missing that one `proxy_*` method) → `Tape::Missing_Ruby_Proxy_Declaration`.
4. So: forgetting the Ruby class is safe unless the `.tape` body calls `@ruby` — then it's a runtime error on first call, not at declaration time.

#### Quick file map

| Concern | File |
|---|---|
| Tokens, reserved words, operator lists, precedence | [`src/shared/constants.rb`](src/shared/constants.rb) |
| Identifier casing rules (`type_identifier?`, etc.) | [`src/shared/helpers.rb`](src/shared/helpers.rb) |
| Lexemes → tokens | [`src/compiler/lexer.rb`](src/compiler/lexer.rb), [`lexeme.rb`](src/compiler/lexeme.rb) |
| AST node classes | [`src/compiler/expressions.rb`](src/compiler/expressions.rb) |
| Tokens → AST | [`src/compiler/parser.rb`](src/compiler/parser.rb) |
| Static literal type checks | [`src/compiler/type_checker.rb`](src/compiler/type_checker.rb) |
| Scope hierarchy (`Global`/`Type`/`Instance`/`Func`/...) | [`src/runtime/scopes.rb`](src/runtime/scopes.rb) |
| AST → execution | [`src/runtime/interpreter.rb`](src/runtime/interpreter.rb) |
| Runtime errors | [`src/runtime/errors.rb`](src/runtime/errors.rb) |
| Ruby-backed built-in types | [`src/external/ruby/`](src/external/ruby) |
| `proxy`/`proxy_delegate` helpers | [`src/shared/ruby_proxies.rb`](src/shared/ruby_proxies.rb) |
| Standard library (`.tape` side of built-ins) | [`tapes/`](tape), auto-loaded via [`tapes/global.tape`](tapes/global.tape) |
| Entry points (`Tape.lex`/`.parse`/`.interp`, `+_file` variants) | [`src/tape.rb`](src/tape.rb) |
