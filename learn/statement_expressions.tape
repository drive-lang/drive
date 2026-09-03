### Introduction

A backtick-wrapped expression -- `` `expr` `` -- doesn't run right away. It builds an `Tape::Statement` that wraps the expression as-is, callable later with `()`.
###
x := `1+2`
@assert "x: `x`" == 'x: Statement{Tape::Infix_Expr}', 'a bare Statement should describe the expression it wraps'
@assert x() == 3, 'calling a Statement should run the wrapped expression'


### Written directly at the call site, it's immediate

`` `expr`() `` right next to each other skips the "build it, store it" step -- the expression just runs on the spot.
###
result := `1+2`()
@assert result == 3, 'a Statement written and called in the same place should run immediately'


### Not memoized -- every call re-runs the expression

Stored in a variable, a Statement can be called any number of times. Each call re-interprets the wrapped expression fresh -- nothing about the result is cached.
###
counter   := 0
increment := `counter += 1`

increment()
increment()
increment()
@assert counter == 3, 'each call should re-run the wrapped expression, not cache the first result'


### A type annotation works too

`: Statement` is just the ordinary `: Type` annotation form -- same self-declaring rules as any other typed assignment.
###
y: Statement = `1+2`
@assert y() == 3, 'a Statement built via a type annotation should behave the same as a bare backtick literal'


### Extra call arguments are ignored

A Statement takes no params of its own -- whatever's wrapped inside the backticks is all that runs, regardless of what's passed to `()`.
###
z := `5 * 5`
@assert z(999, 'ignored') == 25, 'extra call arguments should be ignored'


### A practical use: deferring a directive

Directives like `@load` are ordinary expressions too, so wrapping one in backticks defers it the same way -- build the Statement now, run the load later.
###
loader := `@load 'tapes/string'`
loader()
@assert 'tape'.upcase() == 'TAPE', 'the deferred @load should have run once the Statement was called'
