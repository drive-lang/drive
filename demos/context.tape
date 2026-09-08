### Introduction

`@` is the current scope's *context* -- a small struct the interpreter fills with facts about
wherever `@` is written: its name, the types it composes, how it displays, and a handful of
built-in functions (`@puts`, `@assert`, ...). Every scope has one -- Global, a Type, an instance,
a function body -- built the first time you reach for it.
###
@assert @ === Context, 'at is the current scope context'
@assert @.name == 'Global', 'at the top level it describes Global'


### `@word` is shorthand for `@.word`

Reading a member off the context is common enough to have a prefix form: `@name` means `@.name`,
`@root_path` means `@.root_path`, and so on.
###
@assert @name == @.name, 'at-word and at-dot-word are the same thing'
@assert @.root_path == @root_path, 'both spellings reach the same member'


### The vitals

Reflective facts about the scope. `name`/`display_name` are its identity; `object_id` and
`size_in_bytes` are the plain Ruby-level numbers (`size_in_bytes` is shallow -- this object only,
not what it points at).
###
@assert @.object_id =>= Number, 'object_id is a number'
@assert @.size_in_bytes =>= Number, 'size_in_bytes is a number'
@assert not @root_path.empty?(), 'root_path is the absolute path to the project directory'


### `@.to_s()` -- a context prints as `@<name>`

`to_s` is one of the context's function members, so it takes `()`.
###
@assert @.to_s() == '@Global', "the Global context stringifies as '@Global'"


### On a Type

Written inside (or against) a Type, `@` describes that Type. `@.composed_types` is the set of every
type it composes -- its own name plus anything brought in with `|` / `&` / `~` / `^`.
###
Flying { airborne := true }
Duck | Flying { name := 'duck' }

@assert Duck.@name == 'Duck', 'a Type context knows its own name'
@assert Duck.@composed_types.include?('Flying'), 'composed_types lists everything the type composes'
@assert Duck.@composed_types.include?(Flying), 'the class reference works too -- a String equals a bare Type by name'


### Through an instance

An instance has its own context, but a member it doesn't carry falls through to its Type's context
-- so `duck.@name` still answers `'Duck'`.
###
duck := Duck()
@assert duck.@name == 'Duck', "an instance's context falls through to its type's"


### Struct reflection

A struct's shape is `@`-only -- plain `.` on a struct is for its own members. `@.names`,
`@.type_names`, `@.types` and `@.values` describe the members; `@.name` is a bare named struct's
identifier (or nil).
###
schema := <id: Number, title: String>
@assert schema.@names == ['id', 'title'], '@.names is the member names'
@assert schema.@type_names == ['Number', 'String'], '@.type_names is each member type'

Point <x: Number, y: Number>
@assert Point.@name == 'Point', 'a bare named struct carries its identifier on @.name'
@assert (<1, 2>).@name == nil, 'an anonymous struct has no name'


### Enum reflection

Same idea for enums: `@.keys`, `@.values`, `@.count`.
###
Status [ OPEN, CLOSED, MERGED ]
@assert Status.@keys == ['OPEN', 'CLOSED', 'MERGED'], '@.keys is the member names'
@assert Status.@count == 3, '@.count is how many members'


### The function members

`@puts`, `@assert`, `@refute`, `@sleep`, and a few more live on the context too. `@puts` prints its
arguments and passes them straight through, so it drops into an expression without changing the
value.
###
kept := @puts('logged')          # prints: 'logged'
@assert kept == 'logged', '@puts returns its argument unchanged (a passthrough)'

captured := @puts                 # a bare reference -- the function itself
@assert captured('again') == 'again', 'the function member can be captured and called later'


### Declaring your own `@` members on a Type

Inside a `Type { }` body you can hang your own members off the type's context with `@name`. They
show up under `@`, never in plain `.` access -- so they can't collide with the type's real
members. A built-in name (`@name`, `@types`, ...) is reserved and raises if you try.
###
Widget {
	@version := 2
	@author: String = 'me'

	stamp (; "widget v`@version` by `@author`" )
}

@assert Widget.@version == 2, 'a context member is readable off the Type'
@assert Widget().stamp() == 'widget v2 by me', 'and from inside the body'

w := Widget()
@assert w.@version == 2, 'instances see it too (through the type context)'
