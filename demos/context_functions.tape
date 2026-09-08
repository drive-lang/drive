### Introduction

`@` is the current scope's context (see demos/context.tape). Alongside its reflective vitals, the
context carries a set of callable members -- `@puts`, `@assert`, `@declare`, `@push_scope` /
`@pop_scope`, `@sleep`, and a few more. `@word` is shorthand for `@.word`, so `@puts x` is a call
to the `puts` member with `x` as its argument -- an ordinary expression, not a special form.

This file covers the general-purpose ones. The rest have their own walkthrough, next to the
feature they belong to: `@load` (loading_code.tape), `@start_server` / `@stop_server`
(web_servers.tape), `@connect` (databases.tape), and `@splat` / `@splatr` /
`@unsplat` / `@push_scope` / `@pop_scope` (scopes.tape).
###
@puts '@word is shorthand for @.word -- an ordinary call on a context member'


### @puts

Prints a value and passes it straight back, so it drops into an expression without changing it.
Anything Scope-shaped (an Array, a custom Instance, etc.) goes through its own declared `to_s`
first, if it has one -- see strings.tape / arrays.tape for what each built-in type prints as.
###
@puts 'Land ho!'    # Land ho!
@puts 4 + 8          # 12

kept := @puts 'logged'
@assert kept == 'logged', '@puts returns its argument unchanged'

captured := @puts     # a bare @word is the member itself -- capturable
@assert captured('again') == 'again', 'the captured function still prints and passes through'


### @assert

`@assert condition` raises `Tape::Assert_Triggered` if `condition` is falsy. A second,
comma-separated argument becomes the failure message. `@refute` is the inverse.
###
survivors := 12
@assert survivors > 0, 'need at least one survivor'   # passes silently
@refute survivors > 100, 'camp is over capacity'      # passes silently
# @assert survivors > 100, 'camp is over capacity'  -- raises Tape::Assert_Triggered: camp is over capacity


### @declare

`@declare` puts a new identifier directly on the current scope, without going through `:=`. Handy
when the name itself is only known at runtime -- `:=` needs a literal identifier written in the
source, `@declare` takes a String.
###

# flare_count                       # raises Tape::Undeclared_Identifier since it isn't declared yet
@declare 'flare_count'            # name only -- declares nil
@assert flare_count == nil, '@declare with just a name should declare nil'

@declare 'flare_count', 3          # name, value
@assert flare_count == 3, '@declare with a value should overwrite the declaration'

@declare 'ration', 2, Number       # name, value, type -- same as `ration: Number = 2`
@assert ration == 2, '@declare with a type should still declare the value'


### @declare with a Struct

Passed a Struct instead of a name, `@declare` spreads every *named* member onto the current scope
in one go -- each member's own name, value, and declared type carry over directly. Unnamed members
are skipped, since there's nothing to declare them as.
###
supplies := <water: Number = 40, wood := 12>
@declare supplies
@assert water == 40, '@declare with a Struct should spread each named member'
@assert wood == 12, '@declare with a Struct should spread each named member'


### @push_scope / @pop_scope

`@push_scope scope` pushes a scope directly onto the interpreter's stack, so its members become
reachable without a prefix, and any bare declaration made while "inside" lands on the pushed scope
itself. `@pop_scope scope` pops back out -- you name the scope you're popping, and `@pop_scope`
asserts it's identical to whatever `@push_scope` actually pushed; naming the wrong one raises
instead of silently popping something else. scopes.tape goes further (Type-wide vs per-instance
reopening).
###
Camp {
	survivors := 12
}
Other { }

camp := Camp()
@push_scope camp
# @pop_scope Other  -- would raise: Other was never pushed, camp was
survivors += 3   # no camp. prefix needed -- camp IS the current scope now
@pop_scope camp
@assert camp.survivors == 15, '@push_scope should make members reachable without a prefix'


### @sleep

Pauses execution for the given number of seconds. Mostly useful for demos / throttling, not for
business logic, I hope.
###
@sleep 0.1
@puts 'done waiting'   # done waiting
