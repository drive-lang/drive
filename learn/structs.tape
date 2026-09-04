### Introduction

Sometimes you want to attach a small bundle of typed data to something without declaring a whole new Type for it. Structs are Tape's answer: `<...>` builds a small, runtime-inspectable value on the spot.

This file is about Structs as standalone values. Attaching a struct to a Type name instead (to create independent, tagged variants of that type) is a related but separate feature -- see learn/tagged_types.tape for that.
###
pair := <String, Number>
type_names := pair.types.values.map((it;
	it.name
)).join(', ')
@assert type_names == 'String, Number', "a struct's member types should list each declared type"


### Two layers, don't confuse them

- Tape::Member/Tape::Struct (Ruby, src/external/ruby/struct.rb + member.rb) -- the low-level engine behind every `<...>` literal above. Always present, no load required.
- Member/Struct (Tape, tapes/struct.tape + member.tape) -- a separate, higher-level layer built on top, loaded by default as part of the standard library (`tapes/preload.tape` -- `@load 'tapes/struct.tape'` here is redundant, just explicit). Gives you a proper Tape-level Struct type with a real `.members` array, `has?`/`include?`, and custom `==`/`+` operators, so a `<...>` literal actually runs a real declared type's body instead of being a bare Ruby struct.
###
@load 'tapes/struct.tape'


### Members

A Member just remembers a name, a value, and a type, and knows how to describe itself. The constructor order is name, value, type -- not name, type, value:
###
f1 := Member('age', 42, Number)
f2 := Member('name', nil, String)

@assert f1.to_s() == 'age: Number = 42', "a Member's to_s should describe its name, type, and value"
@assert f2.to_s() == 'name: String', "a Member with no value supplied should omit the value"


### Instantiating a struct directly

`<name: String, age: Number>` alone is schema-only -- as shown in the Introduction, each member's "value" there is its declared type, not real data. Calling `()` on a struct literal is how you turn that schema into an actual instance: the arguments become each member's real value, positionally, same order as declared:
###
s := <name: String, age: Number>('Alice', 30)
@assert s.to_s() == "<name: String = 'Alice', age: Number = 30>", "instantiating a struct should fill in each member's real value"
@assert s.members.0.to_s() == "name: String = 'Alice'", '.members should hold each real Member instance'
@assert s.members.1.to_s() == 'age: Number = 30', '.members should hold each real Member instance'


### Equality

Member declares two different comparisons. `==` compares name, type, AND value -- "is this the exact same member, value included". `===` compares only name and type, ignoring value entirely -- "is this the same kind of member":
###
a := Member('id', nil, Number)
b := Member('id', nil, Number)
c := Member('id', 5, Number)

@assert (a == b) == true, '== should be true for the same name, type, and value (both nil)'
@assert (a === b) == true, '=== should be true for the same name and type'
@assert (a == c) == false, '== should be false when the value differs (nil vs 5)'
@assert (a === c) == true, '=== should still be true -- name and type match regardless of value'


### Struct equality

Struct's `==`/`===` just delegate to its `.members` array, comparing element-wise with the exact same rules as above -- `==` needs every member's value to match too, `===` only needs the same members to exist with the same types:
###
sa := <name: String, age: Number>('Alice', 30)
sb := <name: String, age: Number>('Alice', 30)
sc := <name: String, age: Number>('Alice', 99)

@assert (sa == sb) == true, '== should be true for identical values'
@assert (sa === sb) == true, '=== should be true for the same set of members'
@assert (sa == sc) == false, '== should be false when age differs (30 vs 99)'
@assert (sa === sc) == true, '=== should still be true -- still the same set of members'


### Bare named structs

Putting an identifier right in front of `<...>` (`Ident<...>`) isn't an error, as long as nothing is already declared under that name -- it builds a plain Struct, exactly like `<...>` alone, except with `.name` set from the identifier. A struct built with no name in front has a `nil` `.name`, only reachable through whatever variable holds it:
###
Anonymous := <String, Number>
@assert Anonymous.name == nil, 'a struct built with no name in front has no .name of its own'

Named <String, Number>
n := Named <String, Number>
@assert n.name == 'Named', 'Ident<...> builds a real struct with .name taken from Ident'


### Type lookup always wins

This only kicks in when the identifier is genuinely undeclared -- a name that collides with something real still behaves exactly as it always did:
###
Abc\<Number> {}
# Abc<String> would raise Tape::Undeclared_Type_Structure --
# Abc is declared (tagged, via `\`), just not with that shape, so it's never treated as a bare named struct.


### Structs and Tuples together

Tuples (`(...)`) and Structs (`<...>`) both hold an ordered list of values, and both can be pulled apart into their individual pieces with the same destructuring syntax: `(targets) := source`. This section is about how the two work together through that.
###
num_pair := (1, 2)
trio     := <1, 2, 3>
quad     := <1, id := 2, ix: Number, String>(4, 8, 1, 'five')

@assert "`num_pair`" == '(1, 2)', 'a Tuple should display as (values, ...)'
@assert "`trio`" == '<1, 2, 3>', 'a Struct should display as <values, ...>'
@assert "`quad`" == "<4, id: Number = 8, ix: Number = 1, 'five'>", 'a named Struct should display each member with its name/type'
@assert num_pair.values == [1, 2].values, '.values should give the underlying Ruby-side values'
@assert trio.values == [1, 2, 3].values, '.values should give the underlying Ruby-side values'
@assert quad.values == [4, 8, 1, 'five'].values, '.values should give the underlying Ruby-side values, named or not'


### Same destructuring syntax, either source

`(x, y) := source` extracts values positionally into fresh locals -- works identically whether `source` is a Tuple or a Struct, since both are just an ordered list of values underneath:
###
(tx, ty) := (1, 2)
@assert tx + ty == 3, 'destructuring a Tuple should extract values positionally'

(sx, sy) := <10, 20>
@assert sx + sy == 30, 'destructuring a Struct should extract values positionally, same as a Tuple'


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
(dx: Number, dy) := (1, 2)
@assert dx == 1, 'a typed target should extract normally when the value matches'

# (dx: String, dy) := (1, 2)  -- raises Type_Contract_Violation: extracted value is a Number, not a String


### Destructuring straight into an existing member

A target doesn't have to be a fresh local -- `thing.member` reassigns an existing member instead, same rules as writing `thing.member = value` directly: the member has to already exist, can't be a constant, and (if it has a locked type) the extracted value has to match it. See learn/members.tape for why the member has to already exist.
###
Point {
	x, y,
	Self ( x, y;
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
