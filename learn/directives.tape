### Introduction

A directive is `@word`, optionally followed by arguments. They're the interpreter's own escape hatch -- things that aren't really expressions (printing, asserting, declaring on the fly, moving the scope stack around) but still read like part of the language. This file covers `@puts`, `@assert`, `@declare`, `@push_scope`/`@pop_scope`, and `@sleep` -- `scopes.tape` goes further on `@push_scope`/`@pop_scope` specifically (Type-wide vs per-instance reopening). A few other directives already have their own walkthrough, since they only make sense alongside the feature they belong to, like `@load` (`load_directive.tape`), `@start_server`/`@stop_server` (`web_server.tape`), `@connect` (`database.tape`), and `@add_readable_scope`/`@readable`, `@add_writable_scope`/`@writable` (both in `scopes.tape`).
###
@puts 'a directive is just @word plus one or more arguments'


### @puts

Prints a value. Anything Scope-shaped (an Array, a custom Instance, etc.) goes through its own declared `to_s` first, if it has one -- see `strings.tape`/`arrays.tape` for what each built-in type prints as.
###
@puts 'Land ho!'   # Land ho!
@puts 4 + 8         # 12


### @assert

`@assert condition` raises `Tape::Assert_Triggered` if `condition` is falsy. A second, comma-separated argument becomes the failure message.
###
survivors := 12
@assert survivors > 0, 'need at least one survivor'   # passes silently
# @assert survivors > 100, 'camp is over capacity'  -- raises Tape::Assert_Triggered: camp is over capacity


### @declare

`@declare` puts a new identifier directly on the current scope, without going through `:=`. Handy when the name itself is only known at runtime -- `:=` needs a literal identifier written in the source, `@declare` takes a String.
###

# flare_count                         # raises Tape::Undeclared_Identifier since it isn't declared yt
@declare 'flare_count'            # name only -- declares nil
@assert flare_count == nil, '@declare with just a name should declare nil'

@declare 'flare_count', 3          # name, value
@assert flare_count == 3, '@declare with a value should overwrite the declaration'

@declare 'ration', 2, Number       # name, value, type -- same as `ration: Number = 2`
@assert ration == 2, '@declare with a type should still declare the value'


### @declare with a Struct

Passed a Struct instead of a name, `@declare` spreads every *named* member onto the current scope in one go -- each member's own name, value, and declared type carry over directly. Unnamed members are skipped, since there's nothing to declare them as.
###
supplies := <water: Number = 40, wood := 12>
@declare supplies
@assert water == 40, '@declare with a Struct should spread each named member'
@assert wood == 12, '@declare with a Struct should spread each named member'


### @push_scope / @pop_scope

`@push_scope scope` pushes a scope directly onto the interpreter's stack, so its members become reachable without a prefix, and any bare declaration made while "inside" lands on the pushed scope itself. `@pop_scope scope` pops back out -- unlike the old `@cd ..`, you name the scope you're popping, and `@pop_scope` asserts it's identical to whatever `@push_scope` actually pushed; naming the wrong one raises instead of silently popping something else.
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

Pauses execution for the given number of seconds. Mostly useful for demos/throttling, not for business logic, I hope.
###
@sleep 0.1
@puts 'done waiting'   # done waiting
