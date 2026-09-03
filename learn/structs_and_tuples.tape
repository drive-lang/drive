### Introduction by Claude

Tuples (`(...)`) and Structs (`<...>`) both hold an ordered list of values, and both can be pulled apart into their individual pieces with the same destructuring syntax: `(targets) := source`. This file is about how the two work together through that. See learn/structs.tape and learn/tagged_types.tape for Structs on their own first if you haven't already. Loading `tapes/struct.tape` (like those two files do) is what gives a Struct's `.values` a proper `to_s` for display below -- not required for destructuring itself, which works either way.
###
@load 'tapes/struct.tape'

pair := (1, 2)
trio := <1, 2, 3>
quad := <1, id := 2, ix: Number, String>(4, 8, 1, 'five')

@assert "`pair`" == '(1, 2)', 'a Tuple should display as (values, ...)'
@assert "`trio`" == '<1, 2, 3>', 'a Struct should display as <values, ...>'
@assert "`quad`" == "<4, id: Number = 8, ix: Number = 1, 'five'>", 'a named Struct should display each member with its name/type'
@assert pair.values == [1, 2].values, '.values should give the underlying Ruby-side values'
@assert trio.values == [1, 2, 3].values, '.values should give the underlying Ruby-side values'
@assert quad.values == [4, 8, 1, 'five'].values, '.values should give the underlying Ruby-side values, named or not'


### Same destructuring syntax, either source

`(a, b) := source` extracts values positionally into fresh locals -- works identically whether `source` is a Tuple or a Struct, since both are just an ordered list of values underneath:
###
(a, b) := (1, 2)
@assert a + b == 3, 'destructuring a Tuple should extract values positionally'

(c, d) := <10, 20>
@assert c + d == 30, 'destructuring a Struct should extract values positionally, same as a Tuple'


### Extracting fewer than what's there is fine

You don't have to take everything -- the rest are just discarded:
###
(first, second) := <1, 2, 3>
@assert first == 1 && second == 2, 'extracting fewer targets than values should discard the rest'


### Asking for more than exists raises

The other direction is a real error, not padding with nil. Uncomment to see it:
###
# (a, b, c) := <1, 2>   -- raises Destructuring_Arity_Mismatch: only 2 values to fill 3 targets


### Typed targets are checked against what comes out

Annotate a target with `: Type` and the extracted value has to match it:
###
(x: Number, y) := (1, 2)
@assert x == 1, 'a typed target should extract normally when the value matches'

# (x: String, y) := (1, 2)  -- raises Type_Contract_Violation: extracted value is a Number, not a String


### Destructuring straight into an existing member

A target doesn't have to be a fresh local -- `thing.member` reassigns an existing member instead, same rules as writing `thing.member = value` directly: the member has to already exist, can't be a constant, and (if it has a locked type) the extracted value has to match it. See CLAUDE.md's "Member Creation Is Strict" for why the member has to already exist.
###
Point {
	x, y,
	new ( x, y;
		self.x = x
		self.y = y
	)
}

p := Point(0, 0)
(p.x, p.y) := (3, 4)
@assert p.x == 3 && p.y == 4, 'destructuring into existing members should reassign them, like thing.member = value'


### The two target kinds mix freely in one destructure

A fresh local and an existing member can sit side by side in the same `(...)`:
###
p2 := Point(0, 0)
(p2.x, offset_y) := (5, 9)
@assert p2.x == 5 && offset_y == 9, 'a fresh local and an existing member should be able to mix in one destructure'


### Structs as a "return multiple values" convention

Since `<...>` is just a value like any other, a function can hand back several results by returning a Struct (or Tuple) literal, and the caller destructures it immediately:
###
min_and_max ( a, b;
	if a < b
		<a, b>
	else
		<b, a>
	end
)

(lo, hi) := min_and_max(9, 3)
@assert lo == 3 && hi == 9, 'a returned Struct should destructure into multiple values at the call site'


### Named structs still destructure positionally

Member names don't change how destructuring reads a Struct -- it only ever goes by position, so a named Struct works exactly like an unnamed one here:
###
(name, age) := <name: String = 'Alice', age: Number = 30>
@assert name == 'Alice' && age == 30, 'a named Struct should still destructure by position, not by name'
