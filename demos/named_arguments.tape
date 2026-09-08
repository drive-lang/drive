### Introduction

`name := value` at a call site binds by the callee's declared param *name*, not its position -- a separate mechanism from labels (demos/labeled_arguments.tape), which check a *position*'s declared label and never reorder anything. Named arguments genuinely reorder: any order you supply them in binds to the right param.
###
sub ( a, b;
	a - b
)

@assert sub(a := 1, b := 2) == -1, 'named arguments should bind by declared param name'
@assert sub(b := 2, a := 1) == -1, 'named arguments should give the same result regardless of order'


### Positional first, then named -- never the other way

A call can start with positional arguments (bare or labeled) and switch to named arguments partway through, but not switch back. Positional args still fill params left-to-right by position; named args fill by name, so the two never fight over the same param as long as you don't supply one both ways.
###
@assert sub(1, b := 2) == -1, 'positional then named should be fine'

# sub(a := 1, 2)  -- raises Tape::Positional_Argument_After_Named: a positional argument can't follow a named one


### Named arguments work through constructors too

`Self(;)`'s own params are just params -- calling `Type(...)` goes through the exact same binding as any other function call.
###
Point {
	x, y,

	Self ( x, y;
		self.x = x
		self.y = y
	)

	to_s (;
		"(`x`, `y`)"
	)
}

p := Point(y := 4, x := 3)
@assert p.to_s() == '(3, 4)', 'named arguments should bind to constructor params by name too'


### Named arguments compose with defaults

Omitting a named, defaulted param still falls back to its default, same as omitting it positionally would.
###
greet ( name := "World";
	"Hello, `name`"
)

@assert greet() == 'Hello, World', 'an omitted param should fall back to its default'
@assert greet(name := 'Drive') == 'Hello, Drive', 'a named argument should override the default'


### What goes wrong

The same name twice, a name that isn't a real param, or a param given both positionally and by name -- all three raise, rather than silently picking one:
###
# sub(a := 1, a := 2)  -- raises Tape::Duplicate_Named_Argument: a was given more than once
# sub(a := 1, c := 2)  -- raises Tape::Unknown_Named_Argument: c is not a declared parameter
# sub(1, a := 2)       -- raises Tape::Argument_Given_By_Name_And_Position: a was given both positionally and by name
