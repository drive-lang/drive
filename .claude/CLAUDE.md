# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Relationship

User writes the code and **Claude starts in PM/advisor mode**: help maintain `todos.md`, track what's in flight, surface language gaps worth prioritizing, review approach, and act as a sounding board for design decisions — don't jump into implementation unprompted, even when a task looks small or the next step seems obvious. Only write code, run the implementation, or make edits to source/`.tape` files when explicitly asked to act as an assistant for that task. Write a changelog only when asked to.

This is a side project (sometimes PRs — other times commit straight to `main`), and keeping it feeling like one matters: the point is to push the language toward its vision himself, hitting real gaps under real workloads (see the `hockey-sim port` entry in `todos.md`), not delegating that discovery process away.

## About Tape

Tape is an educational programming language for web development, implemented in Ruby. It features:

- Naming conventions that replace keywords (Capitalized classes, lowercase functions/variables, UPPERCASE constants)
- Class composition operators instead of inheritance (|, &, ~, ^)
- Dot notation for accessing nested structures and scopes (., ..)
- First-class functions and classes
- Built-in web server support with routing
- When writing .tape source, use `#` for single-line comments (with a space after), and `###`/`###` for multi-line/block comments -- a longer run of `#`s on the outer marker nests a same-length or shorter one inside it (same rule triple-backtick ` ``` ` fences use to nest, Markdown-fence-style)

## Common Commands

### Testing

```bash
# Run all tests (default task also runs cloc)
bundle exec rake test

# Run specific test file
ruby test/lexer_test.rb

# Run all tests and cloc
bundle exec rake
```

### Running Tape Programs

```bash
# Run Tape file with hot reload (watches for changes)
bin/tape <file.tape>

# Debug/inspect compilation stages
bin/tape lex "4 + 8"              # Show lexer tokens for code string
bin/tape parse "4 + 8"            # Show AST for code string
bin/tape interp "4 + 8"           # Execute code string

bin/tape lexf <file.tape>          # Tokenize file
bin/tape parsef <file.tape>        # Parse file to AST
bin/tape interpf <file.tape>       # Execute file
```

### Setup

```bash
# Install dependencies (requires Ruby 3.4.1 and Bundler)
bundle install
```

## Architecture

Five phases: **Lexer → Parser → Type Checker → Forward Declarator → Interpreter**

`Interpreter` is the main entry point. It owns a `Lexer` and `Parser`, and exposes `run(source_code)` which drives all phases. `Lexer` and `Parser` are plain transformation classes you can also call directly.

### Compile-time (src/compiler/)

Source code is tokenized, parsed into an AST, and statically type checked:

- `lexer.rb` - Tokenizes source code into lexemes (tokens)
- `parser.rb` - Parses lexemes into an AST of expression objects
- `lexeme.rb` - Token representation
- `expressions.rb` - AST node definitions
- `type_checker.rb` - Static type checker; runs on the AST before interpretation
- `declarator.rb` - Builds `Interpreter#declarations`, the table `#resolve_forward_declaration` lazily interprets from — see Forward Declarations below

### Runtime (src/runtime/)

The AST is executed to produce output:

- `interpreter.rb` - The running program; owns `@lexer`, `@parser`, and all execution state (`stack`, `routes`, `servers`, `cached_expressions_by_filepath`, etc.); `run(source)` is the entry point; handles file loading via `load_file_into_scope`
- `scopes.rb` - All scope types and built-in types:
	- `Global < Scope` - The global scope; pushed as the bottom of the stack on first `run`; standard library declarations live here
	- `Type`, `Instance`, `Func`, `Route`, `Return` - Scope hierarchy
	- `String`, `Array`, `Number`, `Dictionary`, `Server`, `Table`, `Database`, etc. - Built-in types
- `errors.rb` - Runtime error definitions

### Systems (src/systems/)

- `server_runner.rb` - HTTP server implementation using WEBrick (routing, URL params, query strings)
- `dom_renderer.rb` - HTML rendering for `Dom` composition

### Shared (src/shared/)

- `constants.rb` - Language constants, operators, precedence table, reserved words
- `helpers.rb` - Utility functions for identifier classification (constant_identifier?, type_identifier?, member_identifier?)

### Entry Point

- `src/tape.rb` - Requires all components; exposes convenience methods:
	- `Tape.lex(source)` / `Tape.lex_file(filepath)` - Tokenize only
	- `Tape.parse(source)` / `Tape.parse_file(filepath)` - Parse to AST
	- `Tape.interp(source)` / `Tape.interp_file(filepath)` - Full execution

### Standard Library

- `tapes/preload.tape` - Auto-loaded when `load_standard_library` is `true` (default) — lands in its own `Standard_Library` scope added to Global's readable scope, not as direct Global declarations (see Readable and Writable Scopes below)
- Standard library path defined in `Tape::STANDARD_LIBRARY_PATH`

## Type Checker

The type checker (`src/compiler/type_checker.rb`) runs between the parser and interpreter. It is invoked from `Interpreter#output` before the execution loop, so it also runs on files loaded via `@load`.

### What it checks

- **Typed variable assignments** — `x: String = 123` raises `Type_Mismatch` (literal RHS only)
- **Typed function parameter defaults** — `go ( x: Number := 'bad'; x )` raises at the param default
- **Call site argument types** — `add(1, 'oops')` raises if `add` has typed params and the arg is a known literal

Annotations whose RHS is non-literal (an identifier, a function call, etc.) are silently skipped — only literal mismatches are caught statically.

### How it works

`Type_Checker` has two core methods:

- `infer_type(expr)` — maps an expression to an Tape type name string (`'String'`, `'Number'`, `'Symbol'`), or looks up `Identifier_Expr` values in `type_by_identifier`. Returns `nil` if unknown.
- `check(expr)` — recursive dispatcher; returns `nil` (no error) or a `Type_Mismatch` error. Recurses into all child-bearing expression types.

`type_by_identifier` is a hash built during the walk:
- Typed assignments (`x: String = ...`) register `'x' => 'String'`
- Named functions with typed params (`add ( a: Number; ... )`) register `'add' => ['Number', 'Number']` via `register_func`

Call site checking happens in `check_call` — it looks up the receiver name in `type_by_identifier`, retrieves the param type array, and compares each literal argument's inferred type against the expected type.

### Runtime Type Contracts (`:=`)

Separate from the static `Type_Checker` above, `:=` is a runtime-enforced type contract handled entirely in the interpreter (`interp_infix_declaration` in `interpreter.rb`), not the type checker. `:=` is also the general declaration operator — `=` is pure assignment and requires the identifier to already be declared (handled in `interp_infix_assignment`), raising `Tape::Cannot_Assign_Undeclared_Identifier` otherwise:

```tape
x := 4        # declares x, infers Number, locks x to that type
x = 8         # ok — same type
x = 'hello'   # raises Tape::Type_Contract_Violation

y = 4         # raises Tape::Cannot_Assign_Undeclared_Identifier — y was never declared

counter := -1
increment (;
	counter := 99   # shadows — declares a new local `counter`, doesn't touch the outer one
	counter += 1    # `=`/compound ops still resolve outward, so this mutates the local
)
increment()
counter           # still -1 — the outer `counter` was never touched
```

- `:=` declares the identifier, infers a type from the RHS, and records it on the assigning scope's `type_by_identifier`
- `:=` always declares on the current scope (`stack.last`), shadowing any identically-named identifier in an enclosing scope, rather than reusing/overwriting it. Plain `=` and compound ops (`+=`, etc.) still resolve through the enclosing scope via `scope_for_identifier`, which is how closures over outer variables keep working
- Subsequent plain `=` assignments to that identifier are checked against the recorded type on every assignment (not just literal RHS, unlike the static checker)
- Re-running `:=` on the same identifier re-infers and overwrites the locked type
- `=` without a prior `:=` (or a `: Type` annotation, or another declaration form — see below) raises `Tape::Cannot_Assign_Undeclared_Identifier`
- A `: Type` annotation (`x: Number = 4`) and a Class-styled identifier assigned a Scope value (`My_Type = Other {}`) are each themselves self-declaring, so `=` is allowed to introduce those identifiers too
- A bare annotated identifier with no `=` at all (`x: Number`, or a struct annotation like `thing: <String, Number>`) self-declares to `nil` rather than raising `Tape::Undeclared_Identifier` when later referenced — same as the nil-init idiom (`ident,`), handled in `interp_identifier` via `self_declare_annotated_identifier`
- Raises `Tape::Type_Contract_Violation` (`errors.rb`), not `Type_Mismatch`

### Important gotcha

`Type_Checker` lives inside `module Tape`. Bare `Array` inside the module resolves to `Tape::Array` (the built-in scope type), not Ruby's `::Array`. Always use `::Array` when checking Ruby array types (e.g. `signature.is_a? ::Array`).

### Known limitation

Call sites that appear before the function definition are not checked — the signature isn't registered yet when the call is encountered. This is a known limitation; a two-pass approach would fix it.

### Errors

- `Tape::Type_Mismatch < Tape::Type_Checking_Failed` — carries `expression`, `declared`, and `inferred`
- `Tape::Type_Checking_Failed` — raised by `output` if any errors were collected

## Forward Declarations

Top-level function/type declarations are hoisted ahead of the point where they're actually reached in the file, so calling a function (or referencing a type) before its own declaration works — including mutual recursion between two top-level functions declared in either order. Plain variable assignments (`:=`/`=`/`ident,`) are never hoisted this way; reading one before its own line has run still raises `Tape::Undeclared_Identifier`, exactly as if this feature didn't exist:

```tape
result := main()   # `main` hasn't been reached yet -- works anyway
main (; helper() )
helper (; 42 )
result             # 42

@puts "`a`"        # raises Tape::Undeclared_Identifier -- `a` is a plain variable, not hoistable
a := 123
```

### `Declarator` (`src/compiler/declarator.rb`)

Walks the whole top-level AST once, before interpretation (invoked from `Interpreter#output`, same spot `Type_Checker` runs from), building `Interpreter#declarations`: `Hash{::String => Tape::Declaration}`. `Tape::Declaration = Data.define(:key, :expr_or_decl, :expr)` — `expr` is always the *original* expression (what would need to be `interpret`ed to actually bring the declaration into being); `expr_or_decl` is a more inspectable rendering (a nested Hash for a `Type_Expr`/`Func_Expr`/`Route_Expr` body, the raw value expression for `:=`/`=`, etc.). Inspect either directly via `bin/tape declare <code>` / `declaref <file>`.

`#declare` dispatches per expression kind:

- **Nests** under its own key: `Type_Expr`, `Func_Expr` (named only), `Route_Expr`, `Func_Signature_Expr` — each recurses into its own body/params via `#declare_all`, the same Hash-building the top level itself uses. A `Type_Expr`'s own `.tag` (if any) rides along under a `'tag'` key
- **Flattens** into the enclosing level instead: `Conditional_Expr` (`if`/`unless`/`while`/`until` don't push their own scope, so a `:=` inside a branch really does land in the enclosing scope — chains through `elif`/`elwhile` via `.when_false`) and `Circumfix_Expr` (groupings don't push a scope either) — `#declare_all` accepts either a `Declaration` or a `Hash` back from `#declare`, merging the latter flat rather than nesting it under a made-up key
- **Deliberately excluded**: `For_Loop_Expr` (pushes its own scope per iteration in `#interp_for_loop` — loop-local, not forward-referenceable from outside), `Call_Expr` (its arguments can themselves use `:=` for named-argument passing, which looks identical to a declaration but isn't one — see Named Function Arguments above), and a bare `Identifier_Expr` (reads a value, doesn't declare one — registering one used to be a real bug: it silently clobbered a same-named real declaration reached later in the same Hash, since both share a key)
- **Literals** (`String_Expr`/`Number_Expr`/`Symbol_Expr`) aren't declarations on their own, but are preserved (not dropped to `nil`) as the *value* on the right of a `:=`/`=` via `#resolve_value` — a separate helper from `#declare`, used only for RHS resolution, so a literal or plain identifier RHS is stored as-is instead of wrapped in another `Declaration`

### `@load` (`Declarator#declarations_for_load`)

A bare `@load 'file'` also participates: `#declare`'s `Directive_Expr` branch hands `declarations_for_load` off to compute the *other* file's own Declarator output (parsed + declared once, cached class-level in `cached_declarations_by_filepath`, keyed by resolved path — mirrors `Interpreter.cached_expressions_by_filepath`; `currently_loading_filepaths` guards a load cycle, A `@load`ing B `@load`ing A, from recursing forever), then **rebinds every entry's `.expr` to the `@load` directive itself**, not the isolated node it was found on in the other file. This matters twice over: a loaded file's declarations aren't independent of each other (`Div | Dom {}` needs `Dom` too — forcing `Div` alone and leaving `Dom` unhoisted would break), and forcing any single name has to mark the *whole* `@load` as forced, or `#output`'s own walk redundantly re-runs the entire file a second time once it reaches that line for real. Returns nil (declines) when the path isn't a plain string literal (`@load some_var`) — nothing statically known to walk. The rebound Hash flattens into the current level the same way `Conditional_Expr`/`Circumfix_Expr` already do.

`Ident := @load 'file'` / `IDENT := @load 'file'` (a *named*, namespace-isolating load — see File Loading below) doesn't need any of the above: it's handled entirely by the existing `Infix_Expr` branch plus `#hoistable_declaration_expr?`'s casing check (next section) — forcing the whole `Infix_Expr` re-runs the real assignment, which builds the isolated scope correctly on its own.

### Interpreter (`#resolve_forward_declaration`)

The consuming side lives in `#interp_identifier`'s final `else` branch — the case where ordinary lookup found nothing and `scope` is `nil` — right before it would raise `Tape::Undeclared_Identifier`. It checks `declarations[name]`, and if a hoistable declaration is found, runs its `.expr` immediately (`interpret decl.expr`, pushed against `#global` specifically, not whatever's currently on top of `stack`), then retries the lookup.

- **Hoistable vs. not** — `HOISTABLE_EXPRESSIONS` (`Func_Expr`, `Type_Expr`, `Route_Expr`, `Struct_Expr`, `Func_Signature_Expr`, `Operator_Expr`, `Operator_Overload_Expr`; lives on `Interpreter`, not `constants.rb` — it references `Expression` subclasses, and `constants.rb` loads before `expressions.rb` does) are declarative and order-independent, so running one early changes nothing about what the program means. `#hoistable_declaration_expr?` also unwraps one level of `:=`/`=` to catch `This := That {}` (see Runtime Type Contracts above, "Class-styled identifier assigned a Scope value") — same declarative category as a bare `Type_Expr`, just spelled through an assignment. A *named* `@load` (`Ident := @load 'file'` / `IDENT := @load 'file'`) is checked the same way, but additionally requires a Capitalized/UPPERCASE left-hand name (`Tape.type_of_identifier`) — a lowercase `mod := @load 'file'` stays a plain variable, not hoisted. A *bare* `@load` (no assignment at all) is checked separately, via `#bare_load_directive_expr?` — always hoistable, since there's no left-hand name to apply a casing rule to; kept out of `#hoistable_declaration_expr?`'s own recursive unwrap specifically so it can't leak permissiveness into the named/casing-restricted case. Anything else — a plain `x := 5`, `x := some_call()`, `ident,` — is a step in the program's own imperative order, and reading it before that step runs is a bug in the *program*; forward-resolving it anyway would silently paper over that instead of raising
- **Guards against double execution** — forcing a declaration marks its `.expr` in `@forced_declarations` (identity-tracked, a plain `Set` — `Expression` doesn't override `hash`/`eql?`); `#output`'s own top-level walk skips any expression already in that set when it reaches it for real, so a forced function/type/`@load` only ever runs once. That skip has to *keep* the running result (`result` in `input.each.inject(nil) { |result, expr| ... }`), not reset it via a bare `next` — otherwise, if the skipped statement happens to be the file's *last* one, the whole program's reported result silently becomes `nil` instead of the true last value
- **Only fires when Global is actually reachable** — guarded by `stack.any? { |s| s.equal? global }` (identity check, not `#include?`, which is `==` and can hit an Tape type's own overload — e.g. `Tape::Array#==` assumes its operand also has `.values`). A plain `x.y` dot access deliberately excludes Global from its lookup (`#interp_dot_scope`'s `exclude_global_scope: true`, see Scope System below) specifically so a member missing on `x` stays missing — without this guard, forward-resolution would quietly reach past that exclusion and resolve to an unrelated global of the same name. Consequence worth knowing: a plain identifier reference (`This()`) hoists, but a `.method()` call doesn't independently hoist the method it's calling — `sign.warning()` only works once `warning`'s own declaration has actually been reached, even if `sign`'s type was itself forced early (see `learn/forward_declarations.tape`)
- **`#global`** — a dedicated reference set once when Global is created, independent of `stack` (which `#interp_member_access` temporarily swaps out during dot-access resolution — `stack.first` isn't reliably Global during that window)
- **`declarations` is saved/restored around `#load_file_into_scope`'s recursive `#output` call**, same as `@input` already was — otherwise loading a file (`@load`, especially the `x := @load 'file'` isolated-scope form) would overwrite the outer program's own `declarations` with the loaded file's, and forward-resolution would leak names declared inside an isolated module scope straight onto Global

### Known limitation

`declarations` is keyed by name at one flat level per file — a declaration nested inside a Type/Func body (or a top-level `if`/tuple, whose own declarations flatten into this same level) isn't distinguished from a genuinely top-level one. Forcing one of those runs only that one inner expression, not the construct around it (an `if`'s condition, say).

## Scope System

Tape uses a scope hierarchy, all defined in `src/runtime/scopes.rb`:

- **Global** - The global scope; pushed as the bottom of `Interpreter#stack` on first `run`; standard library declarations live here; execution state (routes, servers, loaded files, etc.) lives directly on `Interpreter`
- **Type** - Class definitions (tracks `@types`, `@expressions`)
- **Instance** - Class instances
- **Func** - Function scopes (tracks `@expressions`)
- **Route** - HTTP route handlers (extends Func, adds `@http_method`, `@path`, `@handler`, `@parts`, `@param_names`)
- **Html_Element** - HTML element scopes (tracks `@expressions`, `@attributes`, `@types`)
- **Return** - Return value wrapper (tracks `@value`)

Each scope can also have **readable** and **writable** fallback scopes - additional scopes checked after the scope's own declarations during identifier lookup, populated via `@add_readable_scope`/`@add_writable_scope` (or the `@readable`/`@writable` shorthand in function params) - see Readable and Writable Scopes below. This is distinct from `@push_scope`/`@pop_scope` (see Reopening a Scope below), which pushes a scope directly onto the interpreter's stack rather than adding a fallback lookup place.

### Scope Operators

Tape provides three scope operators for explicit scope access:

- `~/identifier` - Access global scope
- `./identifier` - Access current instance scope only
- `../identifier` - Access current type scope only

**Identifier Search Behavior:**

- `identifier` (no operator) - Searches through all scopes in the stack from current to global, including checking for proxies methods
- `./identifier` - Only searches the current instance scope (does not fall back to global)
- `../identifier` - Only searches the current type scope
- `~/identifier` - Only searches the global scope

**Privacy Convention:**

Identifiers starting with `_` are considered private by convention (e.g., `_private_var`, `_helper_function`).

**Validation:**

- Scope operators cannot be followed by literals (e.g., `../123` is a parse error)
- Using `./` outside an instance context raises `Cannot_Use_Instance_Scope_Operator_Outside_Instance`
- Using `../` outside a type context raises `Cannot_Use_Type_Scope_Operator_Outside_Type`

**Dot access (`x.y`)** resolves `y` only against `x` (plus global scope) via `#interp_member_access` (`interpreter.rb`), never the ambient call stack — without this, a member missing on `x` could fall through to an unrelated same-named member still active further down the interpreter's stack (e.g. the very method currently executing) instead of raising `Undeclared_Identifier`.

**Nil receiver.** `x.y` / `x.y()` / `x.y = z` / `x.y := z` where `x` is `nil` raises `Tape::Receiver_Is_Nil` (`"`x` is nil — no member `.y` to reach"`), not a bare `Undeclared_Identifier` (which read as if `y` were a missing type). `nil` is still a real scope with its own declared members, so `nil.to_s()` and the like keep working — the read path (`#interp_dot_scope`) only translates an `Undeclared_Identifier` to `Receiver_Is_Nil` when the lookup genuinely finds nothing and the receiver is `Tape::Nil`; the write path (`#assign_dot_member`) guards Ruby `nil` and any not-actually-declared member on `Tape::Nil` up front. `x.?y` on a nil `x` still returns `nil` (`Receiver_Is_Nil` is in `#interp_dot_infix`'s `.?` rescue list).

### `self` / `Self` Keywords

`self` and `Self` are keyword sugar for `./` and `../` respectively — `self.x` and `./x` (`Self.x` and `../x`) are exactly the same thing, just spelled differently. **The user prefers `self`/`Self` over `./`/`../` in new/edited Tape code** (`.tape` files under `learn/`, `tapes/`, `examples/`, and `readme.md`) — `./`/`../` still work and aren't being removed, but default to `self`/`Self` when writing or updating Tape source unless the surrounding code is specifically demonstrating the scope-operator spelling itself (e.g. the Scope Operators section above).

- Bare `self`/`Self` (no trailing `.identifier`) are handled in `#interp_identifier` (`interpreter.rb`): each does the same stack search `./`/`../` already do (`#current_instance`/nearest `Tape::Type`) and returns that Scope object as a real value — so `Self()` constructs the type (`Self() === Type_Name()`), `Self.declaration` reads a static, and passing `self`/`Self` around works like passing any other value
- `self.x`/`Self.x` as a `:=`/`=` write target is special-cased in `#assign_dot_member` (`interpreter.rb`, `Tape::SELF_KEYWORDS`) to route around the stricter external-`.`-write rules (`Cannot_Reassign_Constant`, `#check_dot_access_permissions!`) that a real dot-write always enforces — `./`/`../` never run those checks either, so this makes both spellings behave identically for both new and already-declared members
- `self.funk (;)`/`Self.funk (;)` (bare function declarations, no `:=`) are desugared entirely at parse time: `#parse_self_prefixed_func_name` (`parser.rb`) synthesizes the equivalent `./`/`../` scope-operator lexeme onto the function name's `Identifier_Expr`, so every downstream scope-operator-aware check (`#track_static_declaration`, the per-instance re-run skip in `#run_type_body_on_instance`) treats it identically with zero interpreter-side special-casing for this form
- `#static_var_declaration_expr?` (`interpreter.rb`) recognizes both the `../x := value` AST shape (scope-operator identifier) and the `Self.x := value` shape (dot-target) as static declarations that must run once, not per-instance — these are structurally different ASTs, so `#run_type_body_on_instance`'s skip-check needs to recognize both explicitly
- `#current_instance` (`interpreter.rb`) is the nearest `Tape::Instance` in the stack (role-based, not positional) — shared by `self`/`./` resolution and `#check_dot_access_permissions!`'s privacy check. This mattered for a real bug: `#interp_func_body` always pushes a fresh per-call `Func` frame on top of the instance, so `stack.last` during any method body is never the instance itself — a privacy check that compared against `stack.last` directly would (and did) wrongly reject `self.some_private_member` read from inside that very instance's own method, until fixed to compare against `#current_instance` instead

## Reopening a Scope

`@push_scope scope` pushes a `Type` or `Instance` directly onto the interpreter's stack, so its members become reachable without a prefix, and any bare declaration made while "inside" lands on the pushed scope itself — this actually mutates the target, unlike the readable/writable scopes described below. `@pop_scope scope` pops back out; it asserts (by identity) that `scope` is exactly what `@push_scope` last pushed, raising a plain `RuntimeError` instead of silently popping the wrong thing.

```tape
Button {
	label := 'default'
}

@push_scope Button
	css_filter := 'invert()'   # declared directly on the Button type -- every instance sees it
@pop_scope Button

b := Button()
b.css_filter   # 'invert()'
```

Reopening a `Type` extends every instance (past and future); reopening a specific `Instance` directly changes only that one value. Implemented as `#interp_directive`'s `'push_scope'`/`'pop_scope'` cases in `interpreter.rb`, calling `#push_scope`/`#pop_scope` on the interpreter's `stack`. This replaces the older `@cd`/`@cd ..` directive, which popped without naming (or checking) a target.

## Static Declarations

Type-level (static) members are declared using the `Self.` scope operator (keyword sugar for `../` — see `self` / `Self` Keywords above):

```tape
Person {
    Self.count := 0      # Static variable shared across all instances

    Self.increment (;  # Static method
        count += 1
    )

    init (;
        Self.count += 1  # Access static from instance method
    )
}

Person().init()
Person().init()
Person.increment()   # Call static method on type => 3 (2 from init(), 1 more from this call)
```

**Implementation Details:**

- Static declarations are tracked in `type.static_declarations` set
- Instance methods can access type-level variables via `Self.`/`../`
- When calling instance methods, the interpreter pushes both the type scope and instance scope onto the stack
- Instances are linked to their types via `instance.enclosing_scope = type`
- Static functions and variables are declared on the Type scope

## Member Creation Is Strict

A member must be declared in a type's own body — including via `./member := value` inside any of its own methods — before it can be written to from outside. `.` (external dot access) never creates a member:

```tape
Thing { Self (; ./member := 123 ) }   # self-declaration via ./ inside a method -- legitimate,
                                     # equivalent to declaring `member,` in the body directly
t := Thing()
t.member = 5                         # fine -- member already exists
t.missing = 5                       # raises Tape::Cannot_Assign_Undeclared_Identifier
```

- `./`/`../` self-declaration (`:=`) is only allowed while the instance is still under construction — the class body's own declarations, or `Self(;)` itself (and anything it calls). A later method self-declaring a brand-new member this way also raises `Tape::Cannot_Assign_Undeclared_Identifier`, so an instance's shape can't keep growing after it's built. Detected via `instance.has?('Self')` — `#interp_type_call` deletes the `Self` declaration the moment construction finishes, so that check is true for exactly the construction window
- Not yet covered: the equivalent restriction for `../` creating a brand-new *static* member from outside the type's original body walk — no "still being defined" signal exists for `Type` the way `has?('Self')` does for `Instance`
- A constant-named member (`X.SOME_CONST = ...`) can never be reassigned via `.`, raising `Tape::Cannot_Reassign_Constant`
- All three `.`-write forms — plain `=`, plain `:=`, and destructuring dot-targets (see Destructuring below) — share one implementation, `#assign_dot_member` in `interpreter.rb`. `:=` onto an *existing* member re-infers/overwrites its recorded type (same as re-running `:=` on a plain identifier); `=` checks the new value against any previously recorded type instead
- A `.`-write onto a `nil` receiver (`x.y = z` / `x.y := z` where `x` is `nil`) raises `Tape::Receiver_Is_Nil`, not `Cannot_Assign_Undeclared_Identifier` — see "Nil receiver" under Scope System above

## Class Composition Operators

Tape uses composition operators instead of inheritance. Applied as `Class | Other { body }`:

- `|` **Union** - merge all declarations; left side wins conflicts
- `&` **Intersection** - keep only declarations shared by both sides
- `~` **Difference** - remove right side's declarations from left side
- `^` **Symmetric Difference** - keep only unique declarations (discard shared ones)

Multiple operators can be chained: `Admin | Read_Permissions | Write_Permissions { }`.

Built-in types like `Server` and `Dom` are composed this way:

```tape
Web_App | Server { get:// (; "Hello" ) }
Layout | Dom { render (; Html([Body("Hello")]) ) }
```

(`Table` used to be composed too — `Post | Table { Self.database := ~/db }` — but the ORM moved to plain `Database` instance methods; see Database and ORM below.)

### Alias vs. subtype

Two ways to give a type a second name, with different type-identity behavior (see Type Comparison Operators):

- **`Name := Other`** — a plain alias. `Name` is bound to the *exact same* `Type` object (the "Class-styled identifier assigned a Scope value" form, see Runtime Type Contracts). Same composed-type set, so `x === Name` ⟺ `x === Other`. This is how `tapes/number.tape` declares `Int := Integer` / `Flo := Float` / `Dec := Decimal`.
- **`Name | Other {}`** — a distinct, *narrower* subtype. `Name`'s composed-type set is `{Name} ∪ Other`'s, strictly larger — so `Name =>= Other` is true but `Name === Other` is false, and a plain `Other` value is **not** `=== Name` (it doesn't carry `Name` in its set). This is `Web_App | Server {}`, `Duck | Flying {}`, etc.

Pick `:=` for a synonym, `| {}` when the new name should be its own type that `=>=` its parent without being `===` to it.

## Type Comparison Operators

Five operators compare the *composed-type sets* of Types and Instances (a type's own name plus every type it has composed via `|`/`&`/`~`/`^`), handled by `#interp_comparison_infix` (`interpreter.rb`, dispatched from `#interp_infix`). All five share the `=X=` shape (equals, symbol, equals) so they're easy to remember and hard to mistake for one another:

- `===` - exact type-set equality
- `=!=` - negation of `===`
- `=>=` - is left a superset of right (left composes with at least everything right does)
- `=<=` - is right a superset of left (mirror of `=>=` with operands reversed: `A =<= B` ≡ `B =>= A`)
- `=/=` - disjoint: the two share no composed types at all

Only `=>=` (superset) carries genuinely new information — `=<=` is `=>=` with swapped operands, and `===` is mutual `=>=` in both directions (`(A =>= B) && (B =>= A)`); `=!=` is just `!(A === B)`. The other three exist purely for readability at the call site, the same reason most languages ship both `<=`/`>=` alongside `==`/`!=` despite one being derivable from the other.

```tape
Flying { can_fly := true }
Swimming { can_swim := true }

Duck | Flying | Swimming { name := 'duck' }
Fish | Swimming { name := 'fish' }

Duck === Duck          #=> true  (identical composed-type sets)
Duck === Fish          #=> false (Duck also composes Flying)
Duck =!= Fish          #=> true
Duck =>= Swimming      #=> true  (Duck composes with at least Swimming)
Swimming =>= Duck      #=> false (Swimming doesn't compose Duck's extra types)
Swimming =<= Duck      #=> true  (mirror of the line above)
Duck =/= Fish          #=> false (both compose Swimming, so they're not disjoint)
Flying =/= Swimming    #=> true  (share nothing)
```

Struct members (see below) factor into all five: `===`/`=!=` require both the composed-type-sets *and* the structures (`left.tag&.types == right.tag&.types`) to match; `=>=`/`=<=` additionally require the member-poor side's members to be entirely present in the member-rich side's; `=/=` additionally requires the members to share nothing either. An unstructured side is treated as having no members, so `Abc === Abc` (neither side structured) is unaffected and stays `true`. Two types still sharing a composed type (e.g. both being `Abc`) always blocks `=/=` regardless of their members — disjointness means sharing *nothing*, composed types included.

### `Any` is a universal wildcard

`Any` (`tapes/preload.tape`) is a real declared type, but `==`/`!=`/`===`/`=!=` special-case it: any value or type that isn't `nil` counts as equal to `Any`, in either operand position, with no composition required — you don't need `Thing | Any {}` for `Thing` to satisfy it.

```tape
Thing { x := 1 }

String === Any      #=> true
Thing() == Any       #=> true
4 == Any             #=> true
nil == Any           #=> false -- the one exception
```

Implemented once in `#interp_comparison_infix` (`interpreter.rb`), checked up front before the normal composed-type-set/overload-lookup logic — a new `#any_type?` helper identifies the literal `Any` type (by name, not by composed types), and the check covers `==`/`!=`/`===`/`=!=` together so the negations stay consistent with their positive forms.

## Structs

`<...>` attaches runtime-inspectable metadata (a "struct") to a standalone value or a reference to an existing type. Parsed by `parse_struct` in `parser.rb` into `Tape::Struct_Expr`; interpreted by `interp_struct` in `interpreter.rb` into an `Tape::Struct` instance (`src/external/ruby/struct.rb` — no paired `.tape` file; `tapes/struct.tape` + `tapes/member.tape` are a separate, higher-level `Member`/`Struct` layer built on top of it, loaded by default via `tapes/preload.tape`).

Tagging a *Type* declaration/reference itself — as opposed to a standalone struct value — goes through `\` (`Tape::TAG_OPERATOR`, `src/shared/constants.rb`) instead of bare `<...>`, to stay unambiguous from a lone unnamed Struct-valued member (see "Each declared tag is its own type" below) and from ordinary comparisons. `\`'s RHS is resolved by `#resolve_tag_node` (`interpreter.rb`; `#resolve_tag_reference` is a thin `expr.tag` → `#resolve_tag_node` delegator), dispatched from `interp_type`/`#interp_tagged_type_declaration`:

```tape
Abc\<Number> {}              # inline literal declaration — Number becomes part of Abc's tag_declaration
Task_Schema <a: Number, b: String>  # a separately-declared struct value (bare `<...>`, no `\`)
Array\Task_Schema {}         # named reference — reuses an already-declared struct value verbatim
Array\String {}              # named reference to a Type — wrapped as the equivalent single-unnamed-member struct, same as Array\<String>
Thing\One\Two {}             # chain — Thing tagged with One, One itself tagged with Two (see "Tag chains" below)

x := Abc\<Number>             # reference — dup of the existing Abc type, tagged; doesn't mutate the original
x: Abc\<Number>                # same, as a type annotation — lands on the Identifier_Expr's `.tag`
thing: <String, Number>        # bare struct annotation — lands on the Identifier_Expr's `.type` as a Struct_Expr, sugar for `thing: Struct<String, Number>`; a standalone Tape::Struct value, unrelated to `\`
z := Abc\<4815>                # a reference tagged with an actual value rather than a type
z()                            # constructs Abc, with .tag bound before Self(;) runs
Abc\<4815>()                   # same, in one step
Abc\4815                       # bare integer, no `<...>` — shorthand for Abc\<4815> (a "version tag")
Primary_Key\Int               # bare identifier RHS is still a named reference, not this shorthand
Def {}
Def()                          # untagged types are completely unaffected — a `.tag` read on one raises Undeclared_Identifier
```

There is no standalone `\expr` expression — `\` only ever trails a type name (a declaration, a reference, or an annotation). `Identifier_Expr` and `Param_Expr` carry the tag on `.tag`; the bare `x: <...>` struct annotation lives on `.type` (an `Identifier_Expr` for a plain `: Type`, a `Struct_Expr` for `: <...>`). There is no `type_struct` field and no `Tag_Expr` node.

A named reference's RHS must resolve to a real `Tape::Struct` or `Tape::Type` — anything else raises `Tape::Tag_Reference_Must_Be_Type_Or_Struct`. Referencing a name that's a real declared Type but has no matching tagged variant yet doesn't raise — it auto-declares one on the spot (an implicit empty body via `#declare_tagged_type_variant`), so `Array\String` "just works" without requiring `Array\String {}` to have been written first; declaring it for real later reopens/extends this same auto-created variant.

- A member is any expression (`Abc\<1+2+3/123>`, `Abc\<this, that>`), not just a type name — evaluated normally at interpret time, so an identifier like `Number` resolves to the actual `Tape::Type`
- **Bare integer shorthand** (`Abc\4815`, no angle brackets): a "version tag", parsed identically to `Abc\<4815>` — a single unnamed member holding that integer. Handled by `#integer_tag_next?`/`#type_then_integer_tag_next?`/`#integer_tag_struct_expr` (`parser.rb`), in both the primary-expression dispatch and `#parse_identifier_expr`'s trailing-tag handling. Only a bare integer triggers it; `Abc\Name` stays a named reference. Used by `tapes/database.tape`'s `Primary_Key\Int` (an `Int`-tagged primary key) and left open for schema-version tagging
- Named members (`Type\<some_string: String, num: Number> {}`) reuse `parse_identifier_expr`'s existing `: Type` annotation parsing for each member — no separate grammar needed. Only two named forms exist: `name: Type` and `name := value` — there's no general `name: value` the way Dictionaries have one. `:` immediately after a bare identifier, followed by anything that isn't a capitalized type name or `<...>` (almost always a lowercase value, mistaken for Dictionary-style `key: value`), raises `Tape::Invalid_Struct_Member_Annotation` at parse time in `#parse_struct` — without that check, `#parse_identifier_expr`'s own `: Type` lookahead just declines to consume the `:` (it can never be a type), leaving it to be reparsed on the next loop iteration as an unrelated `:symbol` prefix literal starting a whole new member, since commas are optional between struct members same as any other list — `<columns: cols>` would otherwise silently become the two members `columns, :cols` instead of erroring anywhere
- A struct is only ever reachable via `.tag` (`.tag.types`, `.tag.some_string` for named members) — never auto-unpacked into `./`
- A bare identifier immediately followed by `,` inside `<...>` (`<String, Number>`) is special-cased in `parse_struct` to parse as a plain identifier rather than the nil-init idiom (`ident,` ⇒ `ident = ident or nil`), which would otherwise misfire on the exact same shape
- Reference forms (`x := Abc\<Number>`) `dup` the matched variant (see below) rather than mutating it in place — `Object#dup` is shallow, so `@declarations`/`@static_declarations` are explicitly re-forked too, otherwise tagging one reference would silently mutate every other reference sharing that variant
- Constructing from a tagged reference binds `.tag` onto the instance *before* `type.expressions` (and therefore `Self(;)`) run, so `Self`'s own body can read `.tag` — but member values are never forwarded as constructor arguments; whatever `(...)` actually passes still binds to `Self`'s own declared params, entirely separately
- A named member's value, supplied positionally at the reference site (`Woof\<'hello', 4815>`, never `Woof\<key: 'hello'>`), gets re-associated with the *matched variant's own* `tag_declaration` names before landing on the instance, so `.tag.key` still resolves correctly

### Tag chains

`Thing\One\Two` tags `Thing` with `One`, and `One` is itself tagged with `Two` — `x.tag` is `One`, `x.tag.tag` is `Two`. The parser already nests this: `#parse_identifier_expr`'s trailing-`\` branch recurses, so `\One\Two` parses as `Identifier_Expr(One)` with its own `.tag` of `Identifier_Expr(Two)` (`#parse_type_decl`'s `\Name` branch calls straight into `#parse_identifier_expr`, so it inherits the recursion). `\<...>` is always terminal — you can't chain past an inline struct (`Thing\<x: Int>\Two` is not a thing), and you can't tag a bare named struct (`Struct_Name\Tag<members>`).

`#resolve_tag_node` walks the nested `.tag`: it resolves one link to an `Tape::Struct`, and if the node carries its own `.tag`, recursively resolves that and hangs it off `struct.tag_instance` + `#declare_tag(struct)`. Each link is a real `Tape::Struct` (a `Scope`), so `.tag.tag.tag` is just ordinary dot access down the chain. `#interp_type`'s reference branch (which rebuilds the top struct to re-associate call-site member values) carries the chain across that rebuild explicitly.

Two chains sharing a prefix are distinct variants: `Thing\One\Two {}` and `Thing\One\Three {}` don't merge. `#declare_tagged_type_variant`'s collision check pairs `Struct#structure_declaration_equal?` (top level) with `#tag_chains_equal?` (recursive exact equality down `.tag_instance`), and `#find_tagged_type_variant` filters candidates through `#tag_chains_satisfy?` (recursive `=>=`-style compositional match) before its own exact/compositional pick. Both helpers treat both-nil as equal, so an unchained tag is unaffected.

### Runtime re-tagging

`x.tag = new_tag` re-tags at runtime. Handled in `#assign_dot_member` (`interpreter.rb`), in a dedicated branch right after the nil-receiver guard, so it covers both `x.tag =` and `self.tag =`:

- Only allowed when `x`'s type was declared with a tag — the branch is gated on `receiver.has?('tag')`, so `Thingy {}` then `Thingy.tag = 5` still falls through to the ordinary `Cannot_Assign_Undeclared_Identifier` (Member Creation Is Strict)
- `new_tag` is normalized to its tag `Tape::Struct` by `#tag_struct_for_reassignment` (a Struct is itself; a Type/Instance contributes its own `.tag_instance`, or is wrapped single-member)
- The new tag must `=>=` the current one at every chain link — `#tag_chains_satisfy?(receiver.tag_instance, new_tag)` — else `Tape::Tag_Signature_Violation`
- On success: `receiver.tag_instance = new_tag` + `#declare_tag(receiver)`. Methods read `.tag` live on each call; no re-running of already-run methods

### Each declared tag is its own type

`Abc\<Number> {}` and `Abc\<String> {}` are independent `Tape::Type` objects, not one shared type with two tags bolted on — declaring a tag creates a fresh type seeded from a copy of the *bare* type's own body (if one exists at declaration time), so one tagged variant's `Self`/methods can never clobber another's. This is handled by `#interp_tagged_type_declaration` (`interpreter.rb`), a sibling of `#interp_bare_type_declaration` (used for plain, untagged `Type { ... }`, which still reopens/extends one shared object as before). Both funnel into `#declare_tagged_type_variant` (shared with the auto-declare-on-reference fallback, see above) then `#finish_type_declaration` (Tape:: Ruby-class linking, `@types` bookkeeping, running the body) — reopening an existing variant (bare or tagged) only re-runs its *new* expressions, not ones already run on an earlier declaration.

Each variant is kept in a per-scope list (`Scope#tagged_type_variants`, keyed by base name — e.g. every declared tag of `String`) rather than a single mangled-string-keyed member, so `String\<dict: Dictionary> {}` and `String\<other: Dictionary> {}` are two distinct variants instead of colliding on a shared `"String<Dictionary>"` key. Matching pairs top-level structure equality (`Tape::Struct#structure_declaration_equal?`, `struct.rb` — both `names` and resolved `type_names`, positionally, mirroring the language's own `===` on Type/Instance) with `#tag_chains_equal?` for anything chained (`Thing\One\Two` vs `Thing\One\Three`).

A reference resolves by inferring a type name for each supplied value and matching that against the declared variants for that base name — but the match isn't exact-name-only: `#member_candidate_type_names` returns every type a value composes (its own name first, then everything it composes), so e.g. a `Div` satisfies a member declared `Dom` even though nothing in `tapes/html.tape` is literally named `Dom`. `Tape::Struct#satisfied_by_candidates?` checks a declared variant against those candidates (mirroring the language's own `=>=` superset operator); `#find_tagged_type_variant` first filters candidates through `#tag_chains_satisfy?` (the same compositional match, applied recursively down `.tag_instance`), then prefers an exact match before falling back to a compositional one. A lone unnamed Struct-valued member spreads at declare time but not at reference time by default (see below) — `#interp_type`'s reference branch retries with spreading applied whenever the unspread shape doesn't find anything, so a reference/composition operand can still reach a variant that was declared with spreading. A reference with no matching declared variant either auto-declares one (base name is a real Type, see above) or raises `Tape::Undeclared_Type_Structure` (base name is something else entirely).

```tape
String\<Dictionary> { to_s (; "I'm a dict-tagged string" ) }
String\<Number>     { to_s (; "I'm a number-tagged string" ) }

String\<{x=1}>().to_s()   # "I'm a dict-tagged string"   -- {x=1} is a Dictionary
String\<5>().to_s()       # "I'm a number-tagged string" -- 5 is a Number
```

### Confirmed example

```tape
String\<dict: Dictionary> {
    Self ( str: String = "";
        value = str
    )
    to_s (;
        final := value
        final += "{"
        for tag.dict
            final += "`key`::`value`, "
        end
        final += "}"
    )
}
a := String\<{x=0, y=1, z=2}>()
b := String\<{x=0, y=1, z=2}>("My dict: ")
a.to_s()   # "{x::0, y::1, z::2, }"
b.to_s()   # "My dict: {x::0, y::1, z::2, }"
```

### Runtime wiring

- `Tape::Struct < Instance`, not `Scope` — the `enclosing_scope` method-lookup fallback used for `arr.push(...)`-style calls (see `#interp_identifier`) is gated on `is_a?(Tape::Instance)`, and `Struct` needs that same fallback for `tapes/struct.tape`'s own declarations (`==`, `include?`) to be reachable at all. Note: `tapes/struct.tape`/`tapes/member.tape` are the separate, higher-level `Member`/`Struct` layer, loaded by default (`tapes/preload.tape`) but still reachable with `Tape.interp(code, load_standard_library: false)` — distinct from this low-level `Tape::Struct` Ruby class, which every struct literal goes through regardless of whether that layer is loaded, or which operator (`<...>` or `\`) built it
- Every `Tape::Struct.new` call site also calls `link_instance_to_type(struct, 'Struct')`, linking it to whichever `Struct` type is currently declared — either the bare Ruby-backed fallback (no standard library loaded), or `tapes/struct.tape`'s own `Struct { }` otherwise (see `#build_struct`)
- `.tag` is exposed on `Type`/`Instance`/`Struct` via `declare_tag` (`interpreter.rb`) — only added when a scope actually has a tag, and marked as a static declaration so it's readable straight off a bare `Type`, not just an instance. Chained tags call it on each link struct too, which is what makes `.tag.tag` resolve
- `Type` (and therefore `Instance`, which subclasses it, and `Struct`) carries two separate accessors, both holding an `Tape::Struct`:
  - `.tag_instance` (Ruby; `.tag` at the Tape level) — what a specific reference or instance was actually tagged with (`Abc\<4815>`). Set on an explicit `Abc\<...>`/`Abc\Name` reference (never the bare declared type), on each nested link struct of a chain, and by a runtime `x.tag =` write — its presence on a Type is what distinguishes "explicitly referenced" from "just the declared type" for `===`/`=!=`/etc. and for whether construction binds `.tag` at all
  - `.tag_declaration` — the type's own declared tag (`Abc\<dict: Dictionary = {}> {}`): named/positional members, annotations, and defaults. A tagged reference looks here to re-associate positional call-site values with names and fall back to defaults
  - Both live on `Type`, not `Scope`, because a tagged reference is a `dup` of the type (same Ruby class as the type itself), so a `Type`-vs-`Instance` check can't stand in for the "declared" vs "supplied" distinction — see the comments on `Type#tag_instance`/`Type#tag_declaration` in `scopes.rb`

### Bare Named Structs

`Ident<...>` where `Ident` has nothing declared under it anywhere (no bare `Type`, no tagged variant, no alias to one) isn't an error — it builds a plain `Struct`, same as `<...>` alone, except with `.name` set from the identifier:

```tape
Thing := <String, Number>   # anonymous -- .name is nil; only reachable via the variable Thing
Named <String, Number>      # named -- .name == 'Named'

n := Named<String, Number>
n.name                      # 'Named'
```

**Type lookup always takes priority.** This only kicks in when `Ident` is genuinely undeclared — a name that collides with something real still behaves exactly as it always has:

```tape
Abc\<Number> {}
Task \<a: Number> {}
Task <b: String>      # raises Tape::Undeclared_Type_Structure -- Task IS declared (as a tagged Type), just not with this shape
```

Implemented in `#interp_struct`/`#register_bare_named_struct` (`interpreter.rb`), gated on `expr.name.is_a?(Tape::Lexeme)` (`parse_struct`'s own leading-identifier capture — distinct from `\<...>`'s inline-literal form, which copies its name onto `.tag.name` as a plain String instead and so never re-triggers this path). Conflict detection checks both `find_in_stack(name)` (a bare Type or a local alias) and `tagged_variants_for(name)` (any tagged variant under that name, matching or not) — a tagged Type declaration never registers under the plain identifier namespace, so `find_in_stack` alone can't see it; either check being non-empty means something real is declared under that name, so the original error still applies.

## Enums (not finalized — don't rely on yet)

`TYPE_IDENTIFIER [ ... ]` declares an `Tape::Enum` (`Tape::Enum_Expr` in the parser, `#parse_enum_expr`; `#interp_enum`/`#build_enum`/`#build_enum_member` in `interpreter.rb`; backing Tape body in `tapes/enum.tape`, Ruby class in `src/external/ruby/enum.rb`). Members can be bare (`TODO`), bare with a trailing comma (`BUG,`), type-annotated only (`DONE: Priority`), type-annotated with a value (`CANCELLED: Priority = 99`), self-declared with a value (`ARCHIVED := 'archived'`), or a nested enum (`Nested [ A, B ]`, reachable only as `Outer.Nested`). A bare/annotated-only member's value is a Symbol matching its own name. The enum exposes `.type`, `.keys`/`.values`/`.types` (parallel Arrays), and `.count`.

**Syntactically present, but the type system isn't enforced yet**: each member's own `: Type` annotation is stored but never checked against anything — `Task_Type [ BUG: String = 'oops' ]` declares and constructs without error. The older forced-type spelling (`TYPE_IDENT :: Type { ... }`) doesn't exist anymore — `#parse_enum_expr` no longer parses a forced type at all, so `.type` is currently always `nil`. See the todos.md entry for finalizing this. Don't build real functionality on top of Enum type annotations until that's resolved.

## Destructuring

`(a, b) := <tuple-or-struct-valued expr>` extracts a Tuple's or Struct's values positionally into fresh locals or existing members:

```tape
(a, b) := (1, 2)              # Tuple source
(a, b) := <1, 2>              # Struct source
(x: Number, y) := (1, 2)      # per-target type check against the extracted value
(thing.member, local) := <Number, Number>(1, 1)  # existing-member target
```

- A plain-identifier target always declares fresh on the current scope, same shadowing behavior as any other `:=` — even if that name is already declared elsewhere
- Extracting fewer values than the source has is fine (extras discarded); asking for *more targets than the source has values* raises `Tape::Destructuring_Arity_Mismatch`
- A target can also be an existing member (`thing.member`) instead of a fresh local — this reassigns rather than declares, going through the same `#assign_dot_member` path as plain `thing.member = value` (see Member Creation Is Strict above): the member must already exist, can't be a constant, and (if it has a previously recorded type) the extracted value must match it
- Only `Tape::Tuple`/`Tape::Struct` sources are supported (`Tape::Invalid_Destructuring_Source` otherwise); a target that's neither a plain identifier nor an existing-member dot-expression raises `Tape::Invalid_Destructuring_Target`
- Implementation: `#interp_destructuring_declaration` in `interpreter.rb`, dispatched from `#interp_infix_declaration` when `expr.left` is a `()`-grouped `Circumfix_Expr`
- Not implemented: the bare (no-parens) form `a, b := ...` — needs lookahead past the whole comma-run to distinguish it from N independent nil-init declarations, deferred as not urgent

## Percent Literals

`%kind(...)` turns a space-separated list of bare items into a real `Array` of String or Symbol literals, without quoting each one individually. Parsed by `#parse_percent_literal_expr` (`parser.rb`) into `Tape::Percent_Literal_Expr`; interpreted by `#interp_percent_literal` (`interpreter.rb`).

```tape
%string(boo Hoo COOL)      # [boo, Hoo, COOL] — preserves each item's own casing
%symbol(BOO hoo Cool)      # [:BOO, :hoo, :Cool]

%str(Boo hOO COOL)         # [boo, hoo, cool] — forces lowercase
%Str(boo HOO cOOl)         # [Boo, Hoo, Cool] — forces Capitalcase
%STR(boo Hoo cool)         # [BOO, HOO, COOL] — forces UPPERCASE
# %sym/%Sym/%SYM do the same three, for symbols

cool := 2342
%string(481516 `cool`)     # [481516, 2342] — a backtick item (see Statement Expressions below) is interpolated immediately, then folded through the same casing treatment as everything else

%string(1px solid red)     # [1px, solid, red]     — "1px" stays one item, even though the lexer tokenizes it as a number then an identifier
%string(file.ext other)    # [file.ext, other]      — same for "file.ext" (identifier/operator/identifier)
```

- Eight kinds total: `string`/`str`/`Str`/`STR` (String), `symbol`/`sym`/`Sym`/`SYM` (Symbol) — see `PERCENT_LITERALS` in `constants.rb`
- Items can be identifiers, numbers, operators, or `` `expr` `` (Statement) literals; anything else (a string literal, `[1, 2]`, ...) raises `Tape::Invalid_Percent_Literal_Expression`
- **Items split only on whitespace (or `,`), not per lexer token.** `1px`/`file.ext` are each one item even though the lexer tokenizes them as several lexemes (a number then an identifier; two identifiers split by a `.` operator) — matching how the rest of Tape treats `.` as meaningful punctuation, not a word boundary. `#parse_percent_literal_item` (`parser.rb`) parses one token via `#parse_percent_literal_token` (the same one-token-at-a-time dispatch described below), then keeps merging in further tokens via `#merge_percent_literal_items` as long as `#lexeme_adjacent?` says there's no gap in the source between the previous token's end and the next one's start. A merged item always becomes a plain `Identifier_Expr` carrying the concatenated text (regardless of what token kinds it merged) — downstream (`#interp_percent_literal`) only ever reads `.value`/`.lexeme` off an item, casing included, so the merge is transparent to it. A backtick item never merges with neighboring text; it stands alone, same as before
- **Parsing (one token)**: `#parse_percent_literal_token` reads one bare token at a time (`curr? :operator`/`:number`/identifier-kind dispatch), never via the general `#parse_expression` — a symbolic operator item like `+`/`-` is also a valid PREFIX operator, and `#parse_expression` would happily reparse it as a prefix/infix expression that swallows the *next* item as its operand (`%str(+ - ^)` used to collapse into one nested `Prefix_Expr` instead of three separate items); a run like `^^^ + - * /` would similarly get glommed into one compound infix expression by ordinary expression parsing, since nothing else marks item boundaries besides whitespace
- The one remaining `else -> #parse_expression` branch exists purely so an *invalid* item still consumes at least one token — without it, the parser looped forever re-checking the same un-consumed token instead of raising `Invalid_Percent_Literal_Expression`

## @puts Directive

`#interp_directive`'s `'puts'` case (`interpreter.rb`) prints a display form (via `#stringify_for_display`, which calls the value's own `to_s`/`pretty_print` when the Tape type declares one) but **returns the original, un-stringified value** — `@puts` is a passthrough, not a statement, so it can sit inline anywhere an expression is expected: `f(@puts thing)` prints `thing` and still passes the real `thing` through to `f` untouched. Don't collapse this into `value = stringify_for_display(...); puts value; value` — that returns the printed *display string* instead of the original value, breaking the passthrough (regressed and fixed once already).

## Statement Expressions

`` `expr` `` wraps any expression without running it — an `Tape::Statement`, callable later with `()`. Parsed by `#parse_statement_expr` (`parser.rb`) into `Tape::Statement_Expr`; interpreted by `#interp_statement` (`interpreter.rb`) into an `Tape::Statement` instance (`src/external/ruby/statement.rb` + `tapes/statement.tape`).

```tape
`1+2`()                    # 3 — written and called in the same place, evaluates immediately

x := `1+2`
x()                        # 3 — stored, called later
x: Statement = `1+2`       # same thing, explicit type annotation

counter := 0
increment := `counter += 1`
increment()
increment()
increment()
counter                    # 3 — each call actually re-runs the wrapped expression; not memoized by default
```

**Scope: captured by default, opt into the caller's.** A Statement remembers the single scope it was on top of the stack when *built* (`captured_scope`, mirroring how `Tape::Func#enclosing_scope` already gives ordinary functions real closures) — calling it later, from anywhere, resolves free identifiers as if it were still running where it was written, not wherever `()` happens to be called from.

```tape
Slacker {
	count := 0
	statement: Statement

	Self ( statement; ./statement = statement )
	live_count (-> Number; statement() )
}

count := 2
captured := `count += 4`
Slacker(captured).live_count()   # 6 — resolves the *outer* count, mutating it 2 -> 6

count = 2
dynamic := `count += 4`
dynamic.use_caller_scope = true
Slacker(dynamic).live_count()    # 4 — resolves Slacker's *own* count member instead (0 -> 4); outer count untouched
```

- `.use_caller_scope = true` switches a Statement from captured (predictable, closure-like) to dynamic (resolves fresh at every call site) — see `learn/statements.tape`
- `.memoize = true` caches the first `()` result and returns it on every call after that, instead of re-running — `Memoized_Statement`/`Memoizer` no longer exist as separate types, this replaced them
- `Statement(other)` adopts `other`'s wrapped expression, `captured_scope`, and settings rather than re-capturing "wherever this `Statement(...)` call happens to be written" — `Statement(x+1)` behaves exactly like writing `` `x+1` `` directly (`Tape::Statement#proxy_from`, called from `tapes/statement.tape`'s `Self(;)`)

**Two construction paths, and why it matters.** Every Ruby-backed Tape type (`Tape::String`, `Tape::Array`, `Tape::Statement`, ...) can be built two different ways, and Statement's `captured_scope` makes the distinction concrete:

1. A backtick literal (`` `expr` ``) — `#interp_statement` builds the Ruby object directly and is the *only* place that can set `captured_scope`, since it's interpreter-side code with a live `stack` to read from; Ruby's `#initialize` has no reference to the running `Interpreter` at all.
2. An explicit `Statement(...)` call — goes through the normal Type-construction path (`#interp_type_call` -> `#build_instance_of_type`), which calls `Tape::Statement.new` with no meaningful constructor argument. Real argument binding happens afterward, separately, once `Self(;)`'s own body (`tapes/statement.tape`) runs. Ruby's `#initialize` only ever needs to set harmless defaults it can't get wrong.

`use_caller_scope`/`memoize`/`_memoized`/`_memoized_value` are declared as ordinary Tape members in `tapes/statement.tape` (not Ruby `attr_accessor`s) so plain dot-assignment (`s.memoize = true`) works with no extra plumbing; `#invoke_statement` reads/writes them from Ruby via `Scope#[]`/`#[]=`. `captured_scope` couldn't take that route — it holds a live Ruby `Scope` object, not an Tape-representable value — so it stays a Ruby `attr_accessor` instead.

A bare backtick literal builds the Ruby object directly and skips the normal Type-construction path entirely, so `#interp_statement` has to *also* run the type's own Tape-level body on the instance (`#run_type_body_on_instance`) — otherwise `use_caller_scope`/`memoize`/etc. would only ever exist on instances built the `Statement(...)` way, and `s.memoize = true` on a bare `` `expr` `` would raise `Cannot_Assign_Undeclared_Identifier`.

**Where scope-aware invocation is (and isn't) enforced.** `#invoke_statement` is the single place `use_caller_scope`/`memoize` are enforced, called from `#interp_call`'s `Tape::Statement` branch (an already-*constructed* instance being called via `()`). It doesn't apply to:
- A bare `` `expr`() `` written and called in the same place (`#interp_call`'s earlier `Tape::Statement_Expr` check) — always immediate, in whatever scope it's written in
- A `` `expr` `` item inside a percent literal (`#interp_percent_literal`) or array literal (`#interp_circumfix`) — neither ever builds a real `Tape::Statement`, so there's no instance to hold these settings on

Pushing the captured scope back on top (rather than swapping the whole stack) is deliberate: identifier lookup searches innermost-first, so one scope pushed via `#push_then_pop` wins the search over the caller's own frames underneath, without needing to hide/replace them — the same trick `#interp_func_body` already uses for ordinary `Func` closures.

## Identifier Naming Conventions

The language enforces naming conventions through the helper functions:

- **UPPERCASE** (constant_identifier?) - Constants
- **Capitalized** (type_identifier?) - Classes/types
- **lowercase** (member_identifier?) - Variables and functions

## Function Conventions

Lowercase identifier, followed by a `()` grouped block which contains `;` which separates the params and body.

```tape
<identifier> ( <args>; <body> )
```

`(...)` is also grouping, a call's argument list, and a Tuple, so a bare `(` alone doesn't say which one is coming. `func_declaration_follows?` (`parser.rb`) disambiguates by depth-checking the upcoming tokens for a bare `;` at nesting level 1 (the declaration's own params/body separator, not a nested one) before the matching `)` closes: `foo((a; a+1), 5)` is an ordinary call passing an anonymous func as its first argument — the inner func's `;` sits at depth 2, one level past `foo`'s own opening paren, so it doesn't make `foo(...)` itself look like a declaration.

### Spread lambda sugar

A call whose *single* argument is an anonymous function may drop that argument's own parens:

```tape
xs.map(x; x * 2)        # sugar for xs.map((x; x * 2))
xs.filter(n; n > 0)
xs.find(x; x == target)
xs.map(x; x * 2).filter(n; n > 2)   # chains
```

Only when the receiver is a **member access, call result, or subscript** — `xs.map(...)`, `f().g(...)`, `a[0](...)`. A bare identifier stays a declaration: `double(n; n * 2)` still *declares* `double`. And only when the tokens before the `;` are genuinely param-list-shaped (`anon_func_param_list_follows?`, `parser.rb`) — `xs.reduce(0, a; a)` (a value, then a name) does not spread. Handled in `#complete_expression` plus a `member_rhs` flag on `#begin_expression`/`#parse_expression` that stops the `.`-RHS `member(x; y)` from being read as a declaration.

## Labeled Function Arguments

Swift/ObjC-style: a param declared with two identifiers in a row (`label name`) can be called with `label: value` at the call site.

```tape
send_greeting ( to person; person )
send_greeting(to: 42)      # matches the label declared at that position
send_greeting(42)          # labels are opt-in -- a bare positional call still works
```

- Matching is purely positional — a labeled argument's label must match whatever's declared at that same param index; labels are never used to reorder arguments
- A supplied label that doesn't match the declared one at that position (including "labeled when none was declared") raises `Tape::Argument_Label_Mismatch`
- Two params can share the same label (`Self ( at x, at y; ... )` then `Point(at: 3, at: 4)`) — matching Swift, labels aren't required to be unique
- Implementation: `label: value` parses as an ordinary `:` `Infix_Expr` (same production named struct members use) — `#interp_func_body` unwraps it via `#classify_argument` before interpreting, rather than letting `#interpret` try to resolve the label as an identifier

## Named Function Arguments

`name := value` at a call site binds by the callee's declared param *name*, order-independent — a separate mechanism from labels (which check a *position*'s declared label, never reorder). Works for any call, including construction (`Self(;)` params).

```tape
sub ( a, b; a - b )
sub(a := 1, b := 2)  #=> -1
sub(b := 2, a := 1)  #=> -1, same result -- order doesn't matter
sub(1, b := 2)       #=> -1, positional then named is fine
```

- **Ordering rule**: positional arguments (bare or labeled) must come before all named arguments in a call — once you switch to naming, every argument after that has to be named too. Reverting to positional after a named argument raises `Tape::Positional_Argument_After_Named`
- The same name used twice in one call raises `Tape::Duplicate_Named_Argument`
- A param supplied both positionally *and* by name (e.g. `add(1, a := 2)` where `a` is the first param) raises `Tape::Argument_Given_By_Name_And_Position`
- A named argument whose name doesn't match any declared param raises `Tape::Unknown_Named_Argument` — checked up front, before param binding, so a typo'd name is reported directly rather than surfacing as a confusing `Tape::Missing_Argument` on some unrelated param the typo incidentally starved of a value
- A named argument bypasses label-checking entirely for that param — it's matched by declared name, not position, so there's no positional label to compare against
- Implementation: `name := value` parses as an ordinary `:=` `Infix_Expr` (same production a struct member's bare default uses) — `#classify_argument` distinguishes it from a labeled (`:`) or plain positional argument; `#interp_func_body` builds a `named_args` hash alongside the existing positional `arg_values` array, consulting it first when binding each declared param

## Struct-Typed Function Parameters

A function param can be typed with an inline struct (`: <...>`) instead of a plain type name — structural, not nominal: any argument that has each named member, with a compatible type, satisfies it, regardless of what type the argument itself is actually named.

```tape
f ( right: <name: String, type: Any, value: Any>; right.name )

m := Member('x', String, 4)
f(m)          #=> 'x' -- Member has all three, so it satisfies the struct annotation without being named "Member" in the annotation itself

f(nil)        # raises Tape::Type_Contract_Violation -- nil has none of the required members
```

- `Any` is a wildcard within a struct annotation's member types — `type: Any` matches regardless of the member's actual type (including a declared-but-nil member)
- Checked at every call — unlike a plain `: Type` param annotation (never runtime-enforced except by the static checker on literal args), a struct annotation is a real, always-checked contract
- Implementation: a `: <...>` param annotation parses onto `Param_Expr#type` as a `Struct_Expr` (same as `x: <String, Number>` on `Identifier_Expr#type`); `#check_struct_type_contract` (interpreter.rb) runs on every bound argument whose `param.type.is_a?(Tape::Struct_Expr)`, reusing `#member_candidate_type_names` (the same compositional matching `Ident<...>` structured-type references already use) to check each named member
- Found and fixed a real, previously-undiscovered lexer bug while building this: `>` immediately followed by `,`/`;` with no space (`<String>;`) lexed as one bogus combined operator token instead of two, silently breaking any struct annotation directly followed by either character

## Class Conventions

A capitalized identifier followed by a `{}` grouped block

```tape
<Identifier> { <body> }
```

`Self (;)` is the constructor. `Type()` is the one documented way to call it:

```tape
Point {
    x,
    y,

    Self ( x, y;
        ./x = x
        ./y = y
    )
}

p := Point(3, 4)  # Calls Self
```

### `Self` is an ordinary function member — no dot-based construction magic

There used to be a separate `X.new`/`X.new(...)` dot-sugar that specially meant "construct". It's gone: the constructor is just named `Self`, declared and reachable like any other function, and `Type()` is the *only* construction sugar — `X.Self`/`X.Self(...)` are deliberately **not** special-cased:

- **`Type.Self`** (bare, no parens) is an ordinary reference to the declared function, same as any other unnamed function access — it returns the raw `Tape::Func`, uncalled. This works because a type's body runs directly onto the type's own scope, not just per-instance (`#finish_type_declaration`), so `Self` stays declared there even though it's deleted off each *instance* right after its own construction finishes (see Member Creation Is Strict above). Getting this right required a bypass in `#interp_member_access` (`interpreter.rb`): without it, a dot-target literally named `Self`/`self` fell into `#interp_identifier`'s bare-keyword branch (which means "the enclosing Type/Instance", and only makes sense with *no* dot receiver at all) instead of doing plain member lookup — `Widget.Self` would silently return `Widget` itself, and `x.Self` on a non-Type receiver would raise the wrong error (`Cannot_Use_Type/Instance_Scope_Operator_Outside_Type/Instance`) instead of `Undeclared_Identifier`. The bypass triggers only when the dot-target's name is a bare `Self`/`self` (no scope operator), doing `receiver[name]`/`receiver.has?(name)` directly instead of routing through `#interp_identifier`.
- **`Type.Self()`** (called) is just an ordinary call on that `Func` — not documented, not fixed up. It never goes through `#interp_type_call`'s instance-building machinery, so no `Instance` is ever pushed; a constructor body's `self.x = ...` therefore raises `Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance`. This is "fair game" (deliberately left as-is) rather than a designed feature — a side effect of `Self` being ordinary, not something to fix or rely on.
- **`instance.Self`** raises `Tape::Undeclared_Identifier` — `Self` is deleted off an instance the moment its own construction finishes (`instance.delete :Self` in `#interp_type_call`), same as the old `:new` used to be.
- `Tape::Cannot_Initialize_Non_Type_Identifier` was removed along with the old dot-based construction special-casing (`errors.rb`) — nothing raises it anymore; a non-callable value now just raises `Tape::Cannot_Call_Value` regardless of how it's written.

**Storing a method reference as a first-class value.** `f := instance.some_method` (bare, no call) followed by `f(...)` later works correctly even from a totally unrelated scope — sibling methods `some_method` itself calls internally stay reachable. This is `#rebind_func_to_scope` (`interpreter.rb`): whenever an identifier lookup finds a `Tape::Func`, it rebinds that func's `enclosing_scope` to whatever Instance/Type it was just found on, so calling it later still has access to the rest of that instance's declarations. This only has to happen *once* per method — guarded by `enclosing_scope.instance_of?(Tape::Type)` (exact class, "still pointing at the bare declaring Type") rather than `is_a?` — `Tape::Instance < Tape::Type` in Ruby, so `is_a?` would also match a method *already* correctly bound to a specific Instance, re-rebinding it to whatever unrelated scope its *container* (a plain variable, an Array/Dictionary/struct member, ...) was found through on every subsequent read, silently losing the original binding.

## Readable and Writable Scopes

Every scope keeps two extra fallback places identifier lookup checks, after its own declarations: a **readable** scope set (read-only) and a **writable** scope set (also a fallback for writes). Neither overrides anything already reachable on the scope itself.

Both are held **weakly** — adding an instance doesn't keep it alive. Once every other reference to it is gone, it becomes eligible for GC on its own, even though it's technically still "in" the readable/writable set, and it silently stops resolving through it. This matters most for long-lived scopes (Global, or anything a running `@start_server` keeps reusing across requests) — a `Set` of strong references would otherwise pin whatever gets added for the life of the process unless it's explicitly removed.

### Auto-unpack in Function Parameters

`@readable`/`@writable` are shorthand for `@add_readable_scope`/`@add_writable_scope`, meant specifically for function param lists, where the longer names get noisy fast.

```tape
add ( @readable vec;
	x + y   # Access vec.x and vec.y directly
)

v := Vector(3, 4)
add(v)   # Returns 7
```

`@writable` unpacks the same way, but a plain write inside the body to a name the argument already has lands on that member directly instead of declaring a fresh local:

```tape
double ( @writable vec;
	x *= 2   # writes straight through to vec.x
	y *= 2
	vec
)
```

### Manual Scope Control

`@add_readable_scope instance` / `@add_writable_scope instance` (medium alias: `@add_readable`/`@add_writable`) do the same unpacking by hand, in any scope, not just a function's param list. `@remove_readable_scope`/`@remove_writable_scope` (medium alias: `@remove_readable`/`@remove_writable`) take an instance back out.

```tape
Island {
	name,
}

island := Island()
@add_readable_scope island   # Add island's members to the readable scope
x := island_member           # Access members directly

@remove_readable_scope island   # Remove island from the readable scope

thingy ( @readable island;
	# use island.name here unpacked
)
```

**Implementation details:**

- `Scope#readable_scopes`/`Scope#writable_scopes` (`scopes.rb`) are `ObjectSpace::WeakMap`s (each entry stored as its own key *and* value — `wm[x] = x` — since there's no dedicated weak-Set in the stdlib), not `Set`s, specifically so membership can't keep an instance alive on its own
- Adding/removing goes through `Scope#add_readable_scope`/`#add_writable_scope`/`#remove_readable_scope`/`#remove_writable_scope` — the only code that touches the WeakMaps directly. `#interp_directive`'s `'add_readable_scope'`/`'add_writable_scope'`/`'remove_readable_scope'`/`'remove_writable_scope'` cases (and their aliases) call these, as does `param.add_to_readable`/`param.add_to_writable` handling in `#interp_func_body` for the `@readable`/`@writable` param shorthand
- Lookup order, for both reads and writes, is `[self, writable, readable]`: own `@declarations` first, then `@writable_scopes` (most-recently-added first), then `@readable_scopes`. `Scope#get`/`#[]=`/`#delete` all check own declarations before falling back to `@writable_scopes` — an own declaration always wins over a same-named member reachable through a writable scope, for both reads and writes
- "Most-recently-added first" (`test_multiple_unpacks`) means lookups walk `@writable_scopes.keys.reverse_each`/`@readable_scopes.keys.reverse_each` — `WeakMap#keys` does preserve insertion order in practice, but unlike `Hash`/`Set`, Ruby doesn't document that as a guarantee
- Only works with `Type`/`Instance` values for the param shorthand (silently skipped for anything else); the directive forms run the target through `#maybe_instance` first (so a raw primitive like `4` becomes a real `Tape::Number`, which counts as a `Scope`) and then raise `Tape::Invalid_Scope_Directive_Argument` if it still isn't one. Because `#maybe_instance` also turns Tape `nil`/`false` into a real, Ruby-truthy value (a fresh `Tape::Nil` instance / the `Tape::Bool::FALSE` singleton), the `if target` truthiness guard those directives use to detect "nothing was passed" never actually fires for `nil`/`false` — they're silently accepted rather than rejected (`test_add_readable_scope_with_nil_argument_is_silently_accepted`/`..._with_false_argument_is_silently_accepted`, `scopes_test.rb`) — harmless in practice, since ordinary dot-write rules already prevent mutating them regardless of what scope they end up sitting in
- Renamed and split from the older combined `@ += instance`/`@ -= instance`/`@param` "sibling scope" mechanism, which had no readable/writable distinction and used a strong-reference `Set`
- `tapes/preload.tape` is loaded into its own `Standard_Library` scope (`Interpreter#run`), added to Global's readable scope rather than merged into Global's own declarations — so `String`/`Array`/etc. are reachable but not directly declared on Global (`global.declarations.key?('Array')` is `false`; `global.has?('Array')` is `true`, via the fallback). `global` is pushed onto `stack` *before* this load (rather than being the load's own target) so `~/` still resolves to real Global throughout the stdlib's own loading. Reassigning a built-in (`Array = Mine`) can never mutate the real one — `Scope#[]=` only redirects through `writable_scopes`, never `readable_scopes` — it just creates a new entry directly in Global's own declarations, shadowing the readable fallback for the rest of that `Global`'s lifetime. If `Mine` composes the original (`Mine | Array {}`), everything keeps working afterward, since proxy-method dispatch (`.length()` etc.) finds its owning type by looking up the type name in the stack, and `Mine` has those declarations composed in — and reassigning this way is a real, working way to extend every array literal in the rest of a program, not just a safe no-op

## Operator Overloading

Custom operators are declared with `@operator`, a fixity directive, a precedence number, and a function body. Parsed specially in `parser.rb` (`scan_and_register_operator_overloads_before_parsing` pre-scans and registers precedence before the main parse, since fixity/precedence affects how the rest of the file parses):

```tape
@operator -> @infix 300 ( left, right;
    right(left)
)

double ( n; n * 2 )
5 -> double  # => 10
```

- Fixities: `@infix`, `@prefix`, `@postfix`, and `@circumfix` (only `infix`/`prefix`/`postfix` are documented in `readme.md`; `circumfix` is accepted by the parser but undocumented there)
- The operator symbol can be any symbol sequence or identifier (`->`, `!!`, `pm`, `$`)
- Overloads are stored as regular functions in the declaring scope — they don't leak outside it
- Represented internally as `Tape::Operator_Overload_Expr` (fixity, precedence, operator lexeme, `Func_Expr` body)
- **Precedence**: a type's own overload for an operator always wins over a same-named one declared anywhere else. Dispatch (`#find_operator_overload` in `interpreter.rb`) checks the left operand's own declarations first, then its `enclosing_scope` (for shorthand-constructed instances that never got the type's declarations copied onto themselves — see `#interp_type_call`), and only falls back to a lexically/dynamically-scoped global operator (found by searching `stack.reverse_each`, deliberately excluding `Tape::Type`/`Tape::Instance` scopes) if the operand doesn't declare its own
- That stack search is scope-based, not global-only — an operator declared inside a function body shadows a same-named one declared outside it, for the duration of that call, with no leakage back out once the call returns
- `Tape::Type`/`Tape::Instance` scopes are excluded from that stack search specifically to prevent infinite recursion: a Type merely being on the call stack (because one of its methods is currently executing) says nothing about whether the *current* operands belong to it — without the exclusion, an overload whose body reuses its own operator symbol on unrelated operands (even plain `1 == 1`) would recurse into itself forever, since the declaring Type never leaves the stack while its own body runs

## Ranges

Four range operators, all built on the same `...`/`..<`/`>..`/`>.<` family (`RANGE_OPERATORS` in `constants.rb`, handled by `#interp_range_infix` in `interpreter.rb`, dispatched from `#interp_infix`):

```tape
1...5  # inclusive:         1, 2, 3, 4, 5
1..<5  # exclusive end:     1, 2, 3, 4
1>..5  # exclusive start:      2, 3, 4, 5
1>.<5  # exclusive both:       2, 3, 4
```

`..<` trims the end, `>..`/`>.<` bump the start by 1 — implemented as `Tape::Range.new(start, finish, exclude_end: bool)` with `start`/`start + 1` depending on operator.

## Built-in Types and Intrinsic Methods

Tape's built-in types (String, Array, Dictionary, Number) have ruby methods that delegate to Ruby's native implementations. These methods are declared using a `proxy_` prefix (see src/shared/ruby_proxies.rb)

### Intrinsic Method Implementation Pattern

**In Tape** (`.tape` files):

```tape
String {
    upcase (; @ruby )
    downcase (; @ruby )
}
```

**In Ruby** (`scopes.rb`):

```ruby

class String < Instance
	extend Ruby_Proxies

	proxy_delegate 'value' # Delegate to @value
	proxy :upcase # Calls @value.upcase
	proxy :downcase # Calls @value.downcase
end
```

**Custom ruby handlers** for methods that need special logic:

```ruby

def proxy_concat other_array
	values.concat other_array.values # Extract Ruby array first
end
```

**Methods implemented in Tape** (not as Ruby proxies):
Some methods like `find`, `any?`, and `all?` are implemented directly in Tape using for loops rather than Ruby proxies, as they need to execute Tape functions.

### String

Properties: `length`, `ord`

Methods: `upcase()`, `downcase()`, `split(delimiter)`, `slice(substr)`, `trim()`, `trim_left()`, `trim_right()`, `chars()`, `index(substr)`, `to_i()`, `to_f()`, `empty?()`, `include?(substr)`, `reverse()`, `replace(new)`, `start_with?(prefix)`, `end_with?(suffix)`, `gsub(pattern, replacement)`

`.N`-style positional dot-index (`"abc".0` -> `"a"`) indexes by character, same syntax Array/Tuple/Struct already support — a narrower dispatch (`#interp_dot_string`, `interpreter.rb`), not shared with theirs, since reusing that one outright would also pick up its `.each` shorthand branch and Ruby's own String has no `#each`. Negative/out-of-range indices behave the same as Array's own `.N`; the result is a real `Tape::String` (`#array_index_value` wraps it via `#maybe_instance`), so `"abc".0.upcase()` chains fine.

Defined in: `tapes/string.tape`, implemented in `scopes.rb` as `Tape::String`

### Array

Properties: `values`

Methods: `push(item)`, `pop()`, `shift()`, `unshift(item)`, `length()`, `first(count)`, `last(count)`, `slice(from, to)`, `reverse()`, `join(separator)`, `map(func)`, `filter(func)`, `reduce(func, init)`, `concat(other)`,`flatten()`, `sort()`, `uniq()`, `include?(item)`, `empty?()`, `find(func)` *(Tape)*, `any?(func)` *(Tape)*, `all?(func)`*(Tape)*, `each(func)`

Defined in: `tapes/array.tape`, implemented in `scopes.rb` as `Tape::Array`

**Note:** Methods marked *(Tape)* are implemented in Tape using for loops, not as Ruby proxies.

**Gotcha:** `concat` is destructive — a plain passthrough to Ruby's own `Array#concat`, so it mutates the receiver in place, unlike every other method above (`map`/`filter`/`flatten`/`reverse`/`sort`/`uniq`/...), which all return a new Array and leave the receiver untouched. Dangerous against a struct's own member array specifically, since structs are meant to be plain, immutable data — prefer `[a, b].flatten()` to combine two arrays without mutating either one.

### Dictionary

Methods: `keys()`, `values()`, `has_key?(key)`, `delete(key)`, `merge(other)`, `count()`, `empty?()`, `clear()`, `fetch(key, default)`

```tape
dict := {x: 4, y: 8}
dict[:x]           # Access by key => 4
dict[:z] = 15      # Assignment
dict.keys()        # [:x, :y, :z]
dict.values()      # [4, 8, 15]
dict.empty?()      # false
dict.count()       # 3
```

**Features:**

- Symbol, string, or identifier keys
- Subscript access via `dict[key]`
- Defined in: `tapes/dictionary.tape`, implemented in `scopes.rb` as `Tape::Dictionary`

### Number (and Integer / Float / Decimal)

Mirrors Ruby's numeric tower. `Number` is the abstract base (Ruby's `Numeric` role) — never instantiated directly. The concrete types each wrap the matching Ruby class in `value`:

| Tape type | Ruby backing | literal |
|---|---|---|
| `Integer` | `Integer` | `4` |
| `Float` | `Float` | `4.5` |
| `Decimal` | `BigDecimal` | none — `Decimal('1.50')` / `Decimal(x)` only |
| `Number` | — (base) | — |

`Int` / `Flo` / `Dec` are short **aliases** — declared `Int := Integer` (not `Int | Integer {}`), so each *is* the same `Type` object, with an identical composed-type set: `4 === Int` **and** `4 === Integer` are both true. A `| {}` subtype would instead be narrower (`4 === Int` false, `Int =>= Integer` true) — see "Alias vs. subtype" below. The temporal structs (`tapes/date.tape` etc) and DB schema columns use these aliases.

- **`#maybe_instance`** picks the class off the already-evaluated Ruby value's class (`::Integer` → `Tape::Integer`, etc). All bare `Integer`/`Float` inside `module Tape` now mean `Tape::Integer`/`Tape::Float` — use `::Integer`/`::Float` for the Ruby classes (same gotcha as `Array`).
- **`Tape::Integer < Tape::Number`**, etc. `#find_ruby_class_for_type` picks the most-derived candidate (longest ancestor chain), so `Integer(x)` builds a `Tape::Integer` (whose `value=` coerces via `to_i`; `Float`→`to_f`; `Decimal`→`BigDecimal`), not a bare `Tape::Number`.
- **Arithmetic and `<=>`** run straight on `value`, so mixed operands follow Ruby's tower. Integer division stays lossy (`7 / 2` is `3`).
- **`Ruby_Proxies.proxy_delegate_name`** walks the superclass chain (class-ivar, not inherited) so `Instance#[]=` still syncs the `value` member on a subclass; `Instance#[]=` reads the value back after the setter runs, picking up any coercion.

**Type identity.** `===` is exact type-set equality, so `4 === Integer` is **true** but `4 === Number` is **false** — use `4 =>= Number` for the "is-a" check (an `Integer` composes `Number`). Contract enforcement (`x: Number = 4`, param `:=`, destructuring, dot-member) is compositional via `#type_contract_satisfied?` (`composed_types_for(value).include?(expected)`), so `x: Number = 4` passes while `x: Integer = 4.5` doesn't. The static `Type_Checker` uses `#numeric_compatible?` (family-aware) at its three comparison sites; `infer_type(Number_Expr)` returns `'Integer'`/`'Float'`.

**Leniency on inference.** `#inferred_type_name` collapses any numeric to `'Number'` — used when *recording* a type from a value (`:=` locking, struct member inference, contract-violation messages) so `sum := 0` then `sum = 1.5` still works and struct metadata stays coarse. `#type_name_to_string` still returns the leaf (`'Integer'`), used for `===`/display. `#member_candidate_type_names` returns the compositional list (`['Integer', 'Number']`).

Properties: `value` (the wrapped Ruby number). Methods: `numerator()`, `denominator()`, `to_s()`, `abs()`, `floor()`, `ceil()`, `round()`, `sqrt()`, `even?()`, `odd?()`, `to_i()`, `to_f()`, `clamp(min, max)`. (No `type` — dropped; use `=== Integer` / `.value.class`-equivalents.)

Defined in `tapes/number.tape`, implemented in `src/external/ruby/number.rb`. `Number#initialize` coerces a non-`Numeric` argument to `0` — `#interp_directive` builds a throwaway `ruby_class.new(type_name_string)` when dispatching a static proxy (`Integer.rand`).

### Date / Time / Date_Time

Three temporal wrappers, always available (loaded by `tapes/preload.tape` — no `@load` needed). Each wraps a Ruby stdlib value: `Date` → `::Date`, `Time` → `::Time`, `Date_Time` → `::DateTime`.

```tape
Date.today()                       # today's Date
Date.parse('2020-03-15')           # Date from an ISO string
Time.now()                         # current Time
Time.at(1_700_000_000)             # Time from epoch seconds
Date_Time.now()
Date_Time.parse('2020-03-15T09:30:00+00:00')

d := Date.parse('2020-03-15')
d.year        # 2020
d.month       # 3
d.day         # 15
d.weekday     # 0  (0 = Sunday .. 6 = Saturday; Date only)
d.iso8601()   # '2020-03-15'
d.to_s()      # same as iso8601()

Time.now().epoch()   # Unix seconds (Time only)
```

- **Common members**: `year`, `month`, `day`, `iso8601()`, `to_s()` (all three). `Time`/`Date_Time` add `hour`, `minute`, `second`. `Time` adds `epoch()`. `Date` adds `weekday`.
- **Comparison**: `<`, `>`, `<=`, `>=`, `==`, `!=` all work, against another wrapper or a raw Ruby value — `Temporal#<=>` unwraps either side (`src/external/ruby/temporal.rb`).
- **Static constructors**: `Date.today`, `Date.parse`; `Time.now`, `Time.at`, `Time.parse`; `Date_Time.now`, `Date_Time.parse`.
- Backing bodies: `tapes/date.tape`, `tapes/time.tape`, `tapes/date_time.tape`. Ruby classes and the shared `Temporal` mixin: `src/external/ruby/temporal.rb`. Tests: `test/temporal_test.rb`.
- These are the types a `Date` / `Time` / `Date_Time` table column maps to — a value read back from such a column comes out as the matching wrapper, linked to its global type via `Table#linked_temporal` (`table.rb`).

### File_System (File I/O)

Static methods for reading and writing files:

```tape
content := File_System.read('./path/to/file.txt')  # Read file contents as string
File_System.write_string_to_file('./path/to/file.txt', 'Hello, World!')  # Write string to file
```

Defined in: `tapes/file_system.tape`, implemented in `scopes.rb` as `Tape::File_System`

## Loop Control Flow

### For Loops

```tape
for [1, 2, 3, 4, 5]
    result << it
end

for 1..10  # Range support
    sum += it
end

for items by 2  # Stride support
    process it  # it contains chunks of 2 items
end
```

**Intrinsic variables:**

- `it` - Current iteration value
- `at` - Current iteration index

### For Loop Verbs

For loops support transformation verbs that return values: `map`, `select`, `reject`, `count`.

```tape
`Transform each element
doubled := for [1, 2, 3, 4, 5] map
    it * 2
end  # => [2, 4, 6, 8, 10]

`Filter elements where body is truthy
evens := for [1, 2, 3, 4, 5, 6] select
    it % 2 == 0
end  # => [2, 4, 6]

`Filter elements where body is falsy
odds := for [1, 2, 3, 4, 5, 6] reject
    it % 2 == 0
end  # => [1, 3, 5]

`Count elements where body is truthy
count := for [1, 2, 3, 4, 5, 6] count
    it % 2 == 0
end  # => 3
```

**With stride:**

```tape
`Map chunks of 2
sums := for [1, 2, 3, 4, 5, 6] map by 2
    it.0 + it.1
end  # => [3, 7, 11]
```

**With stop (partial results):**

```tape
`Stop returns partial results for map/select/reject
partial := for [1, 2, 3, 4, 5] map
    stop if it == 4
    it * 2
end  # => [2, 4, 6]
```

### Loop Control Keywords

```tape
for items
    if condition
        skip  # Continue to next iteration
    end
    if other_condition
        stop  # Break out of loop
    end
end
```

- **skip** - Skip remaining loop body and continue to next iteration (like `continue`)
- **stop** - Exit the loop immediately (like `break`)
- Works with `for`, `while`, and `until` loops

### While and Until Loops

```tape
while x < 4
    x += 1
end

until x >= 23
    x += 2
end
```

Both support `elwhile`/`else` chaining (like `elif` for loops):

```tape
while x < 4
    x += 1
elwhile y > -8
    y -= 1
else
    z := 1
end
```

### Unless / Control Flows as Expressions

`unless condition` is equivalent to `if !condition`. All control flows (`if`, `unless`, `while`, `until`) are expressions and return values:

```tape
x := unless condition
    4
else
    -4
end
```

**Truthiness** (`#truthy?` in `interpreter.rb`) is uniform across all four conditional forms (`if`/`unless`/`while`/`until`) and just delegates to Ruby's own rules (`!!value`): only `nil`/`false` are falsy, everything else — `0`/`0.0` included — is truthy.

### Return Statement

The `return` keyword exits a function and returns a value. It properly propagates even when used inside loops:

```tape
find ( func;
    for values
        if func(it)
            return it  # Exits the function, not just the loop
        end
    end
    nil
)

[1, 2, 3].find(( x;
    x > 1
))  # Returns 2
```

**Implementation:**

- `return value` creates an `Tape::Return` object wrapping the value
- For loops detect `Return` objects and propagate them up to the function
- Functions unwrap the `Return` object and return the inner value
- Without `return`, functions return the last expression evaluated

## Code Style Preferences

### Ruby Code Style

- **Indentation**: Use tabs (equivalent to 4 spaces)
- **Class names**: Use `This_Case` (capitalized with underscores), not `ThisCase`
- **Method definitions**: Omit parentheses - `def something arg` not `def something(arg)`
- **Method calls**: Omit parentheses where possible - `foo.bar arg` not `foo.bar(arg)`
- **Comments**: Only add comments for non-obvious code — don't comment obvious operations. Keep each comment to 1-2 sentences on a single `#` line that wraps naturally in the editor; only start a new `#` line for a genuinely separate second point, never to manually wrap one long sentence across multiple lines

## Testing

Tests use Minitest and inherit from `Base_Test` (in test/base_test.rb):

- `test/lexer_test.rb` - Lexer tests
- `test/parser_test.rb` - Parser tests
- `test/interpreter_test.rb` - Interpreter tests
- `test/type_checker_test.rb` - Static type checker tests
- `test/composition_test.rb` - Class composition operator tests
- `test/pipeline_test.rb` - Full lex→parse→interpret pipeline tests
- `test/error_test.rb` - Runtime error tests
- `test/proxies_test.rb` - Ruby Proxy method tests
- `test/regression_test.rb` - Regression tests
- `test/server_test.rb` - Server and routing tests
- `test/e2e_server_test.rb` - End-to-end server tests
- `test/database_test.rb` - Database and ORM tests

The base test class provides `refute_raises` helper for asserting no exceptions.

## Database and ORM

Tape includes built-in database support with an ActiveRecord-style ORM using Sequel and SQLite. `tapes/database.tape` (which itself `@load`s `tapes/table.tape`) gives you both `Database`/`Sqlite` and `Table`.

### Connecting

`@connect` opens the connection and **returns the `Database`** — so the idiom is one line:

```tape
@load 'tapes/database.tape'

db := @connect Sqlite('./data/myapp.db')   # a real path
db := @connect Sqlite.memory()             # ':memory:', nothing hits disk
db := @connect Sqlite.local('demo')        # <@root>/temp/demo.db (adds `.db` if missing)
```

- `Sqlite(url)` builds an unconnected `Database` (`adapter`/`url` set, `connection` still nil). `@connect` interprets its argument, links it to the `Database` type, and lazily builds + caches the Sequel connection on it (`#interp_directive`'s `'connect'` case → `#interp_database`, `interpreter.rb`). A second `@connect` on the same `Database` returns the same cached `Sequel::SQLite::Database`.
- `@connect db` (statement form, no assignment) still works — it returns the same value, you just ignore it.
- Connecting with no `url` raises `Tape::Url_Not_Set_For_Database_Instance`.

### Schemas

A schema is a **named Struct** — one member per column, the member's type name deciding the column type. The struct's `.name` is what the table name is derived from (`User` → `users`, `Log_Schema` → `log_schemas`, via `Sequel::Inflections` pluralize/underscore), so an **anonymous** schema struct raises `Tape.assert` (a `RuntimeError`) in every method that takes one.

```tape
User <
    id: Primary_Key
    name: String
    joined_at: Date_Time
>
```

Column type names, matched by string in `Database#proxy_create_table` (`database.rb`):

| schema type | column |
|---|---|
| `Primary_Key` | auto-increment primary key (declared `Primary_Key\Int` in `tapes/database.tape`) |
| `String`, `Text` | text |
| `Int` | integer |
| `Number` | numeric |
| `Bool` | boolean (SQLite stores 0/1/NULL — see round-trip note below) |
| `Date`, `Time`, `Date_Time` | the matching Ruby date/time column |
| `Flo`/`Float`, `Decimal`, `Blob`/`Binary` | mapped, but no Tape type backs these yet |
| an `Enum`-typed member | text |

### Database methods

- `find_or_create_table(schema)` → a `Table` (creates the table if missing, otherwise just binds to it). The usual entry point.
- `create_table(schema)` → a `Table` (fails if the table already exists at the Sequel level)
- `find_table(name_or_schema)` → a `Table`, or `nil` if the table doesn't exist. Passing the schema struct also sets the returned `Table`'s `.columns`; passing a bare name (`'widgets'` / `:widgets`) does not.
- `delete_table!(name_or_schema)` — drop it. Takes a bare `Symbol`/`String` name too, so you don't need the original schema in scope to drop a table.
- `table_exists?(name_or_schema)` → `Bool`
- `tables()` → `Array` of table-name `Symbol`s
- `to_s()` → `"Database{<object_id>}"`

### Records (the `Table` instance)

The `Table` you get back carries `.columns` (the schema struct), `.database`, and `.table_name` (a plain `String`, e.g. `'users'`). Its CRUD methods are **instance methods on that object** — there is no `User | Table {}` model composition or `Self.database` static pattern anymore (removed deliberately, so one schema can be bound to more than one database). `tapes/table.tape` has no `Self.` members.

```tape
users := db.find_or_create_table(User)

cooper := users.create(<name := 'Cooper'>)   # attrs are a `:=`-member Struct, not a Dictionary
users.create(<name := 'Luna'>)

users.all()                    # Array of record Structs
users.find(cooper.id)          # one record Struct, or nil
users.find_by(<name := 'Luna'>)  # first match, or nil
users.where(<name := 'Luna'>)    # Array of matches
users.update(cooper.id, <name := 'Cooper II'>)
users.delete(cooper.id)
users.count()
```

- **A record is an `Tape::Struct`**, named after the schema, built by `Table#row_to_struct` → `Interpreter#build_struct` (`table.rb`). Read members by name (`record.name`, `record.id`); `.to_h` gives the whole row.
- `find`/`update`/`delete` take a primary key (`pk`). `find_by`/`where`/`create`/`update` take a Struct of `name := value` members.
- A filter/attrs Struct naming a column the schema doesn't have raises `Tape::Table_Invalid_Filter_Column` (checked proactively in `#check_filter_columns!`, before the query runs).
- **`Bool` round-trip**: SQLite has no boolean type, so a `Bool` column stores 0/1 (or NULL when unset). `#coerce_column_value` maps it back to a real `true`/`false` so `if record.done` and `record.done == true` both behave — before this fix an unset value read as the truthy `Bool` *type* object.
- **`Date`/`Time`/`Date_Time` round-trip**: read back as the matching wrapper instance (`record.joined_at.year`, comparisons, etc.), GC-safely linked to its global type via `#linked_temporal`.

### Implementation

- Sequel + SQLite. `Database`/`Table` proxy methods: `src/external/ruby/database.rb`, `src/external/ruby/table.rb`. Tests: `test/database_test.rb`, plus the temporal-column round-trip in `test/temporal_test.rb`.
- `Database#find_table` is a `proxy_overload` — `Tape::Struct` → `#find_table_struct`, `::String` → `#find_table_named`.
- `#table_name_for` is the single place a table name is derived from a schema struct; every struct-accepting method funnels through it, so the "must be named" assert covers all of them at once.

## Web Server Features

Tape has built-in web server support:

- **Server class composition** - Create servers by composing with the built-in `Server` class using `|` operator
- **Route syntax** - Routes defined as `method://path` (e.g., `get://`, `post://users/:id`)
- **URL parameters** - Use `:param` syntax in routes, accessed via route function parameters
- **Route precedence** - `#match_route` (`interpreter.rb`) collects every route whose segment count and literal/`:param` segments match, then picks the one with the *fewest* `:param` segments — so a fully literal route always beats a `:param` route for the same path, regardless of declaration order (`get://favicon.ico` wins over an app's own `get://:id`). `#min_by` keeps the first on a tie, matching the old `.find` order. This is what makes `tapes/server.tape`'s built-in `get://favicon.ico` / `get://apple-touch-icon.png` / `get://apple-touch-icon-precomposed.png` routes (all `ok200`) actually shield an app from the browser's automatic icon probes hitting `get://:id`
- **Query strings** - Available via `request.query` dictionary
- **Request/Response objects** - Automatically available in route handlers (from `scopes.rb`)
- **HTTP redirects** - `response.redirect(url)` for POST/Redirect/GET pattern (uses 303 See Other)
- **Form data** - POST body available via `request.body` dictionary
- **`@start` directive** - Non-blocking server startup, allows multiple concurrent servers
- **Graceful shutdown** - Servers stop when program exits
- **WEBrick backend** - HTTP server implementation in `server_runner.rb`

### Response Methods

- `response.redirect(url)` - Redirect to URL (HTTP 303 See Other, changes POST to GET)
- `response.status = code` - Set HTTP status code
- `response.headers[key] = value` - Set response headers
- `response.body = content` - Set response body

```tape
post://login (;
    if authenticate(request.body.username, request.body.password)
        response.redirect("/dashboard")
    else
        response.status = 401
        "Unauthorized"
    end
)
```

## HTML Rendering

Tape supports HTML rendering via the built-in `Dom` type (load `tapes/html.tape`). Any class composing with `Dom` that defines a `render` method will auto-render to HTML when returned from a server route.

```tape
@load 'tapes/html.tape'

Layout | Dom {
    title,

    Self ( title = 'My Page';
        ./title = title
    )

    render (;
        Html([
            Head(Title(title)),
            Body(H1("Hello!"))
        ])
    )
}
```

**HTML and CSS attributes** use `html_` and `css_` prefixes on declarations:

```tape
Styled_Div | Dom {
    html_element := 'p'
    html_class := 'my_class'
    html_id := 'my_id'
    css_background_color := 'black'
    css_color := 'white'
}
# => <p class='my_class' id='my_id' style='background-color:black;color:white;'></p>
```

**Predefined elements** in `tapes/html.tape`: `Html`, `Head`, `Body`, `Title`, `H1`–`H6`, `P`, `Span`, `A`, `Div`, `Form`, `Input`, `Button`, `Ul`, `Ol`, `Li`, `Html_Table` (not `Table` — that name is the ORM type), `Tr`, `Td`, `Th`, and more.

- Routes returning a `Dom` instance automatically render to HTML string
- HTML rendering only works when `render(;)` is called by a Server instance
- `html_element` sets the tag name (default `'div'`)
- Fence blocks starting with `html\n` are treated as raw HTML tokens by the lexer

## CSS (`tapes/css.tape`)

CSS is plain data here, no parser involved: a handful of structs build a small AST by hand, and a visitor walks whatever tree you constructed. `@load 'tapes/css.tape'` — it also `@load`s `tapes/visitor.tape` for the shared `Warnings_Visitor` mixin (see below).

**AST node structs**: `Property <name: String, value: Any, important: Bool = false>`, `Variable_Declaration <name, value>`, `Css_Function <name, args: Array>`, `Keyframe <values: Array\String, declarations: Array\Property>`, `Color <hex: String>`, `Style_Rule <selectors: Array, declarations: Array, rules: Array = []>`, `At_Rule <name, prelude: String = "", body: Any = nil>`, `Scope_Rule <root: String, limit: String = "", rules: Array = []>`, `Custom_Property_Rule <name, syntax: String, inherits: Bool = false, initial_value: Any = nil>`, `Layer_Order <names: Array\String>`, `Stylesheet <rules: Array\Css>` — `Css | Style_Rule | At_Rule | Scope_Rule | Custom_Property_Rule | Layer_Order <>` is the composed sum-type union all of those (except `Stylesheet` itself) belong to.

```tape
@load 'tapes/css.tape'

rule := Style_Rule(['.card'], [Property('color', 'red'), Property('padding', '8px')])

Css_Formatter_Visitor().format(rule)
# ".card {\n    color: red;\n    padding: 8px;\n}"

Css_Formatter_Visitor(minify := true).format(rule)
# ".card{color:red;padding:8px;}"
```

**`Css_Formatter_Visitor`** — constructed `(indent_size := 4, minify := false)`. `format(node, depth := 0, nested_in_rule := false)` dispatches on `node`'s composed type (`=== Stylesheet`/`Style_Rule`/`At_Rule`/.../`Color`, falling back to `node.to_s()`) to a matching `format_*` method.

- `nested_in_rule` decides whether `format_style_rule` synthesizes a `&` prefix on its own selectors (`format_nested_selector` — only if a selector doesn't already start with `&`/`:`) — it's passed `true` **only** from `format_style_rule`'s own recursive call over `rule.rules` (real CSS nesting, where a parent selector genuinely exists to combine with). Every other caller (`format_stylesheet`'s top-level rules, `format_at_rule`'s/`format_scope_rule`'s own body) leaves it `false`, even though those also increment `depth` — `depth > 0` alone can't tell "really nested inside another selector" apart from "just indented because an `@media`/`@scope` wraps it", which used to wrongly synthesize `&` in the latter case too (bugs.md).
- `Color`'s shorthand branch (`node.hex.has_all_same_characters?()`) relies on String's positional dot-index (`node.hex.0 * 3` — see the String section above) to repeat a single character three times; the plain branch just returns `node.hex` as-is.

**`Css_Lint_Visitor | Warnings_Visitor`** — `lint(node)` resets `self.warnings` then walks, checking each `Property` for a duplicate name (within the same `Style_Rule`), a hardcoded vendor prefix (`-webkit-`/`-moz-`/`-ms-`/`-o-`), and a redundant zero-unit (`"0px"` where `"0"` would do) via `ZERO_UNITS`/`.any?`. Recurses into `Stylesheet.rules`, `Style_Rule.rules`, `Scope_Rule.rules`, and `At_Rule.body` (when it's an Array).

## Struct-Based HTML (`tapes/html2.tape`)

Same spirit as CSS above, and coexists with `tapes/html.tape`'s `Dom` types rather than replacing them — this one only builds an HTML string, it doesn't hook into the server-side live-render pipeline (route responses, onclick wiring, `dom.js`) the way `Dom` does. `@load 'tapes/html2.tape'` — it also `@load`s `tapes/visitor.tape` and `tapes/css.tape`.

**The one node shape**: `Element <tag: String, attributes: Array\Attribute = [], css: Css = nil, children: Array = []>`. `Attribute <name: String, value: Any>` mirrors `Property` exactly — attributes are an ordered Array, not a Dictionary, so they preserve call-site order and can even collide (see `Html_Lint_Visitor` below). `children` holds a mix of `Element` structs and plain Strings (text nodes); `css`, when set, is any css.tape struct.

```tape
@load 'tapes/html2.tape'

page := div([h1('Welcome'), p('Hello!')], [], Style_Rule(['.greeting'], [Property('color', 'blue')]))

Html_Render.render(page)
# '<div><h1>Welcome</h1><p>Hello!</p><style>.greeting{color:blue;}</style></div>'
```

**`Html_Formatter_Visitor`** — constructed `(indent_size := 2, minify := false)`, same "one type, a mode flag" shape as `Css_Formatter_Visitor`. `Html_Render`/`Html_Format` are two shared instances (compact/pretty). `render(node, depth := 0)` dispatches on `node === Element` (else calls `node.to_s()` for a bare text child).

- Void tags (`VOID_TAGS`: `area base br col command embed hr img input keygen link meta param source track wbr`) never get a closing tag, in either mode.
- A single bare-text child stays on one line (`<p>Hello</p>`) rather than always expanding to block style; any other shape (multiple children, or an Element child) expands.
- `css`, if attached, renders as one more child — an embedded `<style>` block (`css_child`), built via a fresh `Css_Formatter_Visitor` sharing this visitor's own `indent_size`/`minify` — appended with `[el.children, [css_child(el.css)]].flatten()`, not `.concat` (see the Array `concat` gotcha above: `.concat` would permanently corrupt `el.children` in place, duplicating the `<style>` tag on a second render).

**`Html_Stats_Visitor`** — `analyze(node)` resets `node_count`/`max_depth`/`tag_counts` then walks; `unique_tags()` reads `tag_counts.keys()`; `minified_size(node)`/`pretty_size(node)` just re-render via `Html_Render`/`Html_Format` and read `.length`.

**`Html_Sanitizer_Visitor`** — `sanitize(node)` returns a cleaned copy (the original is untouched; Elements are plain data). Drops `script`/`iframe`/`object`/`embed` tags entirely, along with their children; strips `on*` attributes and `javascript:`-valued `href`/`src` attributes from whatever's left.

**`Html_Lint_Visitor | Warnings_Visitor`** — `lint(node)` resets `self.warnings` then walks, checking for a void element given children, an `<img>` missing `alt`, an empty (non-void) container, and a duplicate attribute name (`check_duplicate_attributes` — a real possibility now that `attributes` is an ordered Array, not a Dictionary).

**Element constructors** — one lowercase function per tag (`div`, `p`, `h1`–`h6`, `href`, `img`, `input`, ..., full parity with `tapes/html.tape`'s predefined element list), each just `Element("tag", attributes, css, children)`. Lowercase, not capitalized like `tapes/html.tape`'s `Div`/`Title`/etc — a capitalized name before `(` routes to type-reference parsing instead of a function declaration.

- `as_children(children)` wraps a single bare child (a String, or one Element) into a one-element Array, so `li("one")` and `li(["one", "two"])` both just work.
- `merge_attribute(attributes, attr)` gives `href`/`utf8_meta` the same override-in-place-or-append semantics `Dictionary#merge` used to, before `attributes` became an Array: replaces an existing same-named `Attribute` in place, or appends if there isn't one — non-destructive (builds a new Array via `.map`/`.flatten()`, never mutates the caller's own array).

## Shared Visitor Mixin (`tapes/visitor.tape`)

`Warnings_Visitor` — `warnings := []` plus `warn(message)` (pushes onto it) — composed (`| Warnings_Visitor`) into both `Css_Lint_Visitor` and `Html_Lint_Visitor` above, so neither hand-rolls its own accumulator. Loaded automatically by both `tapes/css.tape` and `tapes/html2.tape`.

## File Loading

The `@load` directive allows importing Tape files:

- Interpreter caches parsed expressions in `@cached_expressions_by_filepath` to prevent duplicate parsing
- Files are loaded into a specified scope via `Interpreter#load_file_into_scope`
- Expressions are cached keyed by resolved filepath
- Separately, running (not just parsing) a file into a given scope is deduped per-scope: `Scope#loaded_filepaths` (a `Hash`, keyed by resolved filepath) records the result the first time a file is actually loaded into that scope. A later `@load` of the same file into the *same* scope returns that stored result directly instead of re-running the file — without this, a repeated bare `@load` used to re-run the file's whole body again and could return `nil` instead of the original result. Loading the same file into a *different* scope (e.g. two separate `x := @load 'file'` namespacing calls) still runs it again, since the cache lives on the target scope, not globally — this is what makes namespace isolation actually isolated
- Comment lexemes are filtered out before parsing, matching `#run`'s top-level behavior — otherwise a trailing comment at the end of a loaded file's function/program body would silently become that body's return value
- The target scope depends on the call form:
  - Bare `@load 'file'` merges the file's top-level declarations directly into the current scope (`stack.last`) — `tapes/preload.tape` uses this same mechanism, but `Interpreter#run`'s bootstrap passes a fresh `Standard_Library` scope as the target (not `global` itself), so e.g. `String` lands there, not as a direct Global declaration — see Readable and Writable Scopes below
  - `some_lib := @load 'file'` instead creates a fresh `Tape::Scope` named after the left-hand identifier, loads the file into *that*, and assigns it — giving real namespace isolation, e.g. `some_lib.square(5)`
