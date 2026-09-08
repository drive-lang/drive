### Quick Start

> Requires Ruby `3.4.1` or higher, and Bundler

```bash
git clone https://github.com/drive-lang/drive.git
cd drive
bundle install
bundle exec bin/drive demos/hello_world.tape -p # => Hello, Drive!
```

### Table of Contents
 
- [Project Structure](#project-structure)
- [Extending the Language](#extending-the-language)

### Project Structure

- [`drive/readme`](drive/readme.md) details the architecture and contains instructions for running your own programs
- [`demos`](demos) contains more useful code examples
- [`tapes`](tapes) contains code for the Drive standard library
- [`drive`](drive) contains code implementing Drive
    - [Lexer](drive/1_lexer/lexer.rb) – Source code to Lexemes
    - [Parser](drive/2_parser/parser.rb) – Lexemes to Expressions
    - [Type_Checker](drive/3_type_checker/type_checker.rb) – Basic type annotation checking
    - [Interpreter](drive/5_interpreter/interpreter.rb) – Entry point; `run(source)` lexes, parses, and executes

### Extending the Language

Pipeline: **Lexer → Parser → Type_Checker → Interpreter**. Methods: `lex_*` / `parse_*` / `interp_*`. New phase? Same convention, wire into `Interpreter#run`.

#### Adding a new construct

1. **Lex it** — [`lexer.rb`](drive/1_lexer/lexer.rb)`#output` is one big `if/elsif` dispatching on the current char(s). Add a branch (or a `lex_*` helper called from one) that sets `token.type`/`token.value`.
   1. `l0`/`c0`/`l1`/`c1`/`source_file` are set automatically around every branch — you don't touch them here.
   2. Add any new symbols/keywords to the relevant list in [`constants.rb`](drive/shared/constants.rb) (`RESERVED`, `PERCENT_LITERALS`, an operator list, etc.) so they're recognized/reserved.
2. **Add an AST node** — a new `Tape::Foo_Expr < Expression` in [`expressions.rb`](drive/2_parser/expressions.rb). Only add `attr_accessor`s for what's structurally new; `value`/`type`/`l0..c1`/`source_file` are inherited.
3. **Parse it** — add a branch to `Parser#begin_expression` (prefix position) or `#complete_expression` (infix/postfix position) in [`parser.rb`](drive/2_parser/parser.rb), dispatching on `curr?`/`peek`, calling a new `parse_foo_expr`. Build the `Foo_Expr`, set its location (see below), return it.
4. **Type-check it (optional)** — only if it introduces a new literal type or call shape worth statically checking. Extend `infer_type`/`check` in [`type_checker.rb`](drive/3_type_checker/type_checker.rb). Most constructs skip this — the static checker only handles literal type mismatches.
5. **Interpret it** — add a case to `Interpreter#interpret`'s dispatch and a new `interp_foo` in [`interpreter.rb`](drive/5_interpreter/interpreter.rb) that walks the `Foo_Expr` and produces a runtime value (an `Tape::*` instance, a Ruby primitive, `nil`, etc.).
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

Two files, independently optional — pure-Drive types skip #2, rare Ruby-only types skip #1:

1. **`tapes/foo.tape`** — the Drive-level declaration (`Foo { ... }`). A method that defers to Ruby is just `some_method (; @ruby )`.
2. **`drive/backings/foo.rb`** — `class Foo < Tape::Instance` (or `< Tape::Type`), inside `module Drive`. `extend Ruby_Proxies` + `proxy :method_name` for 1:1 delegation ([`ruby_proxies.rb`](drive/shared/ruby_proxies.rb)), or hand-write `def proxy_method_name(...)` for custom logic. `@ruby` calls `proxy_#{method_name}` on the backing instance.
3. **Register the Ruby file** — `require_relative 'backings/foo'` in [`drive/drive.rb`](drive/drive.rb)'s "backings" block (after `5_interpreter/scopes`).
4. **Load the Drive file** — `@load 'tapes/foo.tape'` in [`tapes/global.tape`](tapes/global.tape) for always-on, or leave opt-in for the user's own program to `@load` (e.g. `tapes/database.tape`).
5. Nothing else — matching Drive type ↔ Ruby class is by name, dynamic at construction time (next section).

#### Linking an instance to its runtime type

1. `Interpreter#find_ruby_class_for_type(type)` walks `type.types` (most-derived first), returns the first Ruby constant `Tape::#{type_name}` that's a `Class < Tape::Instance`.
2. `Interpreter#build_instance_of_type(type, expr)` calls #1: found → `ruby_class.new`; not found → `Tape::Instance.new(type.name)`.
3. Either way: `instance.enclosing_scope = type`, `.tag` bound if any, then the type's own Drive-level body runs on it.
4. This is automatic — no manual registration call for the common case.
5. One manual hook exists: `Interpreter#link_instance_to_type(instance, type_name)`, used only by intrinsics built directly in Ruby (numbers, bools) that skip `build_instance_of_type` entirely — looks up `type_name` in the global scope, sets `instance.enclosing_scope`.

#### Instance/Type without a backing `Tape::Class`

1. Perfectly valid — most user `Type { }`s have no Ruby class; `build_instance_of_type` falls back to plain `Tape::Instance.new(type.name)`.
2. A plain `Tape::Instance` works normally for everything declared in Drive — `declarations` hash, methods, `Self(;)`, composition, structs.
3. Only `@ruby` breaks:
   - Outside a `Func` scope → `Tape::Invalid_Ruby_Proxy_Directive_Usage`.
   - Instance doesn't `respond_to?("proxy_#{method_name}")` (no Ruby class, or Ruby class missing that one `proxy_*` method) → `Tape::Missing_Ruby_Proxy_Declaration`.
4. So: forgetting the Ruby class is safe unless the `.tape` body calls `@ruby` — then it's a runtime error on first call, not at declaration time.

#### Quick file map

| Concern | File |
|---|---|
| Tokens, reserved words, operator lists, precedence | [`drive/shared/constants.rb`](drive/shared/constants.rb) |
| Identifier casing rules (`type_identifier?`, etc.) | [`drive/shared/helpers.rb`](drive/shared/helpers.rb) |
| Lexemes → tokens | [`drive/1_lexer/lexer.rb`](drive/1_lexer/lexer.rb), [`lexeme.rb`](drive/1_lexer/lexeme.rb) |
| AST node classes | [`drive/2_parser/expressions.rb`](drive/2_parser/expressions.rb) |
| Tokens → AST | [`drive/2_parser/parser.rb`](drive/2_parser/parser.rb) |
| Static literal type checks | [`drive/3_type_checker/type_checker.rb`](drive/3_type_checker/type_checker.rb) |
| Scope hierarchy (`Global`/`Type`/`Instance`/`Func`/...) | [`drive/5_interpreter/scopes.rb`](drive/5_interpreter/scopes.rb) |
| AST → execution | [`drive/5_interpreter/interpreter.rb`](drive/5_interpreter/interpreter.rb) |
| Runtime errors | [`drive/5_interpreter/errors.rb`](drive/5_interpreter/errors.rb) |
| Ruby-backed built-in types | [`drive/backings/`](drive/backings) |
| `proxy`/`proxy_delegate` helpers | [`drive/shared/ruby_proxies.rb`](drive/shared/ruby_proxies.rb) |
| Standard library (`.tape` side of built-ins) | [`tapes/`](tapes), auto-loaded via [`tapes/global.tape`](tapes/global.tape) |
| Entry points (`Drive.lex`/`.parse`/`.interp`, `+_file` variants) | [`drive/drive.rb`](drive/drive.rb) |
