### A tagged type can require a Statement

`\<name: Statement>` (see learn/statement_expressions.tape and learn/tagged_types.tape) makes a tagged type's shape say "this slot holds a deferred, callable expression," not a plain value.
###
Row\<id: Statement> {}

r := Row\<`1+2`>()
@assert r.tag.id() == 3, 'a tagged Statement member should be callable'


### Not idempotent — every call re-runs the wrapped expression

This is the real-world angle for a tagged `Statement` member: a column default computed at insert-time instead of baked in once when the schema is declared, e.g. `created_at: Statement` around a clock call (Lost has no clock yet, so a counter stands in below). But it cuts both ways — two tagged references sharing *the same* Statement value both advance the same underlying call, not independent ones.
###
seq      := 0
next_seq := `seq += 1`

row_a := Row\<next_seq>()
row_b := Row\<next_seq>()

@assert row_a.tag.id() == 1, 'the first call should advance the shared counter to 1'
@assert row_b.tag.id() == 2, 'a second reference sharing the same Statement should advance the same counter'
@assert row_a.tag.id() == 3, 'rereading row_a should still advance it, not return a cached value'


### Captured by default

A Statement remembers the scope it was *built* in, not wherever it later happens to get called from — the same predictable behavior a normal closure gives you. Calling it later, from anywhere, still resolves `some_local_var` against the scope where the backtick literal itself was written.
###
some_local_var := 0
expensive       := `some_local_var += 1`

@assert expensive() == 1, 'the first call should resolve some_local_var against its captured scope'


### Caching a Statement's result with .memoize

Set `.memoize = true` and the first `()` call's result is cached and returned by every call after that, instead of re-running the expression.
###
expensive.memoize = true

@assert expensive() == 2, 'the first call after memoize is set should still run for real'
@assert expensive() == 2, 'every call after that should return the cached result instead of running again'
@assert some_local_var == 2, 'the memoized calls after the first should not have mutated some_local_var again'


### Opting into the caller's scope

`.use_caller_scope = true` switches a Statement from "predictable" (captured at build time) to "scope-agnostic" (resolved fresh at every call site, wherever that turns out to be) -- useful when the whole point is letting *whoever* ends up holding the Statement supply its own meaning for a name, rather than always seeing your one, fixed variable.

The scope-agnostic behavior only becomes visible when there's real ambiguity to resolve -- a name declared in more than one reachable scope. `Slacker` gives its `statement` member somewhere to actually run: `count` exists both as Slacker's own instance member *and* as an unrelated outer local, so which one wins depends entirely on the setting below.
###
Slacker {
	count := 0
	statement: Statement

	new ( statement;
		self.statement = statement
	)

	live_count (-> Number;
		statement()
	)
}

demo_predictable := (;
	count       := 2
	captured    := `count += 4`
	predictable := Slacker(captured)

	@assert predictable.live_count() == 6, 'a captured Statement should resolve the outer count it closed over'
	@assert count == 6, "the outer count should be mutated since the Statement resolved it, not Slacker's own"
)

demo_caller_scope := (;
	count          := 2
	dynamic        := `count += 4`
	dynamic.use_caller_scope = true
	scope_agnostic := Slacker(dynamic)

	@assert scope_agnostic.live_count() == 4, "use_caller_scope should resolve Slacker's own count instead of the outer one"
	@assert count == 2, "the outer count should be untouched since Slacker's own count was mutated instead"
)

demo_predictable()
demo_caller_scope()


### Statement(other) adopts, rather than re-captures

Wrapping an existing Statement with `Statement(...)` behaves exactly like reusing it directly -- same wrapped expression, same captured scope, same settings -- not like building a brand new one captured at wherever this `Statement(...)` call happens to be written.
###
x := 1
s := `x + 1`
wrapped := Statement(s)

@assert wrapped() == 2, 'Statement(other) should adopt the wrapped expression and captured scope, not re-capture its own call site'
