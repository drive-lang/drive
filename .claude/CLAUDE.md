# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Relationship

User writes the code and **Claude starts in PM/advisor mode**: help maintain `todos.md`, track what's in flight, surface language gaps worth prioritizing, review approach, and act as a sounding board for design decisions — don't jump into implementation unprompted, even when a task looks small or the next step seems obvious. Only write code, run the implementation, or make edits to source/`.tape` files when explicitly asked to act as an assistant for that task. Write a changelog only when asked to.

This is a side project (sometimes PRs — other times commit straight to `main`), and keeping it feeling like one matters: the point is to push the language toward its vision himself, hitting real gaps under real workloads (see the `hockey-sim port` entry in `todos.md`), not delegating that discovery process away.

## About Lost

Lost is an educational programming language for web development, implemented in Ruby. It features:

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

### Running Lost Programs

```bash
# Run Lost file with hot reload (watches for changes)
bin/lost <file.tape>

# Debug/inspect compilation stages
bin/lost lex "4 + 8"              # Show lexer tokens for code string
bin/lost parse "4 + 8"            # Show AST for code string
bin/lost interp "4 + 8"           # Execute code string

bin/lost lexf <file.tape>          # Tokenize file
bin/lost parsef <file.tape>        # Parse file to AST
bin/lost interpf <file.tape>       # Execute file
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

- `src/lost.rb` - Requires all components; exposes convenience methods:
	- `Lost.lex(source)` / `Lost.lex_file(filepath)` - Tokenize only
	- `Lost.parse(source)` / `Lost.parse_file(filepath)` - Parse to AST
	- `Lost.interp(source)` / `Lost.interp_file(filepath)` - Full execution

### Standard Library

- `lost/preload.tape` - Auto-loaded when `load_standard_library` is `true` (default) — lands in its own `Standard_Library` scope added to Global's readable scope, not as direct Global declarations (see Readable and Writable Scopes below)
- Standard library path defined in `Lost::STANDARD_LIBRARY_PATH`

## Type Checker

The type checker (`src/compiler/type_checker.rb`) runs between the parser and interpreter. It is invoked from `Interpreter#output` before the execution loop, so it also runs on files loaded via `@load`.

### What it checks

- **Typed variable assignments** — `x: String = 123` raises `Type_Mismatch` (literal RHS only)
- **Typed function parameter defaults** — `go ( x: Number := 'bad'; x )` raises at the param default
- **Call site argument types** — `add(1, 'oops')` raises if `add` has typed params and the arg is a known literal

Annotations whose RHS is non-literal (an identifier, a function call, etc.) are silently skipped — only literal mismatches are caught statically.

### How it works

`Type_Checker` has two core methods:

- `infer_type(expr)` — maps an expression to an Lost type name string (`'String'`, `'Number'`, `'Symbol'`), or looks up `Identifier_Expr` values in `type_by_identifier`. Returns `nil` if unknown.
- `check(expr)` — recursive dispatcher; returns `nil` (no error) or a `Type_Mismatch` error. Recurses into all child-bearing expression types.

`type_by_identifier` is a hash built during the walk:
- Typed assignments (`x: String = ...`) register `'x' => 'String'`
- Named functions with typed params (`add ( a: Number; ... )`) register `'add' => ['Number', 'Number']` via `register_func`

Call site checking happens in `check_call` — it looks up the receiver name in `type_by_identifier`, retrieves the param type array, and compares each literal argument's inferred type against the expected type.

### Runtime Type Contracts (`:=`)

Separate from the static `Type_Checker` above, `:=` is a runtime-enforced type contract handled entirely in the interpreter (`interp_infix_declaration` in `interpreter.rb`), not the type checker. `:=` is also the general declaration operator — `=` is pure assignment and requires the identifier to already be declared (handled in `interp_infix_assignment`), raising `Lost::Cannot_Assign_Undeclared_Identifier` otherwise:

```lost
x := 4        # declares x, infers Number, locks x to that type
x = 8         # ok — same type
x = 'hello'   # raises Lost::Type_Contract_Violation

y = 4         # raises Lost::Cannot_Assign_Undeclared_Identifier — y was never declared

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
- `=` without a prior `:=` (or a `: Type` annotation, or another declaration form — see below) raises `Lost::Cannot_Assign_Undeclared_Identifier`
- A `: Type` annotation (`x: Number = 4`) and a Class-styled identifier assigned a Scope value (`My_Type = Other {}`) are each themselves self-declaring, so `=` is allowed to introduce those identifiers too
- A bare annotated identifier with no `=` at all (`x: Number`, or a struct annotation like `thing: <String, Number>`) self-declares to `nil` rather than raising `Lost::Undeclared_Identifier` when later referenced — same as the nil-init idiom (`ident,`), handled in `interp_identifier` via `self_declare_annotated_identifier`
- Raises `Lost::Type_Contract_Violation` (`errors.rb`), not `Type_Mismatch`

### Important gotcha

`Type_Checker` lives inside `module Lost`. Bare `Array` inside the module resolves to `Lost::Array` (the built-in scope type), not Ruby's `::Array`. Always use `::Array` when checking Ruby array types (e.g. `signature.is_a? ::Array`).

### Known limitation

Call sites that appear before the function definition are not checked — the signature isn't registered yet when the call is encountered. This is a known limitation; a two-pass approach would fix it.

### Errors

- `Lost::Type_Mismatch < Lost::Type_Checking_Failed` — carries `expression`, `declared`, and `inferred`
- `Lost::Type_Checking_Failed` — raised by `output` if any errors were collected

## Forward Declarations

Top-level function/type declarations are hoisted ahead of the point where they're actually reached in the file, so calling a function (or referencing a type) before its own declaration works — including mutual recursion between two top-level functions declared in either order. Plain variable assignments (`:=`/`=`/`ident,`) are never hoisted this way; reading one before its own line has run still raises `Lost::Undeclared_Identifier`, exactly as if this feature didn't exist:

```lost
result := main()   # `main` hasn't been reached yet -- works anyway
main (; helper() )
helper (; 42 )
result             # 42

@puts "`a`"        # raises Lost::Undeclared_Identifier -- `a` is a plain variable, not hoistable
a := 123
```

### `Declarator` (`src/compiler/declarator.rb`)

Walks the whole top-level AST once, before interpretation (invoked from `Interpreter#output`, same spot `Type_Checker` runs from), building `Interpreter#declarations`: `Hash{::String => Lost::Declaration}`. `Lost::Declaration = Data.define(:key, :expr_or_decl, :expr)` — `expr` is always the *original* expression (what would need to be `interpret`ed to actually bring the declaration into being); `expr_or_decl` is a more inspectable rendering (a nested Hash for a `Type_Expr`/`Func_Expr`/`Route_Expr` body, the raw value expression for `:=`/`=`, etc.). Inspect either directly via `bin/lost declare <code>` / `declaref <file>`.

`#declare` dispatches per expression kind:

- **Nests** under its own key: `Type_Expr`, `Func_Expr` (named only), `Route_Expr`, `Func_Signature_Expr` — each recurses into its own body/params via `#declare_all`, the same Hash-building the top level itself uses. A `Type_Expr`'s own `.tag` (if any) rides along under a `'tag'` key
- **Flattens** into the enclosing level instead: `Conditional_Expr` (`if`/`unless`/`while`/`until` don't push their own scope, so a `:=` inside a branch really does land in the enclosing scope — chains through `elif`/`elwhile` via `.when_false`) and `Circumfix_Expr` (groupings don't push a scope either) — `#declare_all` accepts either a `Declaration` or a `Hash` back from `#declare`, merging the latter flat rather than nesting it under a made-up key
- **Deliberately excluded**: `For_Loop_Expr` (pushes its own scope per iteration in `#interp_for_loop` — loop-local, not forward-referenceable from outside), `Call_Expr` (its arguments can themselves use `:=` for named-argument passing, which looks identical to a declaration but isn't one — see Named Function Arguments above), and a bare `Identifier_Expr` (reads a value, doesn't declare one — registering one used to be a real bug: it silently clobbered a same-named real declaration reached later in the same Hash, since both share a key)
- **Literals** (`String_Expr`/`Number_Expr`/`Symbol_Expr`) aren't declarations on their own, but are preserved (not dropped to `nil`) as the *value* on the right of a `:=`/`=` via `#resolve_value` — a separate helper from `#declare`, used only for RHS resolution, so a literal or plain identifier RHS is stored as-is instead of wrapped in another `Declaration`

### `@load` (`Declarator#declarations_for_load`)

A bare `@load 'file'` also participates: `#declare`'s `Directive_Expr` branch hands `declarations_for_load` off to compute the *other* file's own Declarator output (parsed + declared once, cached class-level in `cached_declarations_by_filepath`, keyed by resolved path — mirrors `Interpreter.cached_expressions_by_filepath`; `currently_loading_filepaths` guards a load cycle, A `@load`ing B `@load`ing A, from recursing forever), then **rebinds every entry's `.expr` to the `@load` directive itself**, not the isolated node it was found on in the other file. This matters twice over: a loaded file's declarations aren't independent of each other (`Div | Dom {}` needs `Dom` too — forcing `Div` alone and leaving `Dom` unhoisted would break), and forcing any single name has to mark the *whole* `@load` as forced, or `#output`'s own walk redundantly re-runs the entire file a second time once it reaches that line for real. Returns nil (declines) when the path isn't a plain string literal (`@load some_var`) — nothing statically known to walk. The rebound Hash flattens into the current level the same way `Conditional_Expr`/`Circumfix_Expr` already do.

`Ident := @load 'file'` / `IDENT := @load 'file'` (a *named*, namespace-isolating load — see File Loading below) doesn't need any of the above: it's handled entirely by the existing `Infix_Expr` branch plus `#hoistable_declaration_expr?`'s casing check (next section) — forcing the whole `Infix_Expr` re-runs the real assignment, which builds the isolated scope correctly on its own.

### Interpreter (`#resolve_forward_declaration`)

The consuming side lives in `#interp_identifier`'s final `else` branch — the case where ordinary lookup found nothing and `scope` is `nil` — right before it would raise `Lost::Undeclared_Identifier`. It checks `declarations[name]`, and if a hoistable declaration is found, runs its `.expr` immediately (`interpret decl.expr`, pushed against `#global` specifically, not whatever's currently on top of `stack`), then retries the lookup.

- **Hoistable vs. not** — `HOISTABLE_EXPRESSIONS` (`Func_Expr`, `Type_Expr`, `Route_Expr`, `Struct_Expr`, `Func_Signature_Expr`, `Operator_Expr`, `Operator_Overload_Expr`; lives on `Interpreter`, not `constants.rb` — it references `Expression` subclasses, and `constants.rb` loads before `expressions.rb` does) are declarative and order-independent, so running one early changes nothing about what the program means. `#hoistable_declaration_expr?` also unwraps one level of `:=`/`=` to catch `This := That {}` (see Runtime Type Contracts above, "Class-styled identifier assigned a Scope value") — same declarative category as a bare `Type_Expr`, just spelled through an assignment. A *named* `@load` (`Ident := @load 'file'` / `IDENT := @load 'file'`) is checked the same way, but additionally requires a Capitalized/UPPERCASE left-hand name (`Lost.type_of_identifier`) — a lowercase `mod := @load 'file'` stays a plain variable, not hoisted. A *bare* `@load` (no assignment at all) is checked separately, via `#bare_load_directive_expr?` — always hoistable, since there's no left-hand name to apply a casing rule to; kept out of `#hoistable_declaration_expr?`'s own recursive unwrap specifically so it can't leak permissiveness into the named/casing-restricted case. Anything else — a plain `x := 5`, `x := some_call()`, `ident,` — is a step in the program's own imperative order, and reading it before that step runs is a bug in the *program*; forward-resolving it anyway would silently paper over that instead of raising
- **Guards against double execution** — forcing a declaration marks its `.expr` in `@forced_declarations` (identity-tracked, a plain `Set` — `Expression` doesn't override `hash`/`eql?`); `#output`'s own top-level walk skips any expression already in that set when it reaches it for real, so a forced function/type/`@load` only ever runs once. That skip has to *keep* the running result (`result` in `input.each.inject(nil) { |result, expr| ... }`), not reset it via a bare `next` — otherwise, if the skipped statement happens to be the file's *last* one, the whole program's reported result silently becomes `nil` instead of the true last value
- **Only fires when Global is actually reachable** — guarded by `stack.any? { |s| s.equal? global }` (identity check, not `#include?`, which is `==` and can hit an Lost type's own overload — e.g. `Lost::Array#==` assumes its operand also has `.values`). A plain `x.y` dot access deliberately excludes Global from its lookup (`#interp_dot_scope`'s `exclude_global_scope: true`, see Scope System below) specifically so a member missing on `x` stays missing — without this guard, forward-resolution would quietly reach past that exclusion and resolve to an unrelated global of the same name. Consequence worth knowing: a plain identifier reference (`This()`) hoists, but a `.method()` call doesn't independently hoist the method it's calling — `sign.warning()` only works once `warning`'s own declaration has actually been reached, even if `sign`'s type was itself forced early (see `learn/forward_declarations.tape`)
- **`#global`** — a dedicated reference set once when Global is created, independent of `stack` (which `#interp_member_access` temporarily swaps out during dot-access resolution — `stack.first` isn't reliably Global during that window)
- **`declarations` is saved/restored around `#load_file_into_scope`'s recursive `#output` call**, same as `@input` already was — otherwise loading a file (`@load`, especially the `x := @load 'file'` isolated-scope form) would overwrite the outer program's own `declarations` with the loaded file's, and forward-resolution would leak names declared inside an isolated module scope straight onto Global

### Known limitation

`declarations` is keyed by name at one flat level per file — a declaration nested inside a Type/Func body (or a top-level `if`/tuple, whose own declarations flatten into this same level) isn't distinguished from a genuinely top-level one. Forcing one of those runs only that one inner expression, not the construct around it (an `if`'s condition, say).

## Scope System

Lost uses a scope hierarchy, all defined in `src/runtime/scopes.rb`:

- **Global** - The global scope; pushed as the bottom of `Interpreter#stack` on first `run`; standard library declarations live here; execution state (routes, servers, loaded files, etc.) lives directly on `Interpreter`
- **Type** - Class definitions (tracks `@types`, `@expressions`)
- **Instance** - Class instances
- **Func** - Function scopes (tracks `@expressions`)
- **Route** - HTTP route handlers (extends Func, adds `@http_method`, `@path`, `@handler`, `@parts`, `@param_names`)
- **Html_Element** - HTML element scopes (tracks `@expressions`, `@attributes`, `@types`)
- **Return** - Return value wrapper (tracks `@value`)

Each scope can also have **readable** and **writable** fallback scopes - additional scopes checked after the scope's own declarations during identifier lookup, populated via `@add_readable_scope`/`@add_writable_scope` (or the `@readable`/`@writable` shorthand in function params) - see Readable and Writable Scopes below. This is distinct from `@push_scope`/`@pop_scope` (see Reopening a Scope below), which pushes a scope directly onto the interpreter's stack rather than adding a fallback lookup place.

### Scope Operators

Lost provides three scope operators for explicit scope access:

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

**Nil receiver.** `x.y` / `x.y()` / `x.y = z` / `x.y := z` where `x` is `nil` raises `Lost::Receiver_Is_Nil` (`"`x` is nil — no member `.y` to reach"`), not a bare `Undeclared_Identifier` (which read as if `y` were a missing type). `nil` is still a real scope with its own declared members, so `nil.to_s()` and the like keep working — the read path (`#interp_dot_scope`) only translates an `Undeclared_Identifier` to `Receiver_Is_Nil` when the lookup genuinely finds nothing and the receiver is `Lost::Nil`; the write path (`#assign_dot_member`) guards Ruby `nil` and any not-actually-declared member on `Lost::Nil` up front. `x.?y` on a nil `x` still returns `nil` (`Receiver_Is_Nil` is in `#interp_dot_infix`'s `.?` rescue list).

### `self` / `Self` Keywords

`self` and `Self` are keyword sugar for `./` and `../` respectively — `self.x` and `./x` (`Self.x` and `../x`) are exactly the same thing, just spelled differently. **The user prefers `self`/`Self` over `./`/`../` in new/edited Lost code** (`.tape` files under `learn/`, `lost/`, `examples/`, and `readme.md`) — `./`/`../` still work and aren't being removed, but default to `self`/`Self` when writing or updating Lost source unless the surrounding code is specifically demonstrating the scope-operator spelling itself (e.g. the Scope Operators section above).

- Bare `self`/`Self` (no trailing `.identifier`) are handled in `#interp_identifier` (`interpreter.rb`): each does the same stack search `./`/`../` already do (`#current_instance`/nearest `Lost::Type`) and returns that Scope object as a real value — so `Self()` constructs the type (`Self() === Type_Name()`), `Self.declaration` reads a static, and passing `self`/`Self` around works like passing any other value
- `self.x`/`Self.x` as a `:=`/`=` write target is special-cased in `#assign_dot_member` (`interpreter.rb`, `Lost::SELF_KEYWORDS`) to route around the stricter external-`.`-write rules (`Cannot_Reassign_Constant`, `#check_dot_access_permissions!`) that a real dot-write always enforces — `./`/`../` never run those checks either, so this makes both spellings behave identically for both new and already-declared members
- `self.funk (;)`/`Self.funk (;)` (bare function declarations, no `:=`) are desugared entirely at parse time: `#parse_self_prefixed_func_name` (`parser.rb`) synthesizes the equivalent `./`/`../` scope-operator lexeme onto the function name's `Identifier_Expr`, so every downstream scope-operator-aware check (`#track_static_declaration`, the per-instance re-run skip in `#run_type_body_on_instance`) treats it identically with zero interpreter-side special-casing for this form
- `#static_var_declaration_expr?` (`interpreter.rb`) recognizes both the `../x := value` AST shape (scope-operator identifier) and the `Self.x := value` shape (dot-target) as static declarations that must run once, not per-instance — these are structurally different ASTs, so `#run_type_body_on_instance`'s skip-check needs to recognize both explicitly
- `#current_instance` (`interpreter.rb`) is the nearest `Lost::Instance` in the stack (role-based, not positional) — shared by `self`/`./` resolution and `#check_dot_access_permissions!`'s privacy check. This mattered for a real bug: `#interp_func_body` always pushes a fresh per-call `Func` frame on top of the instance, so `stack.last` during any method body is never the instance itself — a privacy check that compared against `stack.last` directly would (and did) wrongly reject `self.some_private_member` read from inside that very instance's own method, until fixed to compare against `#current_instance` instead

## Reopening a Scope

`@push_scope scope` pushes a `Type` or `Instance` directly onto the interpreter's stack, so its members become reachable without a prefix, and any bare declaration made while "inside" lands on the pushed scope itself — this actually mutates the target, unlike the readable/writable scopes described below. `@pop_scope scope` pops back out; it asserts (by identity) that `scope` is exactly what `@push_scope` last pushed, raising a plain `RuntimeError` instead of silently popping the wrong thing.

```lost
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

```lost
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

```lost
Thing { new (; ./member := 123 ) }   # self-declaration via ./ inside a method -- legitimate,
                                     # equivalent to declaring `member,` in the body directly
t := Thing()
t.member = 5                         # fine -- member already exists
t.missing = 5                       # raises Lost::Cannot_Assign_Undeclared_Identifier
```

- `./`/`../` self-declaration (`:=`) is only allowed while the instance is still under construction — the class body's own declarations, or `new(;)` itself (and anything it calls). A later method self-declaring a brand-new member this way also raises `Lost::Cannot_Assign_Undeclared_Identifier`, so an instance's shape can't keep growing after it's built. Detected via `instance.has?('new')` — `#interp_type_call` deletes the `new` declaration the moment construction finishes, so that check is true for exactly the construction window
- Not yet covered: the equivalent restriction for `../` creating a brand-new *static* member from outside the type's original body walk — no "still being defined" signal exists for `Type` the way `has?('new')` does for `Instance`
- A constant-named member (`X.SOME_CONST = ...`) can never be reassigned via `.`, raising `Lost::Cannot_Reassign_Constant`
- All three `.`-write forms — plain `=`, plain `:=`, and destructuring dot-targets (see Destructuring below) — share one implementation, `#assign_dot_member` in `interpreter.rb`. `:=` onto an *existing* member re-infers/overwrites its recorded type (same as re-running `:=` on a plain identifier); `=` checks the new value against any previously recorded type instead
- A `.`-write onto a `nil` receiver (`x.y = z` / `x.y := z` where `x` is `nil`) raises `Lost::Receiver_Is_Nil`, not `Cannot_Assign_Undeclared_Identifier` — see "Nil receiver" under Scope System above

## Class Composition Operators

Lost uses composition operators instead of inheritance. Applied as `Class | Other { body }`:

- `|` **Union** - merge all declarations; left side wins conflicts
- `&` **Intersection** - keep only declarations shared by both sides
- `~` **Difference** - remove right side's declarations from left side
- `^` **Symmetric Difference** - keep only unique declarations (discard shared ones)

Multiple operators can be chained: `Admin | Read_Permissions | Write_Permissions { }`.

Built-in types like `Server` and `Dom` are composed this way:

```lost
Web_App | Server { get:// (; "Hello" ) }
Layout | Dom { render (; Html([Body("Hello")]) ) }
```

(`Table` used to be composed too — `Post | Table { Self.database := ~/db }` — but the ORM moved to plain `Database` instance methods; see Database and ORM below.)

## Type Comparison Operators

Five operators compare the *composed-type sets* of Types and Instances (a type's own name plus every type it has composed via `|`/`&`/`~`/`^`), handled by `#interp_comparison_infix` (`interpreter.rb`, dispatched from `#interp_infix`). All five share the `=X=` shape (equals, symbol, equals) so they're easy to remember and hard to mistake for one another:

- `===` - exact type-set equality
- `=!=` - negation of `===`
- `=>=` - is left a superset of right (left composes with at least everything right does)
- `=<=` - is right a superset of left (mirror of `=>=` with operands reversed: `A =<= B` ≡ `B =>= A`)
- `=/=` - disjoint: the two share no composed types at all

Only `=>=` (superset) carries genuinely new information — `=<=` is `=>=` with swapped operands, and `===` is mutual `=>=` in both directions (`(A =>= B) && (B =>= A)`); `=!=` is just `!(A === B)`. The other three exist purely for readability at the call site, the same reason most languages ship both `<=`/`>=` alongside `==`/`!=` despite one being derivable from the other.

```lost
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

`Any` (`lost/preload.tape`) is a real declared type, but `==`/`!=`/`===`/`=!=` special-case it: any value or type that isn't `nil` counts as equal to `Any`, in either operand position, with no composition required — you don't need `Thing | Any {}` for `Thing` to satisfy it.

```lost
Thing { x := 1 }

String === Any      #=> true
Thing() == Any       #=> true
4 == Any             #=> true
nil == Any           #=> false -- the one exception
```

Implemented once in `#interp_comparison_infix` (`interpreter.rb`), checked up front before the normal composed-type-set/overload-lookup logic — a new `#any_type?` helper identifies the literal `Any` type (by name, not by composed types), and the check covers `==`/`!=`/`===`/`=!=` together so the negations stay consistent with their positive forms.

## Structs

`<...>` attaches runtime-inspectable metadata (a "struct") to a standalone value or a reference to an existing type. Parsed by `parse_struct` in `parser.rb` into `Lost::Struct_Expr`; interpreted by `interp_struct` in `interpreter.rb` into an `Lost::Struct` instance (`src/external/ruby/struct.rb` — no paired `.tape` file; `lost/struct.tape` + `lost/member.tape` are a separate, higher-level `Member`/`Struct` layer built on top of it, loaded by default via `lost/preload.tape`).

Tagging a *Type* declaration/reference itself — as opposed to a standalone struct value — goes through `\` (`Lost::TAG_OPERATOR`, `src/shared/constants.rb`) instead of bare `<...>`, to stay unambiguous from a lone unnamed Struct-valued member (see "Each declared tag is its own type" below) and from ordinary comparisons. `\` has two RHS forms, both handled by `interp_type`/`#interp_tagged_type_declaration`/`#resolve_tag_reference`:

```lost
Abc\<Number> {}              # inline literal declaration — Number becomes part of Abc's tag_declaration
Task_Schema <a: Number, b: String>  # a separately-declared struct value (bare `<...>`, no `\`)
Array\Task_Schema {}         # named reference — reuses an already-declared struct value verbatim
Array\String {}              # named reference to a Type — wrapped as the equivalent single-unnamed-member struct, same as Array\<String>

x := Abc\<Number>             # reference — dup of the existing Abc type, tagged; doesn't mutate the original
x: Abc\<Number>                # same, as a type annotation
thing: <String, Number>        # bare struct, no type name at all — a standalone Lost::Struct value, unrelated to `\`
z := Abc\<4815>                # a reference tagged with an actual value rather than a type
z()                            # constructs Abc, with .tag bound before new(;) runs
Abc\<4815>()                   # same, in one step
Abc\4815                       # bare integer, no `<...>` — shorthand for Abc\<4815> (a "version tag")
Primary_Key\Int               # bare identifier RHS is still a named reference, not this shorthand
Def {}
Def()                          # untagged types are completely unaffected
```

A named reference's RHS must resolve to a real `Lost::Struct` or `Lost::Type` — anything else raises `Lost::Tag_Reference_Must_Be_Type_Or_Struct`. Referencing a name that's a real declared Type but has no matching tagged variant yet doesn't raise — it auto-declares one on the spot (an implicit empty body via `#declare_tagged_type_variant`), so `Array\String` "just works" without requiring `Array\String {}` to have been written first; declaring it for real later reopens/extends this same auto-created variant.

- A member is any expression (`Abc\<1+2+3/123>`, `Abc\<this, that>`), not just a type name — evaluated normally at interpret time, so an identifier like `Number` resolves to the actual `Lost::Type`
- **Bare integer shorthand** (`Abc\4815`, no angle brackets): a "version tag", parsed identically to `Abc\<4815>` — a single unnamed member holding that integer. Handled by `#integer_tag_next?`/`#type_then_integer_tag_next?`/`#integer_tag_struct_expr` (`parser.rb`), in both the primary-expression dispatch and `#parse_identifier_expr`'s trailing-tag handling. Only a bare integer triggers it; `Abc\Name` stays a named reference. Used by `lost/database.tape`'s `Primary_Key\Int` (an `Int`-tagged primary key) and left open for schema-version tagging
- Named members (`Type\<some_string: String, num: Number> {}`) reuse `parse_identifier_expr`'s existing `: Type` annotation parsing for each member — no separate grammar needed. Only two named forms exist: `name: Type` and `name := value` — there's no general `name: value` the way Dictionaries have one. `:` immediately after a bare identifier, followed by anything that isn't a capitalized type name or `<...>` (almost always a lowercase value, mistaken for Dictionary-style `key: value`), raises `Lost::Invalid_Struct_Member_Annotation` at parse time in `#parse_struct` — without that check, `#parse_identifier_expr`'s own `: Type` lookahead just declines to consume the `:` (it can never be a type), leaving it to be reparsed on the next loop iteration as an unrelated `:symbol` prefix literal starting a whole new member, since commas are optional between struct members same as any other list — `<columns: cols>` would otherwise silently become the two members `columns, :cols` instead of erroring anywhere
- A struct is only ever reachable via `.tag` (`.tag.types`, `.tag.some_string` for named members) — never auto-unpacked into `./`
- A bare identifier immediately followed by `,` inside `<...>` (`<String, Number>`) is special-cased in `parse_struct` to parse as a plain identifier rather than the nil-init idiom (`ident,` ⇒ `ident = ident or nil`), which would otherwise misfire on the exact same shape
- Reference forms (`x := Abc\<Number>`) `dup` the matched variant (see below) rather than mutating it in place — `Object#dup` is shallow, so `@declarations`/`@static_declarations` are explicitly re-forked too, otherwise tagging one reference would silently mutate every other reference sharing that variant
- Constructing from a tagged reference binds `.tag` onto the instance *before* `type.expressions` (and therefore `new(;)`) run, so `new`'s own body can read `.tag` — but member values are never forwarded as constructor arguments; whatever `(...)` actually passes still binds to `new`'s own declared params, entirely separately
- A named member's value, supplied positionally at the reference site (`Woof\<'hello', 4815>`, never `Woof\<key: 'hello'>`), gets re-associated with the *matched variant's own* `tag_declaration` names before landing on the instance, so `.tag.key` still resolves correctly

### Each declared tag is its own type

`Abc\<Number> {}` and `Abc\<String> {}` are independent `Lost::Type` objects, not one shared type with two tags bolted on — declaring a tag creates a fresh type seeded from a copy of the *bare* type's own body (if one exists at declaration time), so one tagged variant's `new`/methods can never clobber another's. This is handled by `#interp_tagged_type_declaration` (`interpreter.rb`), a sibling of `#interp_bare_type_declaration` (used for plain, untagged `Type { ... }`, which still reopens/extends one shared object as before). Both funnel into `#declare_tagged_type_variant` (shared with the auto-declare-on-reference fallback, see above) then `#finish_type_declaration` (Lost:: Ruby-class linking, `@types` bookkeeping, running the body) — reopening an existing variant (bare or tagged) only re-runs its *new* expressions, not ones already run on an earlier declaration.

Each variant is kept in a per-scope list (`Scope#tagged_type_variants`, keyed by base name — e.g. every declared tag of `String`) rather than a single mangled-string-keyed member, so `String\<dict: Dictionary> {}` and `String\<other: Dictionary> {}` are two distinct variants instead of colliding on a shared `"String<Dictionary>"` key. Matching is by real structure equality (`Lost::Struct#structure_declaration_equal?`, `struct.rb` — this one Struct-comparison method kept its name; it's used for general struct-shape equality, not just tag matching) — both `names` and resolved `type_names`, positionally — mirroring the language's own `===` operator on Type/Instance (exact set equality, not a string compare).

A reference resolves by inferring a type name for each supplied value and matching that against the declared variants for that base name — but the match isn't exact-name-only: `#member_candidate_type_names` returns every type a value composes (its own name first, then everything it composes), so e.g. a `Div` satisfies a member declared `Dom` even though nothing in `lost/html.tape` is literally named `Dom`. `Lost::Struct#satisfied_by_candidates?` checks a declared variant against those candidates (mirroring the language's own `=>=` superset operator), and `#find_tagged_type_variant` prefers an exact match before falling back to a compositional one. A lone unnamed Struct-valued member spreads at declare time but not at reference time by default (see below) — `#interp_type`'s reference branch retries with spreading applied whenever the unspread shape doesn't find anything, so a reference/composition operand can still reach a variant that was declared with spreading. A reference with no matching declared variant either auto-declares one (base name is a real Type, see above) or raises `Lost::Undeclared_Type_Structure` (base name is something else entirely).

```lost
String\<Dictionary> { to_s (; "I'm a dict-tagged string" ) }
String\<Number>     { to_s (; "I'm a number-tagged string" ) }

String\<{x=1}>().to_s()   # "I'm a dict-tagged string"   -- {x=1} is a Dictionary
String\<5>().to_s()       # "I'm a number-tagged string" -- 5 is a Number
```

### Confirmed example

```lost
String\<dict: Dictionary> {
    new ( str: String = "";
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

- `Lost::Struct < Instance`, not `Scope` — the `enclosing_scope` method-lookup fallback used for `arr.push(...)`-style calls (see `#interp_identifier`) is gated on `is_a?(Lost::Instance)`, and `Struct` needs that same fallback for `lost/struct.tape`'s own declarations (`==`, `include?`) to be reachable at all. Note: `lost/struct.tape`/`lost/member.tape` are the separate, higher-level `Member`/`Struct` layer, loaded by default (`lost/preload.tape`) but still reachable with `Lost.interp(code, load_standard_library: false)` — distinct from this low-level `Lost::Struct` Ruby class, which every struct literal goes through regardless of whether that layer is loaded, or which operator (`<...>` or `\`) built it
- Every `Lost::Struct.new` call site also calls `link_instance_to_type(struct, 'Struct')`, linking it to whichever `Struct` type is currently declared — either the bare Ruby-backed fallback (no standard library loaded), or `lost/struct.tape`'s own `Struct { }` otherwise (see `#build_struct`)
- `.tag` is exposed on `Type`/`Instance` via `declare_tag` (`interpreter.rb`) — only added when a scope actually has a tag, and marked as a static declaration so it's readable straight off a bare `Type`, not just an instance
- `Type` (and therefore `Instance`, which subclasses it) carries two separate accessors, both holding an `Lost::Struct`:
  - `.tag_instance` (Ruby; `.tag` at the Lost level) — what a specific reference or instance was actually tagged with (`Abc\<4815>`). Only ever set on an explicit `Abc\<...>`/`Abc\Name` reference, never on the bare declared type — its mere presence is what distinguishes "explicitly referenced" from "just the declared type" for `===`/`=!=`/etc. and for whether construction binds `.tag` at all
  - `.tag_declaration` — the type's own declared tag (`Abc\<dict: Dictionary = {}> {}`): named/positional members, annotations, and defaults. A tagged reference looks here to re-associate positional call-site values with names and fall back to defaults
  - Both live on `Type`, not `Scope`, because a tagged reference is a `dup` of the type (same Ruby class as the type itself), so a `Type`-vs-`Instance` check can't stand in for the "declared" vs "supplied" distinction — see the comments on `Type#tag_instance`/`Type#tag_declaration` in `scopes.rb`

### Bare Named Structs

`Ident<...>` where `Ident` has nothing declared under it anywhere (no bare `Type`, no tagged variant, no alias to one) isn't an error — it builds a plain `Struct`, same as `<...>` alone, except with `.name` set from the identifier:

```lost
Thing := <String, Number>   # anonymous -- .name is nil; only reachable via the variable Thing
Named <String, Number>      # named -- .name == 'Named'

n := Named<String, Number>
n.name                      # 'Named'
```

**Type lookup always takes priority.** This only kicks in when `Ident` is genuinely undeclared — a name that collides with something real still behaves exactly as it always has:

```lost
Abc\<Number> {}
Task \<a: Number> {}
Task <b: String>      # raises Lost::Undeclared_Type_Structure -- Task IS declared (as a tagged Type), just not with this shape
```

Implemented in `#interp_struct`/`#register_bare_named_struct` (`interpreter.rb`), gated on `expr.name.is_a?(Lost::Lexeme)` (`parse_struct`'s own leading-identifier capture — distinct from `\<...>`'s inline-literal form, which copies its name onto `.tag.name` as a plain String instead and so never re-triggers this path). Conflict detection checks both `find_in_stack(name)` (a bare Type or a local alias) and `tagged_variants_for(name)` (any tagged variant under that name, matching or not) — a tagged Type declaration never registers under the plain identifier namespace, so `find_in_stack` alone can't see it; either check being non-empty means something real is declared under that name, so the original error still applies.

## Enums (not finalized — don't rely on yet)

`TYPE_IDENTIFIER [ ... ]` declares an `Lost::Enum` (`Lost::Enum_Expr` in the parser, `#parse_enum_expr`; `#interp_enum`/`#build_enum`/`#build_enum_member` in `interpreter.rb`; backing Lost body in `lost/enum.tape`, Ruby class in `src/external/ruby/enum.rb`). Members can be bare (`TODO`), bare with a trailing comma (`BUG,`), type-annotated only (`DONE: Priority`), type-annotated with a value (`CANCELLED: Priority = 99`), self-declared with a value (`ARCHIVED := 'archived'`), or a nested enum (`Nested [ A, B ]`, reachable only as `Outer.Nested`). A bare/annotated-only member's value is a Symbol matching its own name. The enum exposes `.type`, `.keys`/`.values`/`.types` (parallel Arrays), and `.count`.

**Syntactically present, but the type system isn't enforced yet**: each member's own `: Type` annotation is stored but never checked against anything — `Task_Type [ BUG: String = 'oops' ]` declares and constructs without error. The older forced-type spelling (`TYPE_IDENT :: Type { ... }`) doesn't exist anymore — `#parse_enum_expr` no longer parses a forced type at all, so `.type` is currently always `nil`. See the todos.md entry for finalizing this. Don't build real functionality on top of Enum type annotations until that's resolved.

## Destructuring

`(a, b) := <tuple-or-struct-valued expr>` extracts a Tuple's or Struct's values positionally into fresh locals or existing members:

```lost
(a, b) := (1, 2)              # Tuple source
(a, b) := <1, 2>              # Struct source
(x: Number, y) := (1, 2)      # per-target type check against the extracted value
(thing.member, local) := <Number, Number>(1, 1)  # existing-member target
```

- A plain-identifier target always declares fresh on the current scope, same shadowing behavior as any other `:=` — even if that name is already declared elsewhere
- Extracting fewer values than the source has is fine (extras discarded); asking for *more targets than the source has values* raises `Lost::Destructuring_Arity_Mismatch`
- A target can also be an existing member (`thing.member`) instead of a fresh local — this reassigns rather than declares, going through the same `#assign_dot_member` path as plain `thing.member = value` (see Member Creation Is Strict above): the member must already exist, can't be a constant, and (if it has a previously recorded type) the extracted value must match it
- Only `Lost::Tuple`/`Lost::Struct` sources are supported (`Lost::Invalid_Destructuring_Source` otherwise); a target that's neither a plain identifier nor an existing-member dot-expression raises `Lost::Invalid_Destructuring_Target`
- Implementation: `#interp_destructuring_declaration` in `interpreter.rb`, dispatched from `#interp_infix_declaration` when `expr.left` is a `()`-grouped `Circumfix_Expr`
- Not implemented: the bare (no-parens) form `a, b := ...` — needs lookahead past the whole comma-run to distinguish it from N independent nil-init declarations, deferred as not urgent

## Percent Literals

`%kind(...)` turns a space-separated list of bare items into a real `Array` of String or Symbol literals, without quoting each one individually. Parsed by `#parse_percent_literal_expr` (`parser.rb`) into `Lost::Percent_Literal_Expr`; interpreted by `#interp_percent_literal` (`interpreter.rb`).

```lost
%string(boo Hoo COOL)      # [boo, Hoo, COOL] — preserves each item's own casing
%symbol(BOO hoo Cool)      # [:BOO, :hoo, :Cool]

%str(Boo hOO COOL)         # [boo, hoo, cool] — forces lowercase
%Str(boo HOO cOOl)         # [Boo, Hoo, Cool] — forces Capitalcase
%STR(boo Hoo cool)         # [BOO, HOO, COOL] — forces UPPERCASE
# %sym/%Sym/%SYM do the same three, for symbols

cool := 2342
%string(481516 `cool`)     # [481516, 2342] — a backtick item (see Statement Expressions below) is interpolated immediately, then folded through the same casing treatment as everything else
```

- Eight kinds total: `string`/`str`/`Str`/`STR` (String), `symbol`/`sym`/`Sym`/`SYM` (Symbol) — see `PERCENT_LITERALS` in `constants.rb`
- Items can be identifiers, numbers, operators, or `` `expr` `` (Statement) literals; anything else (a string literal, `[1, 2]`, ...) raises `Lost::Invalid_Percent_Literal_Expression`
- **Parsing**: items are parsed one bare token at a time (`curr? :operator`/`:number`/identifier-kind dispatch inside `#parse_percent_literal_expr`), never via the general `#parse_expression` — a symbolic operator item like `+`/`-` is also a valid PREFIX operator, and `#parse_expression` would happily reparse it as a prefix/infix expression that swallows the *next* item as its operand (`%str(+ - ^)` used to collapse into one nested `Prefix_Expr` instead of three separate items); a run like `^^^ + - * /` would similarly get glommed into one compound infix expression by ordinary expression parsing, since nothing else marks item boundaries besides whitespace
- The one remaining `else -> #parse_expression` branch exists purely so an *invalid* item still consumes at least one token — without it, the parser looped forever re-checking the same un-consumed token instead of raising `Invalid_Percent_Literal_Expression`

## Statement Expressions

`` `expr` `` wraps any expression without running it — an `Lost::Statement`, callable later with `()`. Parsed by `#parse_statement_expr` (`parser.rb`) into `Lost::Statement_Expr`; interpreted by `#interp_statement` (`interpreter.rb`) into an `Lost::Statement` instance (`src/external/ruby/statement.rb` + `lost/statement.tape`).

```lost
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

**Scope: captured by default, opt into the caller's.** A Statement remembers the single scope it was on top of the stack when *built* (`captured_scope`, mirroring how `Lost::Func#enclosing_scope` already gives ordinary functions real closures) — calling it later, from anywhere, resolves free identifiers as if it were still running where it was written, not wherever `()` happens to be called from.

```lost
Slacker {
	count := 0
	statement: Statement

	new ( statement; ./statement = statement )
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

- `.use_caller_scope = true` switches a Statement from captured (predictable, closure-like) to dynamic (resolves fresh at every call site) — see `learn/advanced_statements.tape`
- `.memoize = true` caches the first `()` result and returns it on every call after that, instead of re-running — `Memoized_Statement`/`Memoizer` no longer exist as separate types, this replaced them
- `Statement(other)` adopts `other`'s wrapped expression, `captured_scope`, and settings rather than re-capturing "wherever this `Statement(...)` call happens to be written" — `Statement(x+1)` behaves exactly like writing `` `x+1` `` directly (`Lost::Statement#proxy_from`, called from `lost/statement.tape`'s `new(;)`)

**Two construction paths, and why it matters.** Every Ruby-backed Lost type (`Lost::String`, `Lost::Array`, `Lost::Statement`, ...) can be built two different ways, and Statement's `captured_scope` makes the distinction concrete:

1. A backtick literal (`` `expr` ``) — `#interp_statement` builds the Ruby object directly and is the *only* place that can set `captured_scope`, since it's interpreter-side code with a live `stack` to read from; Ruby's `#initialize` has no reference to the running `Interpreter` at all.
2. An explicit `Statement(...)` call — goes through the normal Type-construction path (`#interp_type_call` -> `#build_instance_of_type`), which calls `Lost::Statement.new` with no meaningful constructor argument. Real argument binding happens afterward, separately, once `new(;)`'s own body (`lost/statement.tape`) runs. Ruby's `#initialize` only ever needs to set harmless defaults it can't get wrong.

`use_caller_scope`/`memoize`/`_memoized`/`_memoized_value` are declared as ordinary Lost members in `lost/statement.tape` (not Ruby `attr_accessor`s) so plain dot-assignment (`s.memoize = true`) works with no extra plumbing; `#invoke_statement` reads/writes them from Ruby via `Scope#[]`/`#[]=`. `captured_scope` couldn't take that route — it holds a live Ruby `Scope` object, not an Lost-representable value — so it stays a Ruby `attr_accessor` instead.

A bare backtick literal builds the Ruby object directly and skips the normal Type-construction path entirely, so `#interp_statement` has to *also* run the type's own Lost-level body on the instance (`#run_type_body_on_instance`) — otherwise `use_caller_scope`/`memoize`/etc. would only ever exist on instances built the `Statement(...)` way, and `s.memoize = true` on a bare `` `expr` `` would raise `Cannot_Assign_Undeclared_Identifier`.

**Where scope-aware invocation is (and isn't) enforced.** `#invoke_statement` is the single place `use_caller_scope`/`memoize` are enforced, called from `#interp_call`'s `Lost::Statement` branch (an already-*constructed* instance being called via `()`). It doesn't apply to:
- A bare `` `expr`() `` written and called in the same place (`#interp_call`'s earlier `Lost::Statement_Expr` check) — always immediate, in whatever scope it's written in
- A `` `expr` `` item inside a percent literal (`#interp_percent_literal`) or array literal (`#interp_circumfix`) — neither ever builds a real `Lost::Statement`, so there's no instance to hold these settings on

Pushing the captured scope back on top (rather than swapping the whole stack) is deliberate: identifier lookup searches innermost-first, so one scope pushed via `#push_then_pop` wins the search over the caller's own frames underneath, without needing to hide/replace them — the same trick `#interp_func_body` already uses for ordinary `Func` closures.

## Identifier Naming Conventions

The language enforces naming conventions through the helper functions:

- **UPPERCASE** (constant_identifier?) - Constants
- **Capitalized** (type_identifier?) - Classes/types
- **lowercase** (member_identifier?) - Variables and functions

## Function Conventions

Lowercase identifier, followed by a `()` grouped block which contains `;` which separates the params and body.

```lost
<identifier> ( <args>; <body> )
```

`(...)` is also grouping, a call's argument list, and a Tuple, so a bare `(` alone doesn't say which one is coming. `func_declaration_follows?` (`parser.rb`) disambiguates by depth-checking the upcoming tokens for a bare `;` at nesting level 1 (the declaration's own params/body separator, not a nested one) before the matching `)` closes: `foo((a; a+1), 5)` is an ordinary call passing an anonymous func as its first argument — the inner func's `;` sits at depth 2, one level past `foo`'s own opening paren, so it doesn't make `foo(...)` itself look like a declaration.

### Spread lambda sugar

A call whose *single* argument is an anonymous function may drop that argument's own parens:

```lost
xs.map(x; x * 2)        # sugar for xs.map((x; x * 2))
xs.filter(n; n > 0)
xs.find(x; x == target)
xs.map(x; x * 2).filter(n; n > 2)   # chains
```

Only when the receiver is a **member access, call result, or subscript** — `xs.map(...)`, `f().g(...)`, `a[0](...)`. A bare identifier stays a declaration: `double(n; n * 2)` still *declares* `double`. And only when the tokens before the `;` are genuinely param-list-shaped (`anon_func_param_list_follows?`, `parser.rb`) — `xs.reduce(0, a; a)` (a value, then a name) does not spread. Handled in `#complete_expression` plus a `member_rhs` flag on `#begin_expression`/`#parse_expression` that stops the `.`-RHS `member(x; y)` from being read as a declaration.

## Labeled Function Arguments

Swift/ObjC-style: a param declared with two identifiers in a row (`label name`) can be called with `label: value` at the call site.

```lost
send_greeting ( to person; person )
send_greeting(to: 42)      # matches the label declared at that position
send_greeting(42)          # labels are opt-in -- a bare positional call still works
```

- Matching is purely positional — a labeled argument's label must match whatever's declared at that same param index; labels are never used to reorder arguments
- A supplied label that doesn't match the declared one at that position (including "labeled when none was declared") raises `Lost::Argument_Label_Mismatch`
- Two params can share the same label (`new ( at x, at y; ... )` then `Point(at: 3, at: 4)`) — matching Swift, labels aren't required to be unique
- Implementation: `label: value` parses as an ordinary `:` `Infix_Expr` (same production named struct members use) — `#interp_func_body` unwraps it via `#classify_argument` before interpreting, rather than letting `#interpret` try to resolve the label as an identifier

## Named Function Arguments

`name := value` at a call site binds by the callee's declared param *name*, order-independent — a separate mechanism from labels (which check a *position*'s declared label, never reorder). Works for any call, including construction (`new(;)` params).

```lost
sub ( a, b; a - b )
sub(a := 1, b := 2)  #=> -1
sub(b := 2, a := 1)  #=> -1, same result -- order doesn't matter
sub(1, b := 2)       #=> -1, positional then named is fine
```

- **Ordering rule**: positional arguments (bare or labeled) must come before all named arguments in a call — once you switch to naming, every argument after that has to be named too. Reverting to positional after a named argument raises `Lost::Positional_Argument_After_Named`
- The same name used twice in one call raises `Lost::Duplicate_Named_Argument`
- A param supplied both positionally *and* by name (e.g. `add(1, a := 2)` where `a` is the first param) raises `Lost::Argument_Given_By_Name_And_Position`
- A named argument whose name doesn't match any declared param raises `Lost::Unknown_Named_Argument` — checked up front, before param binding, so a typo'd name is reported directly rather than surfacing as a confusing `Lost::Missing_Argument` on some unrelated param the typo incidentally starved of a value
- A named argument bypasses label-checking entirely for that param — it's matched by declared name, not position, so there's no positional label to compare against
- Implementation: `name := value` parses as an ordinary `:=` `Infix_Expr` (same production a struct member's bare default uses) — `#classify_argument` distinguishes it from a labeled (`:`) or plain positional argument; `#interp_func_body` builds a `named_args` hash alongside the existing positional `arg_values` array, consulting it first when binding each declared param

## Struct-Typed Function Parameters

A function param can be typed with an inline struct (`: <...>`) instead of a plain type name — structural, not nominal: any argument that has each named member, with a compatible type, satisfies it, regardless of what type the argument itself is actually named.

```lost
f ( right: <name: String, type: Any, value: Any>; right.name )

m := Member('x', String, 4)
f(m)          #=> 'x' -- Member has all three, so it satisfies the struct annotation without being named "Member" in the annotation itself

f(nil)        # raises Lost::Type_Contract_Violation -- nil has none of the required members
```

- `Any` is a wildcard within a struct annotation's member types — `type: Any` matches regardless of the member's actual type (including a declared-but-nil member)
- Checked at every call — unlike a plain `: Type` param annotation (never runtime-enforced except by the static checker on literal args), a struct annotation is a real, always-checked contract
- Implementation: `Param_Expr` gained a `type_struct` field (parser.rb, mirroring the existing `Identifier_Expr#type_struct` used for `x: <String, Number>`-style variable annotations); `#check_struct_type_contract` (interpreter.rb) runs on every bound argument that has one, reusing `#member_candidate_type_names` (the same compositional matching `Ident<...>` structured-type references already use) to check each named member
- Found and fixed a real, previously-undiscovered lexer bug while building this: `>` immediately followed by `,`/`;` with no space (`<String>;`) lexed as one bogus combined operator token instead of two, silently breaking any struct annotation directly followed by either character

## Class Conventions

A capitalized identifier followed by a `{}` grouped block

```lost
<Identifier> { <body> }
```

The `new` method is the constructor and is called when instantiating a class:

```lost
Point {
    x,
    y,

    new ( x, y;
        ./x = x
        ./y = y
    )
}

p := Point(3, 4)  # Calls new
```

## Readable and Writable Scopes

Every scope keeps two extra fallback places identifier lookup checks, after its own declarations: a **readable** scope set (read-only) and a **writable** scope set (also a fallback for writes). Neither overrides anything already reachable on the scope itself.

Both are held **weakly** — adding an instance doesn't keep it alive. Once every other reference to it is gone, it becomes eligible for GC on its own, even though it's technically still "in" the readable/writable set, and it silently stops resolving through it. This matters most for long-lived scopes (Global, or anything a running `@start_server` keeps reusing across requests) — a `Set` of strong references would otherwise pin whatever gets added for the life of the process unless it's explicitly removed.

### Auto-unpack in Function Parameters

`@readable`/`@writable` are shorthand for `@add_readable_scope`/`@add_writable_scope`, meant specifically for function param lists, where the longer names get noisy fast.

```lost
add ( @readable vec;
	x + y   # Access vec.x and vec.y directly
)

v := Vector(3, 4)
add(v)   # Returns 7
```

`@writable` unpacks the same way, but a plain write inside the body to a name the argument already has lands on that member directly instead of declaring a fresh local:

```lost
double ( @writable vec;
	x *= 2   # writes straight through to vec.x
	y *= 2
	vec
)
```

### Manual Scope Control

`@add_readable_scope instance` / `@add_writable_scope instance` (medium alias: `@add_readable`/`@add_writable`) do the same unpacking by hand, in any scope, not just a function's param list. `@remove_readable_scope`/`@remove_writable_scope` (medium alias: `@remove_readable`/`@remove_writable`) take an instance back out.

```lost
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
- Only works with `Type`/`Instance` values for the param shorthand (silently skipped for anything else); the directive forms run the target through `#maybe_instance` first (so a raw primitive like `4` becomes a real `Lost::Number`, which counts as a `Scope`) and then raise `Lost::Invalid_Scope_Directive_Argument` if it still isn't one. Because `#maybe_instance` also turns Lost `nil`/`false` into the real, Ruby-truthy `Lost::Nil.shared`/`Lost::Bool::FALSE` singletons, the `if target` truthiness guard those directives use to detect "nothing was passed" never actually fires for `nil`/`false` — they're silently accepted rather than rejected (`test_add_readable_scope_with_nil_argument_is_silently_accepted`/`..._with_false_argument_is_silently_accepted`, `scopes_test.rb`) — harmless in practice, since ordinary dot-write rules already prevent mutating those singletons regardless of what scope they end up sitting in
- Renamed and split from the older combined `@ += instance`/`@ -= instance`/`@param` "sibling scope" mechanism, which had no readable/writable distinction and used a strong-reference `Set`
- `lost/preload.tape` is loaded into its own `Standard_Library` scope (`Interpreter#run`), added to Global's readable scope rather than merged into Global's own declarations — so `String`/`Array`/etc. are reachable but not directly declared on Global (`global.declarations.key?('Array')` is `false`; `global.has?('Array')` is `true`, via the fallback). `global` is pushed onto `stack` *before* this load (rather than being the load's own target) so `~/` still resolves to real Global throughout the stdlib's own loading. Reassigning a built-in (`Array = Mine`) can never mutate the real one — `Scope#[]=` only redirects through `writable_scopes`, never `readable_scopes` — it just creates a new entry directly in Global's own declarations, shadowing the readable fallback for the rest of that `Global`'s lifetime. If `Mine` composes the original (`Mine | Array {}`), everything keeps working afterward, since proxy-method dispatch (`.length()` etc.) finds its owning type by looking up the type name in the stack, and `Mine` has those declarations composed in — and reassigning this way is a real, working way to extend every array literal in the rest of a program, not just a safe no-op

## Operator Overloading

Custom operators are declared with `@operator`, a fixity directive, a precedence number, and a function body. Parsed specially in `parser.rb` (`scan_and_register_operator_overloads_before_parsing` pre-scans and registers precedence before the main parse, since fixity/precedence affects how the rest of the file parses):

```lost
@operator -> @infix 300 ( left, right;
    right(left)
)

double ( n; n * 2 )
5 -> double  # => 10
```

- Fixities: `@infix`, `@prefix`, `@postfix`, and `@circumfix` (only `infix`/`prefix`/`postfix` are documented in `readme.md`; `circumfix` is accepted by the parser but undocumented there)
- The operator symbol can be any symbol sequence or identifier (`->`, `!!`, `pm`, `$`)
- Overloads are stored as regular functions in the declaring scope — they don't leak outside it
- Represented internally as `Lost::Operator_Overload_Expr` (fixity, precedence, operator lexeme, `Func_Expr` body)
- **Precedence**: a type's own overload for an operator always wins over a same-named one declared anywhere else. Dispatch (`#find_operator_overload` in `interpreter.rb`) checks the left operand's own declarations first, then its `enclosing_scope` (for shorthand-constructed instances that never got the type's declarations copied onto themselves — see `#interp_type_call`), and only falls back to a lexically/dynamically-scoped global operator (found by searching `stack.reverse_each`, deliberately excluding `Lost::Type`/`Lost::Instance` scopes) if the operand doesn't declare its own
- That stack search is scope-based, not global-only — an operator declared inside a function body shadows a same-named one declared outside it, for the duration of that call, with no leakage back out once the call returns
- `Lost::Type`/`Lost::Instance` scopes are excluded from that stack search specifically to prevent infinite recursion: a Type merely being on the call stack (because one of its methods is currently executing) says nothing about whether the *current* operands belong to it — without the exclusion, an overload whose body reuses its own operator symbol on unrelated operands (even plain `1 == 1`) would recurse into itself forever, since the declaring Type never leaves the stack while its own body runs

## Ranges

Four range operators, all built on the same `...`/`..<`/`>..`/`>.<` family (`RANGE_OPERATORS` in `constants.rb`, handled by `#interp_range_infix` in `interpreter.rb`, dispatched from `#interp_infix`):

```lost
1...5  # inclusive:         1, 2, 3, 4, 5
1..<5  # exclusive end:     1, 2, 3, 4
1>..5  # exclusive start:      2, 3, 4, 5
1>.<5  # exclusive both:       2, 3, 4
```

`..<` trims the end, `>..`/`>.<` bump the start by 1 — implemented as `Lost::Range.new(start, finish, exclude_end: bool)` with `start`/`start + 1` depending on operator.

## Built-in Types and Intrinsic Methods

Lost's built-in types (String, Array, Dictionary, Number) have ruby methods that delegate to Ruby's native implementations. These methods are declared using a `proxy_` prefix (see src/shared/ruby_proxies.rb)

### Intrinsic Method Implementation Pattern

**In Lost** (`.tape` files):

```lost
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

**Methods implemented in Lost** (not as Ruby proxies):
Some methods like `find`, `any?`, and `all?` are implemented directly in Lost using for loops rather than Ruby proxies, as they need to execute Lost functions.

### String

Properties: `length`, `ord`

Methods: `upcase()`, `downcase()`, `split(delimiter)`, `slice(substr)`, `trim()`, `trim_left()`, `trim_right()`, `chars()`, `index(substr)`, `to_i()`, `to_f()`, `empty?()`, `include?(substr)`, `reverse()`, `replace(new)`, `start_with?(prefix)`, `end_with?(suffix)`, `gsub(pattern, replacement)`

Defined in: `lost/string.tape`, implemented in `scopes.rb` as `Lost::String`

### Array

Properties: `values`

Methods: `push(item)`, `pop()`, `shift()`, `unshift(item)`, `length()`, `first(count)`, `last(count)`, `slice(from, to)`, `reverse()`, `join(separator)`, `map(func)`, `filter(func)`, `reduce(func, init)`, `concat(other)`,`flatten()`, `sort()`, `uniq()`, `include?(item)`, `empty?()`, `find(func)` *(Lost)*, `any?(func)` *(Lost)*, `all?(func)`*(Lost)*, `each(func)`

Defined in: `lost/array.tape`, implemented in `scopes.rb` as `Lost::Array`

**Note:** Methods marked *(Lost)* are implemented in Lost using for loops, not as Ruby proxies.

### Dictionary

Methods: `keys()`, `values()`, `has_key?(key)`, `delete(key)`, `merge(other)`, `count()`, `empty?()`, `clear()`, `fetch(key, default)`

```lost
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
- Defined in: `lost/dictionary.tape`, implemented in `scopes.rb` as `Lost::Dictionary`

### Number

Properties: `numerator`, `denominator`, `type`

Methods: `to_s()`, `abs()`, `floor()`, `ceil()`, `round()`, `sqrt()`, `even?()`, `odd?()`, `to_i()`, `to_f()`, `clamp(min, max)`

Defined in: `lost/number.tape`, implemented in `scopes.rb` as `Lost::Number`

### Date / Time / Date_Time

Three temporal wrappers, always available (loaded by `lost/preload.tape` — no `@load` needed). Each wraps a Ruby stdlib value: `Date` → `::Date`, `Time` → `::Time`, `Date_Time` → `::DateTime`.

```lost
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
- Backing bodies: `lost/date.tape`, `lost/time.tape`, `lost/date_time.tape`. Ruby classes and the shared `Temporal` mixin: `src/external/ruby/temporal.rb`. Tests: `test/temporal_test.rb`.
- These are the types a `Date` / `Time` / `Date_Time` table column maps to — a value read back from such a column comes out as the matching wrapper, linked to its global type via `Table#linked_temporal` (`table.rb`).

### File_System (File I/O)

Static methods for reading and writing files:

```lost
content := File_System.read('./path/to/file.txt')  # Read file contents as string
File_System.write_string_to_file('./path/to/file.txt', 'Hello, World!')  # Write string to file
```

Defined in: `lost/file_system.tape`, implemented in `scopes.rb` as `Lost::File_System`

## Loop Control Flow

### For Loops

```lost
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

```lost
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

```lost
`Map chunks of 2
sums := for [1, 2, 3, 4, 5, 6] map by 2
    it.0 + it.1
end  # => [3, 7, 11]
```

**With stop (partial results):**

```lost
`Stop returns partial results for map/select/reject
partial := for [1, 2, 3, 4, 5] map
    stop if it == 4
    it * 2
end  # => [2, 4, 6]
```

### Loop Control Keywords

```lost
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

```lost
while x < 4
    x += 1
end

until x >= 23
    x += 2
end
```

Both support `elwhile`/`else` chaining (like `elif` for loops):

```lost
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

```lost
x := unless condition
    4
else
    -4
end
```

**Truthiness** (`#truthy?` in `interpreter.rb`) is uniform across all four conditional forms (`if`/`unless`/`while`/`until`) and just delegates to Ruby's own rules (`!!value`): only `nil`/`false` are falsy, everything else — `0`/`0.0` included — is truthy.

### Return Statement

The `return` keyword exits a function and returns a value. It properly propagates even when used inside loops:

```lost
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

- `return value` creates an `Lost::Return` object wrapping the value
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

Lost includes built-in database support with an ActiveRecord-style ORM using Sequel and SQLite. `lost/database.tape` (which itself `@load`s `lost/table.tape`) gives you both `Database`/`Sqlite` and `Table`.

### Connecting

`@connect` opens the connection and **returns the `Database`** — so the idiom is one line:

```lost
@load 'lost/database.tape'

db := @connect Sqlite('./data/myapp.db')   # a real path
db := @connect Sqlite.memory()             # ':memory:', nothing hits disk
db := @connect Sqlite.local('demo')        # <@root>/temp/demo.db (adds `.db` if missing)
```

- `Sqlite(url)` builds an unconnected `Database` (`adapter`/`url` set, `connection` still nil). `@connect` interprets its argument, links it to the `Database` type, and lazily builds + caches the Sequel connection on it (`#interp_directive`'s `'connect'` case → `#interp_database`, `interpreter.rb`). A second `@connect` on the same `Database` returns the same cached `Sequel::SQLite::Database`.
- `@connect db` (statement form, no assignment) still works — it returns the same value, you just ignore it.
- Connecting with no `url` raises `Lost::Url_Not_Set_For_Database_Instance`.

### Schemas

A schema is a **named Struct** — one member per column, the member's type name deciding the column type. The struct's `.name` is what the table name is derived from (`User` → `users`, `Log_Schema` → `log_schemas`, via `Sequel::Inflections` pluralize/underscore), so an **anonymous** schema struct raises `Lost.assert` (a `RuntimeError`) in every method that takes one.

```lost
User <
    id: Primary_Key
    name: String
    joined_at: Date_Time
>
```

Column type names, matched by string in `Database#proxy_create_table` (`database.rb`):

| schema type | column |
|---|---|
| `Primary_Key` | auto-increment primary key (declared `Primary_Key\Int` in `lost/database.tape`) |
| `String`, `Text` | text |
| `Int` | integer |
| `Number` | numeric |
| `Bool` | boolean (SQLite stores 0/1/NULL — see round-trip note below) |
| `Date`, `Time`, `Date_Time` | the matching Ruby date/time column |
| `Flt`/`Float`, `Decimal`, `Blob`/`Binary` | mapped, but no Lost type backs these yet |
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

The `Table` you get back carries `.columns` (the schema struct), `.database`, and `.table_name` (a plain `String`, e.g. `'users'`). Its CRUD methods are **instance methods on that object** — there is no `User | Table {}` model composition or `Self.database` static pattern anymore (removed deliberately, so one schema can be bound to more than one database). `lost/table.tape` has no `Self.` members.

```lost
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

- **A record is an `Lost::Struct`**, named after the schema, built by `Table#row_to_struct` → `Interpreter#build_struct` (`table.rb`). Read members by name (`record.name`, `record.id`); `.to_h` gives the whole row.
- `find`/`update`/`delete` take a primary key (`pk`). `find_by`/`where`/`create`/`update` take a Struct of `name := value` members.
- A filter/attrs Struct naming a column the schema doesn't have raises `Lost::Table_Invalid_Filter_Column` (checked proactively in `#check_filter_columns!`, before the query runs).
- **`Bool` round-trip**: SQLite has no boolean type, so a `Bool` column stores 0/1 (or NULL when unset). `#coerce_column_value` maps it back to a real `true`/`false` so `if record.done` and `record.done == true` both behave — before this fix an unset value read as the truthy `Bool` *type* object.
- **`Date`/`Time`/`Date_Time` round-trip**: read back as the matching wrapper instance (`record.joined_at.year`, comparisons, etc.), GC-safely linked to its global type via `#linked_temporal`.

### Implementation

- Sequel + SQLite. `Database`/`Table` proxy methods: `src/external/ruby/database.rb`, `src/external/ruby/table.rb`. Tests: `test/database_test.rb`, plus the temporal-column round-trip in `test/temporal_test.rb`.
- `Database#find_table` is a `proxy_overload` — `Lost::Struct` → `#find_table_struct`, `::String` → `#find_table_named`.
- `#table_name_for` is the single place a table name is derived from a schema struct; every struct-accepting method funnels through it, so the "must be named" assert covers all of them at once.

## Web Server Features

Lost has built-in web server support:

- **Server class composition** - Create servers by composing with the built-in `Server` class using `|` operator
- **Route syntax** - Routes defined as `method://path` (e.g., `get://`, `post://users/:id`)
- **URL parameters** - Use `:param` syntax in routes, accessed via route function parameters
- **Route precedence** - `#match_route` (`interpreter.rb`) collects every route whose segment count and literal/`:param` segments match, then picks the one with the *fewest* `:param` segments — so a fully literal route always beats a `:param` route for the same path, regardless of declaration order (`get://favicon.ico` wins over an app's own `get://:id`). `#min_by` keeps the first on a tie, matching the old `.find` order. This is what makes `lost/server.tape`'s built-in `get://favicon.ico` / `get://apple-touch-icon.png` / `get://apple-touch-icon-precomposed.png` routes (all `ok200`) actually shield an app from the browser's automatic icon probes hitting `get://:id`
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

```lost
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

Lost supports HTML rendering via the built-in `Dom` type (load `lost/html.tape`). Any class composing with `Dom` that defines a `render` method will auto-render to HTML when returned from a server route.

```lost
@load 'lost/html.tape'

Layout | Dom {
    title,

    new ( title = 'My Page';
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

```lost
Styled_Div | Dom {
    html_element := 'p'
    html_class := 'my_class'
    html_id := 'my_id'
    css_background_color := 'black'
    css_color := 'white'
}
# => <p class='my_class' id='my_id' style='background-color:black;color:white;'></p>
```

**Predefined elements** in `lost/html.tape`: `Html`, `Head`, `Body`, `Title`, `H1`–`H6`, `P`, `Span`, `A`, `Div`, `Form`, `Input`, `Button`, `Ul`, `Ol`, `Li`, `Html_Table` (not `Table` — that name is the ORM type), `Tr`, `Td`, `Th`, and more.

- Routes returning a `Dom` instance automatically render to HTML string
- HTML rendering only works when `render(;)` is called by a Server instance
- `html_element` sets the tag name (default `'div'`)
- Fence blocks starting with `html\n` are treated as raw HTML tokens by the lexer

## File Loading

The `@load` directive allows importing Lost files:

- Interpreter caches parsed expressions in `@cached_expressions_by_filepath` to prevent duplicate parsing
- Files are loaded into a specified scope via `Interpreter#load_file_into_scope`
- Expressions are cached keyed by resolved filepath
- Separately, running (not just parsing) a file into a given scope is deduped per-scope: `Scope#loaded_filepaths` (a `Hash`, keyed by resolved filepath) records the result the first time a file is actually loaded into that scope. A later `@load` of the same file into the *same* scope returns that stored result directly instead of re-running the file — without this, a repeated bare `@load` used to re-run the file's whole body again and could return `nil` instead of the original result. Loading the same file into a *different* scope (e.g. two separate `x := @load 'file'` namespacing calls) still runs it again, since the cache lives on the target scope, not globally — this is what makes namespace isolation actually isolated
- Comment lexemes are filtered out before parsing, matching `#run`'s top-level behavior — otherwise a trailing comment at the end of a loaded file's function/program body would silently become that body's return value
- The target scope depends on the call form:
  - Bare `@load 'file'` merges the file's top-level declarations directly into the current scope (`stack.last`) — `lost/preload.tape` uses this same mechanism, but `Interpreter#run`'s bootstrap passes a fresh `Standard_Library` scope as the target (not `global` itself), so e.g. `String` lands there, not as a direct Global declaration — see Readable and Writable Scopes below
  - `some_lib := @load 'file'` instead creates a fresh `Lost::Scope` named after the left-hand identifier, loads the file into *that*, and assigns it — giving real namespace isolation, e.g. `some_lib.square(5)`
