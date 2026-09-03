### Introduction

A *readable* scope is a fallback place identifier lookup checks, after a scope's own declarations -- it never overrides anything already reachable, and it's read-only: nothing ever writes through it. `@add_readable_scope`/`@remove_readable_scope` (medium alias: `@add_readable`/`@remove_readable`) add and remove one by hand; `@readable` is a shorthand meant for function param lists specifically. Writable scopes are a related, separate feature -- see learn/writable_scopes.tape.
###
Raft {
	length := 0
	crew := 0
}

r := Raft()
r.length = 12
r.crew = 4
@add_readable_scope r
@assert length == 12, 'length should be reached via the readable scope, no r. prefix needed'
@remove_readable_scope r
# @puts length would now raise Tape::Undeclared_Identifier -- r was removed from the readable scope


### Auto-unpack in function parameters -- @readable

`@readable` is shorthand for `@add_readable_scope`, meant specifically for function param lists, where the longer name gets noisy fast. Use the short form there; use the full (or medium) name everywhere else, for clarity at the call site.
###
Vector {
	x := 0
	y := 0
}

magnitude ( @readable vec;
	(x ** 2 + y ** 2).sqrt()
)

v := Vector()
v.x = 3
v.y = 4
@assert magnitude(v) == 5.0, '@readable should unpack the argument so x/y resolve directly'


### Manual scope control, outside a function's own params

`@add_readable_scope instance` does the same unpacking by hand, in any scope, not just a function's param list -- useful when the instance to unpack isn't known until the body runs:
###
Island {
	name := 'unknown',
}

island := Island()
island.name = 'The Island'

@add_readable_scope island
@assert name == 'The Island', 'manually adding a readable scope should unpack it the same way'
@remove_readable_scope island
# @puts name would now raise Tape::Undeclared_Identifier -- island was removed from the readable scope


### Medium alias

`@add_readable`/`@remove_readable` are the exact same thing as `@add_readable_scope`/`@remove_readable_scope`, just shorter -- for when the full name feels like a mouthful outside a function's param list, but `@readable` (the shortest form) feels too terse for the call site:
###
@add_readable island
@assert name == 'The Island', 'the medium alias should behave identically to the full name'
@remove_readable island


### Unpacked instances stay visible to later functions, even nested ones

Once unpacked, an instance's members stay reachable from any function declared afterward in that scope -- including one nested inside another function -- because a readable scope is just another place identifier lookup checks, not a one-time substitution:
###
Camp {
	survivors := 0
	water := 0

	new ( survivors, water;
		self.survivors = survivors
		self.water = water
	)
}

ration_report (;
	c := Camp(12, 40)
	@add_readable_scope c

	summarize (;
		"`survivors` survivors, `water` units of water"
	)

	summarize()

)

@assert ration_report() == '12 survivors, 40 units of water', 'a nested function should still see the readable scope'


### Weak references, not strong ones

Adding something to a readable scope doesn't keep it alive. It's a *weak* reference -- once nothing else in your program refers to it anymore, it's free to be garbage collected, even though it's technically still "added". Tape doesn't expose garbage collection directly, so you'll never observe this from inside the language, but it means `@remove_readable_scope` is only for explicitly cutting something off early -- you don't need it just to avoid a leak.
###
add_temporary_reading ( @readable vec;
	# vec is only reachable via the readable scope for the duration of this call -- nothing needs
	# to @remove_readable_scope it afterward. Once the call returns and nothing else references
	# the instance that was passed in, it's simply gone, readable scope membership included.
	x + y
)

w := Vector()
w.x = 5
w.y = 6
@assert add_temporary_reading(w) == 11, 'no cleanup should be needed afterward'


### The standard library works this way too

`String`/`Array`/etc. are reachable through Global's own readable scope, not declared on Global directly -- see learn/load_directive.tape. Reassigning a built-in name shadows it for the rest of your program without ever touching the real one; if what you reassign it to still composes the original, everything keeps working, and every literal of that type picks up whatever else you added too:
###
Mine | Array { extra := true }
Array = Mine

@assert [1,2,3].length() == 3, 'reassigning Array should not break literals -- Mine composes Array'
@assert [1].extra == true, 'every array literal should now pick up what Mine added too'
