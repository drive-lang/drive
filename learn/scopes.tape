### Readable scopes

A *readable* scope is a fallback place identifier lookup checks, after a scope's own declarations -- it never overrides anything already reachable, and it's read-only: nothing ever writes through it. `@add_readable_scope`/`@remove_readable_scope` (medium alias: `@add_readable`/`@remove_readable`) add and remove one by hand; `@readable` is a shorthand meant for function param lists specifically. Writable scopes are a related, separate feature -- covered further down this file.
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

	Self ( survivors, water;
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

`String`/`Array`/etc. are reachable through Global's own readable scope, not declared on Global directly -- see learn/loading_code.tape. Reassigning a built-in name shadows it for the rest of your program without ever touching the real one; if what you reassign it to still composes the original, everything keeps working, and every literal of that type picks up whatever else you added too:
###
Mine | Array { extra := true }
Array = Mine

@assert [1,2,3].length() == 3, 'reassigning Array should not break literals -- Mine composes Array'
@assert [1].extra == true, 'every array literal should now pick up what Mine added too'


### Writable scopes

A *writable* scope is a fallback place identifier lookup checks, exactly like a readable scope (above) -- checked only after a scope's own declarations, never overriding anything already reachable there. The difference: it's also a fallback for writes. Assigning to a name that already exists on the unpacked instance (`=`, `+=`, ...) writes straight to that instance's own member, instead of declaring a fresh local. Declaring a brand new name (`:=`) always stays local either way -- only a write to a name the instance already has gets redirected. `@add_writable_scope`/`@remove_writable_scope` (medium alias: `@add_writable`/`@remove_writable`) add and remove one by hand; `@writable` is a shorthand meant for function param lists specifically.
###
Life_Raft {
	length := 0
}

wr := Life_Raft()
wr.length = 12
@add_writable_scope wr
length = 99   # writes straight through -- wr already has a `length` member
@assert wr.length == 99, 'writing through a writable scope should land on the instance itself'
@remove_writable_scope wr


### Auto-unpack in function parameters -- @writable

`@writable` is shorthand for `@add_writable_scope`, meant specifically for function param lists, where the longer name gets noisy fast. Use the short form there; use the full (or medium) name everywhere else, for clarity at the call site:
###
Compass {
	x := 0
	y := 0
}

double_bearing ( @writable vec;
	x *= 2
	y *= 2
	vec
)

cv := Compass()
cv.x = 3
cv.y = 4
doubled := double_bearing(cv)
@assert doubled.x == 6 && doubled.y == 8, '@writable should unpack the argument so writes land on it directly'


### Manual scope control, outside a function's own params

`@add_writable_scope instance` does the same unpacking by hand, in any scope, not just a function's param list -- useful when the instance to unpack isn't known until the body runs:
###
Islet {
	name := 'unknown',
}

islet := Islet()
islet.name = 'The Island'

@add_writable_scope islet
name = 'Renamed Island'   # writes straight through -- islet already has a `name` member
@assert islet.name == 'Renamed Island', 'manually adding a writable scope should redirect writes the same way'
@remove_writable_scope islet


### Medium alias

`@add_writable`/`@remove_writable` are the exact same thing as `@add_writable_scope`/`@remove_writable_scope`, just shorter -- for when the full name feels like a mouthful outside a function's param list, but `@writable` (the shortest form) feels too terse for the call site:
###
@add_writable islet
name = 'Renamed Again'   # still writes straight through
@assert islet.name == 'Renamed Again', 'the medium alias should behave identically to the full name'
@remove_writable islet


### Lookup order: self, then writable, then readable

When a name exists in more than one place, the priority is always `[self, writable, readable]` -- a scope's own declarations win first, then anything reachable through a writable scope, then a readable scope. This applies to both reads *and* writes: an own declaration always wins, even over a same-named member reachable through a writable scope:
###
Marker { val := 0 }

val := 100
w := Marker()
w.val = 1
r := Marker()
r.val = 2

@add_writable_scope w
@add_readable_scope r

@assert val == 100, "the own declaration should win, not w's or r's"
val = 999
@assert val == 999 && w.val == 1, 'the write should land on the own declaration too, never redirect through w'


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
Marker3 { val := 0 }
Other { unrelated := 99 }

outer (;
	o := Marker3()
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


### Weak references, not strong ones (writable too)

Adding something to a writable scope doesn't keep it alive either -- same as readable scopes above. It's a *weak* reference: once nothing else in your program refers to it, it's free to be garbage collected, even though it's technically still "added". `@remove_writable_scope` is only for explicitly cutting something off early, not for avoiding a leak. This matters most for long-lived scopes -- the top level of a program, or anything a running `@start_server` keeps reusing across requests -- where, without weak references, anything ever unpacked there and never removed would sit in memory for the life of the program.
###
cv2 := Compass()
cv2.x = 5
cv2.y = 6
doubled2 := double_bearing(cv2)
@assert doubled2.x == 10 && doubled2.y == 12, 'no cleanup should be needed afterward, even though cv2 was never @remove_writable_scope\'d'


### Reopening a scope directly

`@push_scope <Type or instance>` pushes that scope directly onto the stack, so declarations made inside it become real members of the target -- unlike the readable/writable scopes above, which only add a fallback lookup place without mutating anything. `@pop_scope <same target>` pops back out to whatever scope was active before -- it asserts the target is identical to what `@push_scope` actually pushed, raising instead of popping the wrong thing.
###
Button {
	label := 'default'
}

@push_scope Button
css_filter := 'invert()'
@pop_scope Button

b := Button()
@assert b.css_filter == 'invert()', 'a member declared while pushed onto the Type should be reachable on an instance'


### Reopening a Type extends every instance

`css_filter` above was added to the `Button` type, not to any one instance -- so every `Button()` built afterward (and even ones already built) sees it, the same as if it had been declared in the original body:
###
another_button := Button()
@assert another_button.css_filter == 'invert()', 'the same declaration should be shared by every Button'


### Reopening one instance changes just that instance

`@push_scope` also accepts an instance directly, in which case the new declarations land only on that one value -- every other instance of the same type is untouched:
###
button_c := Button()
button_d := Button()

@push_scope button_c
onclick := 'clicked'
@pop_scope button_c

@assert button_c.onclick == 'clicked', 'the reopened instance should have the new member'
# button_d.onclick would raise Tape::Undeclared_Identifier -- only button_c was reopened, not the Button type
