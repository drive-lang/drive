### Introduction

A *writable* scope is a fallback place identifier lookup checks, exactly like a readable scope (see learn/readable_scopes.tape) -- checked only after a scope's own declarations, never overriding anything already reachable there. The difference: it's also a fallback for writes. Assigning to a name that already exists on the unpacked instance (`=`, `+=`, ...) writes straight to that instance's own member, instead of declaring a fresh local. Declaring a brand new name (`:=`) always stays local either way -- only a write to a name the instance already has gets redirected. `@add_writable_scope`/`@remove_writable_scope` (medium alias: `@add_writable`/`@remove_writable`) add and remove one by hand; `@writable` is a shorthand meant for function param lists specifically.
###
Raft {
	length := 0
}

r := Raft()
r.length = 12
@add_writable_scope r
length = 99   # writes straight through -- r already has a `length` member
@assert r.length == 99, 'writing through a writable scope should land on the instance itself'
@remove_writable_scope r


### Auto-unpack in function parameters -- @writable

`@writable` is shorthand for `@add_writable_scope`, meant specifically for function param lists, where the longer name gets noisy fast. Use the short form there; use the full (or medium) name everywhere else, for clarity at the call site:
###
Vector {
	x := 0
	y := 0
}

double ( @writable vec;
	x *= 2
	y *= 2
	vec
)

v := Vector()
v.x = 3
v.y = 4
doubled := double(v)
@assert doubled.x == 6 && doubled.y == 8, '@writable should unpack the argument so writes land on it directly'


### Manual scope control, outside a function's own params

`@add_writable_scope instance` does the same unpacking by hand, in any scope, not just a function's param list -- useful when the instance to unpack isn't known until the body runs:
###
Island {
	name := 'unknown',
}

island := Island()
island.name = 'The Island'

@add_writable_scope island
name = 'Renamed Island'   # writes straight through -- island already has a `name` member
@assert island.name == 'Renamed Island', 'manually adding a writable scope should redirect writes the same way'
@remove_writable_scope island


### Medium alias

`@add_writable`/`@remove_writable` are the exact same thing as `@add_writable_scope`/`@remove_writable_scope`, just shorter -- for when the full name feels like a mouthful outside a function's param list, but `@writable` (the shortest form) feels too terse for the call site:
###
@add_writable island
name = 'Renamed Again'   # still writes straight through
@assert island.name == 'Renamed Again', 'the medium alias should behave identically to the full name'
@remove_writable island


### Lookup order: self, then writable, then readable

When a name exists in more than one place, the priority is always `[self, writable, readable]` -- a scope's own declarations win first, then anything reachable through a writable scope, then a readable scope. This applies to both reads *and* writes: an own declaration always wins, even over a same-named member reachable through a writable scope:
###
Marker { x := 0 }

x := 100
w := Marker()
w.x = 1
r := Marker()
r.x = 2

@add_writable_scope w
@add_readable_scope r

@assert x == 100, "the own declaration should win, not w's or r's"
x = 999
@assert x == 999 && w.x == 1, 'the write should land on the own declaration too, never redirect through w'


### Writable beats readable, when there's no own declaration in the way

With no own `y` to shadow anything, a name reachable through both a writable and a readable scope resolves through the writable one:
###
Marker2 {
	y := 0
}

w2 := Marker2()
w2.y = 10
r2 := Marker2()
r2.y = 20

@add_writable_scope w2
@add_readable_scope r2

@assert y == 10, 'with no own declaration to shadow anything, writable should win over readable'


### When a scope's own [self, writable, readable] chain comes up empty

The chain above only covers *one* scope. If none of the three find anything, resolution continues outward to the enclosing scope and tries the same three there -- and keeps going outward, scope by scope, until something matches or Global itself comes up empty. A nested function whose own scope has *nothing at all* falls all the way through to whatever its enclosing scope can see -- but the more precise claim is that each level's *entire* chain gets exhausted before moving on, even if that level has readable/writable content of its own -- it just has to not be the name being looked up:
###
Marker { val := 0 }
Other { unrelated := 99 }

outer (;
	o := Marker()
	o.val = 5
	@add_readable_scope o

	inner (;
		x := Other()
		@add_readable_scope x   # inner's own chain has *something* -- just not `val`
		val                     # falls through inner's whole chain, finds it on outer's
	)

	inner()
)

@assert outer() == 5, "a nested scope's empty chain should fall through to the enclosing scope's"


### Weak references, not strong ones

Adding something to a writable scope doesn't keep it alive either -- same as readable scopes (see learn/readable_scopes.tape). It's a *weak* reference: once nothing else in your program refers to it, it's free to be garbage collected, even though it's technically still "added". `@remove_writable_scope` is only for explicitly cutting something off early, not for avoiding a leak. This matters most for long-lived scopes -- the top level of a program, or anything a running `@start_server` keeps reusing across requests -- where, without weak references, anything ever unpacked there and never removed would sit in memory for the life of the program.
###
w3 := Vector()
w3.x = 5
w3.y = 6
doubled_w := double(w3)
@assert doubled_w.x == 10 && doubled_w.y == 12, 'no cleanup should be needed afterward, even though w3 was never @remove_writable_scope\'d'
