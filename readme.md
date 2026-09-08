![Version](https://img.shields.io/badge/version-0.0.0-2B7FFF.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-2B7FFF.svg)
[![justforfunnoreally.dev badge](https://img.shields.io/badge/justforfunnoreally-dev-2B7FFF)](https://justforfunnoreally.dev)
![Status of project Ruby tests](https://github.com/drive-lang/drive/actions/workflows/tests.yml/badge.svg)

Learn about the language below, or [in the learn section](learn/readme.md), or *[click here to get started using it](getting_started.md)*.

---

## Variables

1. Must start with a lowercase letter or `_`.
2. Can end with `!` or `?`

```tape
nothing := nil
something: Number = 123
_private_thing := "Yes"
tested? := false
```

## Functions

1. Must start with a lowercase letter or `_`
2. The function body is surrounded with `()` parens
3. The arguments are declared before the arguments/body delimiter `;`
4. The body comes after the arguments/body delimiter `;`
5. The last expression is the return value
6. Return early using `return` keyword

```tape
# func_name ( [args]; [body] )

func_with_args ( arg1, arg2 := 1, etc := true;
    # body
)

without_args (;
    # body
)

add ( a, b;
    a + b
)
add(4, 8)  # 12

_privately_do ( x, y, z; )

# A call whose single argument is an anonymous function may drop that argument's parens,
# when the receiver is a member access / call / subscript:
[1, 2, 3].map(n; n * 2)     # == [1, 2, 3].map((n; n * 2))
```

## Labeled & Named Function Arguments

**Labels** — a param declared as two identifiers in a row (`label name`) can be called `label: value`. Matches by position, never reorders. Opt-in per call; wrong label raises `Argument_Label_Mismatch`.

```tape
send_message ( to person, saying text;
    "To `person`: `text`"
)

send_message(to: 'Jack', saying: 'Found fresh water')  # positional and labeled both work
send_message('Sayid', 'Meet at the caves')
```

**Named arguments** — `name := value` at a call site binds by the callee's declared param name, order-independent. Positional args (bare or labeled) must come first; once you name one, the rest must be named too.

```tape
sub ( a, b; a - b )

sub(a := 1, b := 2)   # -1
sub(b := 2, a := 1)   # -1 reordered, same result
sub(1, b := 2)        # -1 positional then named is fine

# sub(a := 1, 2)       raises Positional_Argument_After_Named
# sub(a := 1, a := 2)  raises Duplicate_Named_Argument
# sub(a := 1, c := 2)  raises Unknown_Named_Argument
# sub(1, a := 2)       raises Argument_Given_By_Name_And_Position
```

**Struct-typed params** — `: <...>` instead of a plain type name checks *structurally*, not by name: any argument that has each listed member, with a compatible type, is accepted. `Any` matches any member type. Checked on every call, raising `Type_Contract_Violation` on a mismatch.

```tape
f ( right: <name: String, type: Any, value: Any>; right.name )

m := Member('x', String, 4)
f(m)     # 'x' -- Member isn't named in the annotation, it just has all three members
f(nil)   # raises Type_Contract_Violation
```

## Recursion

A named function is registered in its enclosing scope as it's declared, so it can call itself.

```tape
factorial ( n;
    if n == 0 or n == 1
        1
    else
        n * factorial(n - 1)
    end
)
factorial(8)  # 40320

fib ( n;
    if n <= 1
        n
    else
        fib(n - 1) + fib(n - 2)
    end
)
fib(10)  # 55

fizz_buzz ( n;
    if n % 15 == 0
        'FizzBuzz'
    elif n % 3 == 0
        'Fizz'
    elif n % 5 == 0
        'Buzz'
    else
        n.to_s()
    end
)

for 1...15
    @puts fizz_buzz(it)
end
```

## Forward Declarations

Calling a function, or referencing a type, works even before its own declaration is reached in the file — including mutual recursion between two functions declared in either order.

```tape
result := main()   # `main` hasn't been declared yet, but this still works

main (; helper() )
helper (; 42 )

result  # 42
```

```tape
is_even ( n;
    if n == 0
        true
    else
        is_odd(n - 1)
    end
)

is_odd ( n;
    if n == 0
        false
    else
        is_even(n - 1)
    end
)

is_even(4)  # true
```

A class-styled alias (`This := That {}`) hoists the same way, since it's declaring a type just spelled through an assignment:

```tape
p := This()

This := That {}
That { greet (; 'hi' ) }

p.greet()  # 'hi'
```

A bare `@load` hoists too, so imports can live at the bottom of the file instead of the top:

```tape
sign := Div([P('hi')])
sign.to_s()  # '<div><p>hi</p></div>'

@load 'tapes/html.tape'
```

`Ident := @load 'file'` / `IDENT := @load 'file'` work the same way — only a Capitalized or UPPERCASE left-hand name opts in, since that's what marks it as a namespace rather than an ordinary variable:

```tape
sign := Html_Lib.Div([Html_Lib.P('hi')])
sign.to_s()  # '<div><p>hi</p></div>'

Html_Lib := @load 'tapes/html.tape'

# html_lib := @load 'tapes/html.tape'   -- lowercase stays a plain variable, not hoisted
```

Plain variable assignments are never hoisted this way — reading one before its own line has actually run still raises `Undeclared_Identifier`, same as any language with top-to-bottom execution:

```tape
@puts "`a`"   # raises Undeclared_Identifier
a := 123
```

## Classes

1. Must start with an uppercase character
2. Can have an initializer `Self`

```tape
My_Class {
    input,
    
    Self ( input;
        self.input = input  # self is the current instance, like this in other languages
        @puts 'Initted with "`input`"'
    )
}

instance := My_Class('some input')  # Initted with "some input"
```

## Constants

1. Must be UPPERCASE
2. Cannot be reassigned after initial declaration

```tape
PI := 3.14159
MAX_SIZE := 100
APP_NAME := 'My App'
```

## Comments

```tape
# This is a single-line comment
# Stack a few of these for a multi-line comment

###
Or wrap a whole block in ###/### -- everything in between is discarded,
including lines of code, so it doubles as a way to comment out code.
###

####
A longer run of #s on the outer marker can safely nest a same-length
or shorter ### inside it, since only a marker at least as long as the
opening one closes the block -- the same rule ``` fences use to nest.
### this looks like a comment but it's just text in here ###
still inside the outer comment
####
```

## String Interpolation

1. Use backticks inside strings to interpolate expressions
2. Escape with backslash to prevent interpolation

```tape
name := 'World'
greeting := "Hello, `name`!"  # "Hello, World!"
math := "2 + 2 = `2 + 2`"    # "2 + 2 = 4"
escaped := "Literal \`backticks\`"
```

## Scope Keywords

`self`, `Self`, and `Global` are bare scope keywords — each is a value on its own, and `Keyword.member` reaches one name in exactly that scope, no outward search:

1. `self` — the current instance only
2. `Self` — the current type only (where statics live)
3. `Global` — the global scope only

```tape
My_Class {
    Self.count := 0   # Type-level (static) variable
    value,

    Self ( value;
        self.value = value   # Instance variable (like this.value in other languages)
        Self.count += 1      # Access static from instance
    )

    get_global (;
        Global.PI  # reach a global constant past any local shadow
    )
}
```

## Static Declarations

1. Use `Self.` to declare type-level (static) members
2. Shared across all instances
3. Accessed on the type itself: `Type.member`

```tape
Counter {
    Self.count := 0

    Self.increment (;
        count += 1
    )

    Self (;
        Self.count += 1
    )
}

Counter()
Counter()
Counter.count  # 2
```

## Type Composition

1. `|` union: merge all members from both types
2. `&` intersection: keep only shared members
3. `~` removal: remove members of right type from left
4. `^` symmetric difference: keep non-shared members

```tape
Movable {
    x := 0
    y := 0
    move ( dx, dy;
        x += dx
        y += dy
    )
}

Drawable {
    color := 'black'
    draw (; "Drawing in `color`" )
}

# Combine types
Sprite | Movable | Drawable {
    name := 'sprite'
}

s := Sprite()
s.move(10, 5)
s.draw()
```

Composition chains, so `~` can remove a trait that was mixed in earlier in the same chain:

```tape
Flying { can_fly := true }
Swimming { can_swim := true }

Duck | Flying | Swimming { name := 'duck' }
d := Duck()
d.can_fly     # true
d.can_swim    # true

Ostrich | Duck ~ Flying { name := 'ostrich' }
o := Ostrich()
o.can_swim    # true
o.can_fly     # raises Tape::Undeclared_Identifier
```

A type can even compose with itself, to extend or override a built-in type's own behavior:

```tape
Array | Array {
    each ( func;
        for self.values   # self.values reaches the original Array's own values, despite `each` itself now being redefined
            func(it)
        end
    )
}

values := Array([1, 2, 3])
doubled := []
values.each(( it;
    doubled.push(it * 2)
))
doubled  # [2, 4, 6]
```

### Alias vs. subtype

There are two ways to give a type a second name, and they behave differently under the [type comparison operators](#comparison):

```tape
Whole | Integer {}    # subtype — Whole is a NEW type that composes Integer
Int32 := Integer      # alias   — Int32 IS Integer, the same type object

4 === Integer          # true
4 === Int32            # true   (alias — identical composed-type set)
4 === Whole            # false  (subtype — 4's set is {Integer, Number}; Whole adds itself)

Whole  =>= Integer     # true   (a Whole is-a Integer)
Integer =>= Whole      # false  (not every Integer is a Whole)
```

Use `:=` when you just want a synonym (`Int := Integer` in the standard library); use `| {}` when the new name should be a distinct, narrower type that `=>=` its parent but isn't `===` to it.

## Conditionals

1. `if`/`elif`/`else`/`end`
2. `unless` is the negation of `if`
3. Can be used as inline modifiers
4. Any value works as a condition -- truthiness follows Ruby's own rules: only `nil`/`false` are falsy, everything else (`0`/`0.0` included) is truthy

```tape
if x > 10
    'big'
elif x > 5
    'medium'
else
    'small'
end

unless logged_in
    redirect('/login')
end

# Inline conditionals
@puts 'yes' if condition
@puts 'no' unless condition
```

## While & Until Loops

1. `while` loops while condition is true
2. `until` loops until condition becomes true
3. `elwhile` chains another loop when prior condition becomes false

```tape
i := 0
while i < 5
    @puts i
    i += 1
end

j := 0
until j == 5
    @puts j
    j += 1
end

# Chained loops with elwhile
x := 0
y := 0
while x < 4
    x += 1
elwhile y > -8
    y -= 1
else
    @puts 'done'
end
```

## For Loops

1. Iterate over arrays, ranges, or any iterable
2. `it` is the current element
3. `at` is the current index

```tape
for [1, 2, 3]
    @puts it      # Current element
    @puts at      # Current index
end

for 1...5
    @puts it      # 1, 2, 3, 4, 5
end

# With stride (chunks)
for [1, 2, 3, 4, 5, 6] by 2
    @puts it      # [1,2], [3,4], [5,6]
end
```

## For Loop Verbs

1. `map` transforms each element
2. `select` filters where body is truthy
3. `reject` filters where body is falsy
4. `count` counts where body is truthy

```tape
doubled := for [1, 2, 3] map
    it * 2
end  # [2, 4, 6]

evens := for [1, 2, 3, 4, 5] select
    it % 2 == 0
end  # [2, 4]

odds := for [1, 2, 3, 4, 5] reject
    it % 2 == 0
end  # [1, 3, 5]

even_count := for [1, 2, 3, 4, 5, 6] count
    it % 2 == 0
end  # 3
```

## Loop Control

1. `skip` continues to next iteration
2. `stop` breaks out of loop
3. `return` exits the function (propagates through loops)

```tape
for items
    skip if it.this     # Continue to next
    stop if it.that     # Break out
end

find_first ( predicate;
    for items
        return it if predicate(it)
    end
    nil
)
```

## Splatting a Scope

Every scope keeps two extra fallback places identifier lookup checks, after its own declarations — a **read-only** set and a **writable** set (also a fallback for writes) — making an instance's members reachable without an `instance.` prefix. Lookup order is always `[self, writable, read-only]`: a scope's own declarations win first.

1. `@splat x` unpacks `x` as a writable splat; `@splatr x` read-only; `@unsplat x` removes it. Works on a function param (the common case) or by hand anywhere.
2. A `: Type` / `: <...>` annotation on a splat param *is* enforced at the call — pass the wrong shape and you get a `Type_Contract_Violation` right there, not an `Undeclared_Identifier` deep in the body.
3. Both sets are held *weakly* — a splatted instance isn't kept alive; once nothing else refers to it it's collectible on its own, so `@unsplat` is only for cutting something off early, not for avoiding a leak.
4. The standard library lives this way — `String`/`Array`/etc. are reachable through Global's own read-only splat, not declared on Global directly. Reassigning a built-in (`Array = Mine`) can't mutate the real one; it just shadows the name for the rest of your program.

```tape
Vector {
    x := 0
    y := 0
}

# Auto-unpack in a parameter
magnitude ( @splatr vec;
    (x ** 2 + y ** 2).sqrt()  # x, y resolve directly
)

v := Vector()
v.x = 3
v.y = 4
magnitude(v)  # 5

# @splat (writable) lets a plain write reach the unpacked instance's own member
double ( @splat vec;
    x *= 2   # writes straight through to vec.x
    y *= 2
    vec
)
doubled := double(v)  # doubled.x: 6, doubled.y: 8

# By hand, anywhere
@splatr some_instance
@unsplat some_instance
```

```tape
# The standard library works the same way -- Array is reachable through
# Global's own read-only splat, not declared on Global directly
Mine | Array { extra := true }
Array = Mine          # shadows the name -- the real Array is untouched
[1, 2, 3].length()    # 3 -- still works, Mine composes Array
[1].extra              # true -- and every array literal now has this too
```

An unpacked instance stays visible to functions defined after the unpack, even nested ones:

```tape
Point {
    a := 0
    b := 0

    Self ( a, b;
        self.a = a
        self.b = b
    )
}

outer (;
    p := Point(23, 42)
    @splatr p

    inner (;
        a + b   # a, b resolved from p via the splat, despite being nested inside outer
    )

    inner()
)
outer()  # 65
```

## Reopening Scopes (`@push_scope`/`@pop_scope`)

1. `@push_scope <Type or instance>` pushes that scope directly onto the stack, so declarations made inside it become real members of the target
2. `@pop_scope <same target>` pops back to the previous scope — it asserts (by identity) that you're popping what you actually pushed, raising instead of popping the wrong thing
3. Unlike a splat, `@push_scope` mutates its target — reopening a Type extends every instance of it, reopening a specific instance changes only that one

```tape
Button {
    label := 'default'
}

@push_scope Button
    css_filter := 'invert()'   # extends the Type itself
@pop_scope Button

b := Button()
b.css_filter   # 'invert()' — every Button gets it, since Button itself was extended

@push_scope b
    onclick := { @puts 'clicked' }   # modifies just this instance
@pop_scope b

c := Button()
c.onclick   # raises Tape::Undeclared_Identifier — only b was modified
```

## Arrays

1. Created with `[]` brackets
2. Access elements with subscript or dot notation

```tape
arr := [1, 2, 3, 4, 5]
arr[0]              # 1
arr.0               # 1 (dot notation)

arr.push(6)         # Add to end
arr.pop()           # Remove from end
arr.length()        # 5
arr.first(2)        # [1, 2]
arr.last(2)         # [4, 5]
arr.reverse()
arr.include?(3)     # true
arr.empty?()        # false

arr.map(x; x * 2)       # a lone anonymous-function argument may drop its own parens
arr.filter(x; x > 2)    # (equivalent to arr.filter((x; x > 2)))
```

## Dictionaries

1. Created with `{}` braces and key-value pairs
2. Keys can be symbols, strings, or identifiers
3. Access with subscript `dict[:key]`

```tape
dict := {x: 10, y: 20}
dict[:x]            # 10
dict[:z] = 30       # Assignment

dict.keys()         # [:x, :y, :z]
dict.values()       # [10, 20, 30]
dict.has_key?(:x)   # true
dict.count()        # 3
dict.empty?()       # false
dict.delete(:z)
dict.merge({a: 1})
dict.fetch(:missing, 'default')
```

## Sets

1. An unordered collection of unique items -- no literal, build one with `Set(...)`
2. Seed it from an array, a range, or another set

```tape
s := Set([1, 2, 2, 3])   # {1, 2, 3} -- dedups
s.add(4)                  # mutating methods return self, so they chain
s.include?(2)             # true
s.length()                # 4
s.values()                # [1, 2, 3, 4] -- a fresh array snapshot

Set([1, 2, 3]) | Set([3, 4])    # union          -> {1, 2, 3, 4}
Set([1, 2, 3]) & Set([2, 3, 4]) # intersection   -> {2, 3}
Set([1, 2, 3]) - Set([2, 3, 4]) # difference     -> {1}
Set([1, 2, 3]) ^ Set([2, 3, 4]) # symmetric diff -> {1, 4}

Set([1, 2]).subset?(Set([1, 2, 3]))   # true
Set([1, 2, 3]).map(n; n * 10)          # [10, 20, 30]

for Set([1, 2, 3])
    @puts it
end
```

## Strings

```tape
s := 'Hello, World!'
s.length            # 13
s.0                 # 'H' (dot notation, indexes by character -- same as Array's own .0)
s.upcase()          # 'HELLO, WORLD!'
s.downcase()        # 'hello, world!'
s.split(', ')       # ['Hello', 'World!']
s.trim()            # Remove whitespace
s.chars()           # ['H', 'e', 'l', ...]
s.reverse()
s.include?('World') # true
s.start_with?('He') # true
s.end_with?('!')    # true
s.gsub('World', 'Drive')
s.to_i()            # Convert to integer
s.empty?()          # false
```

## Percent Literals

1. `%string(...)`/`%symbol(...)` turn space-separated bare items into a real Array of String/Symbol literals, preserving each item's own casing
2. `%str`/`%Str`/`%STR` force lower/Capital/UPPER casing on the strings; `%sym`/`%Sym`/`%SYM` do the same for symbols
3. Items can be identifiers, numbers, or operators, not just letters
4. Items split only on whitespace, not on punctuation — `1px` and `file.ext` each stay one item
5. A `` `expr` `` item (see Statement Expressions below) is evaluated immediately, like string interpolation, and folded through the same casing treatment as everything else

```tape
%string(boo Hoo COOL)      # [boo, Hoo, COOL]
%symbol(BOO hoo Cool)      # [:BOO, :hoo, :Cool]

%str(Boo hOO COOL)         # [boo, hoo, cool]
%Str(boo HOO cOOl)         # [Boo, Hoo, Cool]
%STR(boo Hoo cool)         # [BOO, HOO, COOL]

%sym(Boo HOO cOOl)         # [:boo, :hoo, :cool]
%Sym(boo HOO cOOl)         # [:Boo, :Hoo, :Cool]
%SYM(boo Hoo cool)         # [:BOO, :HOO, :COOL]

%string(boo 4815 + - *)    # [boo, 4815, +, -, *]

cool := 2342
%string(481516 `cool`)     # [481516, 2342] -- `cool` is interpolated, not stored as-is

%string(1px solid red)     # [1px, solid, red]
%string(file.ext other)    # [file.ext, other]
```

## Statement Expressions

1. `` `expr` `` wraps any expression without running it -- an `Tape::Statement`, callable later with `()`
2. Written straight at a call site, `` `expr`() `` just evaluates immediately
3. Stored in a variable, it can be called any number of times -- each call re-evaluates the wrapped expression fresh, by default remembering the scope it was *built* in (a normal closure, no matter where `()` ends up being called from)
4. `.memoize = true` caches the first call's result instead of re-running every time
5. `.use_caller_scope = true` does the opposite of remembering -- resolves fresh against wherever `()` is actually called from

```tape
`1+2`()                    # 3 -- evaluated right away

x := `1+2`
x()                        # 3
x: Statement = `1+2`       # same thing, with an explicit type annotation

counter := 0
increment := `counter += 1`
increment()
increment()
increment()
counter                    # 3 -- each call actually re-ran the body

cached := `counter += 1`
cached.memoize = true
cached()                   # 4
cached()                   # 4 -- didn't run again
```

See `learn/statements.tape` for the full picture, including `.use_caller_scope`.

## Numbers

```tape
n := 42
n.abs()             # Absolute value
n.floor()           # Round down
n.ceil()            # Round up
n.round()           # Round to nearest
n.sqrt()            # Square root
n.even?()           # true
n.odd?()            # false
n.to_s()            # '42'
n.clamp(0, 100)     # Clamp to range
```

## Dates & Times

`Date`, `Time`, and `Date_Time` are always available -- no `@load`.

```tape
Date.today()                # today
Date.parse('2020-03-15')
Time.now()
Time.at(1_700_000_000)      # from epoch seconds
Date_Time.now()
Date_Time.parse('2020-03-15T09:30:00+00:00')

d := Date.parse('2020-03-15')
d.year         # 2020
d.month        # 3
d.day          # 15
d.weekday      # 0   (0 = Sunday .. 6 = Saturday; Date only)
d.iso8601()    # '2020-03-15'

Time.now().epoch()   # Unix seconds (Time only)

Date.parse('2020-01-01') < Date.parse('2021-01-01')   # true -- all of < > <= >= == != work
```

`Time` and `Date_Time` also have `.hour`, `.minute`, `.second`.

## Ranges

1. `...` inclusive range
2. `..<` exclusive end
3. `>..` exclusive start
4. `>.<` exclusive both

```tape
1...5   #   1, 2, 3, 4, 5    (inclusive)
1..<5   #   1, 2, 3, 4       (exclusive end)
1>..5   #      2, 3, 4, 5    (exclusive start)
1>.<5   #      2, 3, 4       (exclusive both)

for 1...10
    @puts it
end
```

A range is a real value with its own methods:

```tape
r := 1...5
r.start()          # 1
r.finish()         # 5
r.length()         # 5
r.include?(3)      # true
r.to_a()           # [1, 2, 3, 4, 5]
r.sum()            # 15
r.map(n; n * n)             # [1, 4, 9, 16, 25]
r.filter(n; n % 2 == 0)     # [2, 4]

x: Range = 1...5   # a `: Range` contract holds
1...5 === Range    # true
```

A range also works as an Array or String subscript — each operator keeps its own end/start rule, so `[1...3]` is one element longer than `[1..<3]`. Endless and beginless forms slice too; a negative endpoint counts from the end:

```tape
xs := [10, 20, 30, 40, 50]
xs[1...3]    # [20, 30, 40]      inclusive
xs[1..<3]    # [20, 30]          exclusive end
xs[2...]     # [30, 40, 50]      endless
xs[...3]     # [10, 20, 30, 40]  beginless
xs[...-1]    # [10, 20, 30, 40, 50]   -1 is the last index
"abcdef"[0..<2]   # 'ab'
```

## File I/O

```tape
@load 'tapes/file_system.tape'

content := File_System.read('./file.txt')
File_System.write_string_to_file('./out.txt', 'Hello!')
```

## The Context (`@`)

`@` is the current scope's *context* — a struct the interpreter fills with facts about wherever it's written, plus a set of built-in functions. Every scope has one: Global, a Type, an instance, a function body. There's no separate "directive" concept — `@word` is just `@.word`.

```tape
@ === Context      # true
@.name             # 'Global' at the top level
@.to_s()           # '@Global'
```

`@word` is shorthand for `@.word` — `@name` is `@.name`, and `@puts x` / `@load 'f'` call a function member.

### Reflective vitals

Read-only facts about the scope, snapshotted the first time `@` is reached (a struct's `@.values` / `@.members` are the exception — they always reflect its current member values, even after a `.member = …` write):

```tape
Flying { airborne := true }
Duck | Flying {}

Duck.@name              # 'Duck'
Duck.@composed_types    # Set{'Duck', 'Flying'} — own name plus every |/&/~/^ type
Duck.@object_id         # the plain Ruby number

[1, 2, 3].@type         # 'Array' — @type / @types read on any value
nil.@type               # 'Nil'
```

Reflection lives on `@` only. Plain `.` is reserved for a scope's own members, so a struct member named `name` or `types` never collides with the reflective accessor of the same name:

```tape
Row <name: String, types: Number>
r := Row('cooper', 3)

r.name         # 'cooper'        — the member
r.@name        # 'Row'           — the struct's identifier
r.@type_names  # ['String', 'Number']
r.@names       # ['name', 'types']
```

### Function members

`@puts`, `@assert`, `@refute`, `@sleep`, `@load`, `@declare`, `@push_scope` / `@pop_scope`, `@connect`, `@start_server` / `@stop_server`, and the scope functions `@splat` / `@splatr` / `@unsplat` all live on the context. A bare `@puts` (no call) is the function itself, so it can be captured:

```tape
kept := @puts('logged')   # prints 'logged', returns it unchanged (a passthrough)
p := @puts
p('again')                # 'again'
```

### Your own `@` members on a Type

Inside a `Type { }` body you can hang your own members off the type's context. They show up under `@`, never in plain `.` access, so they can't collide with the type's real members. A built-in name (`@name`, `@types`, ...) is reserved and raises.

```tape
Widget {
    @version := 2
    @author: String = 'me'

    stamp (; "widget v`@version` by `@author`" )
}

Widget.@version   # 2
w := Widget()
w.@version        # 2 — an instance reads through to its type's context
```

## @load

1. Imports another Drive file
2. A file is only run once per scope it's loaded into — loading the same file into the same scope again returns the first run's result instead of re-running it
3. Imports may be scoped by assigning the @load to a variable

```tape
@load 'tapes/string.tape'
@load 'tapes/array.tape'
@load './my_module.tape'
my_mod := @load './my_module.tape'
my_mod.Some_Type()

@load './my_module.tape'   # already loaded into this scope -- returns the same result again, doesn't re-run
```

## @puts

```tape
@puts 'Hello, World!'
@puts variable
@puts "Value: `expression`"
```

`@puts` is a passthrough: it prints, then returns the original value unchanged, so it can sit inline anywhere an expression is expected:

```tape
double ( n; n * 2 )
double(@puts 5)   # prints 5, returns 10 -- the call still gets the real 5
```

### Telling printed values apart

Drive's built-in collection types each wrap their printed contents in a different bracket, so you can tell what you're looking at at a glance:

```tape
@puts [1, 2, 3]      # [1, 2, 3]      -- Array
@puts (1, 2, 3)      # (1, 2, 3)      -- Tuple
@puts {x: 1, y: 2}   # {x: 1, y: 2}   -- Dictionary
@puts <1, 2, 3>      # <1, 2, 3>      -- Struct
```

A custom type prints as raw internals until it defines its own `to_s(;)` — see [Classes](#classes):

```tape
Point {
    x := 1
    greet (; 'hi' )
}
@puts Point()   # #<Tape::Instance name="Point" declarations=["x", "greet"]>
```

Nothing enforces a bracket convention for your own types, but picking one that doesn't collide with the built-ins above keeps output easy to scan.

## @declare

1. Declares an identifier on the current scope from a runtime String name, rather than a literal identifier written in the source (what `:=` needs)
2. `@declare name` declares `nil`; `@declare name, value` and `@declare name, value, type` add a value and, optionally, a type
3. Passed a Struct instead of a name, spreads every *named* member onto the current scope in one go — each member's own name, value, and declared type carry over directly

```tape
@declare 'flare_count'          # flare_count == nil
@declare 'flare_count', 3       # flare_count == 3
@declare 'ration', 2, Number    # same as `ration: Number = 2`

supplies := <water: Number = 40, wood: Number = 12>
@declare supplies               # water == 40, wood == 12
```

## Web Server

1. Compose with `Server` type
2. Define routes with HTTP method syntax
3. Boot with `@start_server` (background thread; `@stop_server` to shut one down)

```tape
@load 'tapes/server.tape'

App | Server {
    Self (;
        self.port = 3000
    )

    get:// (;
        'Hello, World!'
    )

    get://about (;
        'About page'
    )
}

@start_server App()
```

## Routes

1. HTTP methods: `get://`, `post://`, `put://`, `delete://`, `patch://`
2. URL parameters with `:param` syntax
3. Query params via `request.query`

```tape
App | Server {
    # Static route
    get://users (;
        'All users'
    )

    # URL parameter
    get://users/:id ( id;
        "User `id`"
    )

    # Multiple params
    get://posts/:post_id/comments/:id ( post_id, id;
        "Comment `id` on post `post_id`"
    )

    # Query strings: /search?q=term
    get://search (;
        query := request.query[:q]
        "Searching for `query`"
    )
}
```

## Request & Response

```tape
post://login (;
    username := request.body[:username]
    password := request.body[:password]

    if authenticate(username, password)
        response.redirect('/dashboard')
    else
        response.status = 401
        'Unauthorized'
    end
)

get://api/data (;
    response.headers['Content-Type'] = 'application/json'
    '{"status": "ok"}'
)
```

## Database

1. `@load 'tapes/database.tape'` -- this pulls in `tapes/table.tape` too
2. `Sqlite(url)` builds a database; `@connect` opens it and **returns it**
3. `Sqlite.memory()` for an in-memory db, `Sqlite.local('name')` for `temp/name.db`

```tape
@load 'tapes/database.tape'

db := @connect Sqlite('./data/app.db')
```

A schema is a **named Struct** -- one member per column, its type deciding the column type. The table name comes from the struct's name (`User` -> `users`), so the struct has to be named.

```tape
User <
    id: Primary_Key
    name: String
    email: String
    joined_at: Date_Time
>

db.find_or_create_table(User)   # -> a Table (creates it if missing)
db.table_exists?(User)          # true          (also takes a bare :users)
db.tables()                     # [users]  -- Symbols
db.find_table('users')          # -> a Table, or nil
db.delete_table!(User)          # also takes a bare :users
```

Column types: `Primary_Key`, `String`/`Text`, `Int`, `Number`, `Bool`, `Date`, `Time`, `Date_Time`. `Flo`/`Decimal`/`Blob` are mapped but not backed by a Drive type yet.

## Record ORM

`db.find_or_create_table(schema)` returns a `Table`. CRUD lives on that object -- no model composition, no statics.

```tape
users := db.find_or_create_table(User)

cooper := users.create(<name := 'Cooper'>)   # attrs are a `:=`-member Struct
users.create(<name := 'Luna'>)

users.all()                       # Array of record Structs
users.find(cooper.id)             # one record Struct, or nil
users.find_by(<name := 'Luna'>)   # first match, or nil
users.where(<name := 'Luna'>)     # Array of matches
users.update(cooper.id, <name := 'Cooper II'>)
users.delete(cooper.id)
users.count()
```

- A record is a `Struct` named after the schema -- read members by name (`record.name`), or `record.to_h` for the whole row
- `Bool` columns round-trip as real `true`/`false`; `Date`/`Time`/`Date_Time` columns round-trip as the matching wrapper (`record.joined_at.year`)
- A filter naming a column the schema doesn't have raises `Tape::Table_Invalid_Filter_Column`

## HTML Elements

1. Compose with HTML element types from `tapes/html.tape`
2. `css_*` prefix sets inline CSS properties
3. `html_*` prefix sets HTML attributes
4. `.to_s()` renders an element and its children to string directly

```tape
@load 'tapes/html.tape'

Card | Div {
    css_padding := '1rem'
    css_border_radius := '8px'
    css_background_color := '#fff'

    html_class := 'card'
    html_data_value := 42
    html_aria_label,
}

Link | A {
    html_href = '#'
    html_target := '_blank'
}

page := Html([
    Head(Title('My Page'))
    Body([
        H1('Welcome')
        Card([
            P('Hello!')
            Link('Click me')
        ])
    ])
])
```

## CSS

1. `@load 'tapes/css.tape'` -- CSS is plain data: `Property`/`Style_Rule`/`At_Rule`/`Scope_Rule`/`Custom_Property_Rule`/`Layer_Order`/`Keyframe`/`Variable_Declaration`/`Css_Function`/`Color` are all bare structs, no parser involved
2. `Css_Formatter_Visitor` walks a tree of those structs and turns it into a real CSS string -- pretty by default, `minify := true` for one line
3. A rule nested inside another rule's own `rules` gets a synthesized `&` prefix (real CSS nesting); a rule merely sitting inside an `At_Rule`/`Scope_Rule` body does not, since there's no parent selector for `&` to refer to there
4. `Css_Lint_Visitor` walks the same kind of tree checking for duplicate properties, hardcoded vendor prefixes, and redundant zero-units (`0px` -> `0`) instead of formatting it. Handed a whole `Stylesheet`, it also warns when a state rule (`.card:hover`, `:focus`, ...) sets `transform` while the base selector runs a keyframe `animation` that also animates `transform` — the running animation recomputes it every frame, so the hover value never shows

```tape
@load 'tapes/css.tape'

rule := Style_Rule(['.card'], [Property('color', 'red'), Property('padding', '8px')])

Css_Formatter_Visitor().format(rule)
# ".card {\n    color: red;\n    padding: 8px;\n}"

Css_Formatter_Visitor(minify := true).format(rule)
# ".card{color:red;padding:8px;}"

Css_Lint_Visitor().lint(Style_Rule(['.a'], [Property('color', 'red'), Property('color', 'blue')]))
# ["Duplicate property 'color'"]
```

## Struct-Based HTML

1. `@load 'tapes/html2.tape'` -- same spirit as CSS above: `Element <tag, attributes: Array\Attribute, css: Css, children>` is the one node shape, and lowercase constructors (`div`, `p`, `h1`, ...) build it. Coexists with `tapes/html.tape`'s `Dom` types above rather than replacing them -- this one only builds an HTML string, it doesn't hook into the server's live-render pipeline (onclick wiring, `dom.js`)
2. `attributes` is an ordered `Array\Attribute` (`Attribute(name, value)`, built the same way `Property` builds a CSS declaration) -- not a Dictionary, so attributes keep their given order and can even collide (see `Html_Lint_Visitor` below)
3. `css` takes any css.tape struct directly -- `Html_Formatter_Visitor` renders it as one more child, an embedded `<style>` block, wherever it's attached
4. `Html_Render`/`Html_Format` are two shared `Html_Formatter_Visitor` instances (compact/pretty); void tags (`br`, `img`, `input`, ...) never get a closing tag in either mode
5. `Html_Stats_Visitor` (node count, depth, unique tags), `Html_Sanitizer_Visitor` (strips `script`/`iframe`/`object`/`embed` and `on*`/`javascript:` attributes), and `Html_Lint_Visitor` (void element given children, `<img>` missing `alt`, empty containers, duplicate attribute names) walk the same tree for their own purposes -- `Html_Lint_Visitor` and `Css_Lint_Visitor` both compose `tapes/visitor.tape`'s `Warnings_Visitor` mixin for their shared `warnings`/`warn` machinery

```tape
@load 'tapes/html2.tape'
@load 'tapes/css.tape'

page := div([
    h1('Welcome'),
    p('Hello!', [Attribute('class', 'greeting')])
], [], Style_Rule(['.greeting'], [Property('color', 'blue')]))

Html_Render.render(page)
# '<div><h1>Welcome</h1><p class="greeting">Hello!</p><style>.greeting{color:blue;}</style></div>'
```

## Operators

### Arithmetic

```tape
+ - * / %     # Basic math
**            # Exponentiation
<< >>         # Bitwise shift / Array append
```

### Comparison

```tape
== !=             # Equality
< <= > >=         # Relational
<=>               # Spaceship (three-way)
=~ !~             # Regex match
=== =!=           # Composed-type-set equality
=>= =<=           # Composed-type-set superset (and its mirror) =>= means "left superset of right?", and its mirror
=/=               # Composed-type-set disjointness means they don't share anything
```

`===`, `=!=`, `=>=`, `=<=`, and `=/=` compare a type or instance's *composed types* — its own name plus everything it's picked up via `|`/`&`/`~`/`^` — rather than comparing values:

```tape
Flying { can_fly := true }
Swimming { can_swim := true }

Duck | Flying | Swimming { name := 'duck' }
Fish | Swimming { name := 'fish' }

Duck === Duck          # true  (identical composed types)
Duck === Fish          # false (Duck also composes Flying)
Duck =!= Fish          # true

Duck =>= Swimming      # true  (Duck composes with at least Swimming)
Swimming =>= Duck      # false
Swimming =<= Duck      # true  (=<= is =>= with the operands flipped)

Duck =/= Fish          # false (both compose Swimming — not disjoint)
Flying =/= Swimming    # true  (share nothing)
```

All five comparison operators also take [Structs](#structs) into account. An untagged type is treated as having no members, so plain comparisons like the ones above are unaffected:

```tape
Abc\<Number> {}
Abc\<Number> === Abc\<String>   # false — same composed type, different tag
Abc === Abc                     # true  — neither side tagged
```

`Any` is a universal wildcard for `==`/`!=`/`===`/`=!=`: anything that isn't `nil` counts as equal to it, no composition needed.

```tape
String === Any    # true
4 == Any          # true
nil == Any        # false — the one exception
```

A String compares equal (`==`/`!=` only) to a bare Type whose `@name` it spells — so a collection of type-name strings can be scanned with a real type:

```tape
Flying { can_fly := true }
Duck | Flying {}

"Flying" == Flying                       # true
Duck.@composed_types.include?(Flying)    # true — the set holds the string 'Flying'
```

### Logical

```tape
&& and        # Logical AND
|| or         # Logical OR
! not         # Logical NOT
```

### Assignment

```tape
:=            # Declaration — introduces a new identifier, infers and locks its type
=             # Assignment — requires the identifier to already be declared
+= -= *= /=   # Compound assignment
&&= ||=       # Logical compound
<<= >>=       # Shift compound
```

## Operator Overloading

1. Declare with `@operator`, a symbol or identifier, a fixity (`@infix`, `@prefix`, `@postfix`), a precedence number, and a function body
2. Overloads are stored as regular functions in the declaring scope, so they can be scoped to a single function without leaking out
3. Precedence controls how overloaded operators combine with each other and with built-ins
4. If a type declares its own overload for an operator, that always wins over a same-named overload declared elsewhere — dispatch is by the left operand's type first, falling back to whatever's in scope only if the operand doesn't have its own

```tape
# Redefine + only inside this function — everywhere else, + still adds
scoped := compute (;
    @operator + @infix 700 ( left, right;
        left * right
    )
    3 + 4
)

3 + 4      # 7 (unaffected outside)
scoped()   # 12

# Build a pipeline operator
@operator -> @infix 300 ( left, right;
    right(left)
)

double ( n; n * 2 )
add_fifteen ( n; n + 15 )

4 -> double -> add_fifteen  # 23

# Invent new literal syntax
Time { hour, minute, period, }

@operator : @infix 700 ( hour, minute;
    t := Time()
    t.hour = hour
    t.minute = minute
    t
)

@operator pm @postfix 600 ( left: Time;
    left.period = 'pm'
    left
)

11:22pm  # Time(hour: 11, minute: 22, period: 'pm')

# Or a prefix operator that builds a value from a bare literal
Currency { amount, name, code, }

@operator $ @prefix 900 ( amount;
    c := Currency()
    c.amount = amount
    c.name = 'US Dollar'
    c.code = 'USD'
    c
)

$42  # Currency(amount: 42, name: 'US Dollar', code: 'USD')

# A type's own overload beats a same-named global one. A fresh symbol (~>, not ->) since
# declaring another global -> here would just overwrite the pipeline -> declared above it,
# in the same global scope.
@operator ~> @infix 300 ( left, right; 999 )

Wrapped {
    val,
    Self ( v; self.val = v )
    @operator ~> @infix 300 ( left, right; left.val )
}

a := Wrapped(42)
a ~> 1          # 42 — Wrapped's own ~> wins
5 ~> double     # 999 — global ~> still applies to everything else
```

## Runtime Type Contracts

1. `:=` infers a type from its right-hand side and locks the identifier to it
2. Subsequent `=` assignments are checked against that locked type; `:=` again re-infers and re-locks
3. A mismatch raises `Tape::Type_Contract_Violation`, not the static type checker's `Type_Mismatch`

```tape
x := 4        # declares x, infers Number, locks x to that type
x = 8         # ok — same type
x = 'hello'   # raises Tape::Type_Contract_Violation ("expected Number, got String")

x := 4
x := 'hello'  # fine — re-declaring with := re-infers and re-locks the type
x             # 'hello'

y = 4         # raises Tape::Cannot_Assign_Undeclared_Identifier — y was never declared
```

## Function Signatures

1. `(Param, Param -> Type;)` is a signature — a value describing a function's shape (its param types and return type), with no implementation — same `-> Type` placement a real function uses, just with no body
2. A real function always declares its own return type inside its body, with `-> Type` at the end of its param list before `;` — a self-declaring signature uses the same shape under its name (`double: (Number -> Number;)`)
3. Assigning a function to a signature-typed identifier checks its actual shape, not just a name — mismatches raise `Tape::Type_Contract_Violation`, the same runtime type contract `:=` uses
4. Any function with a declared return type is checked on every call — what it actually returns has to match, signature or not

```tape
Currency_Formatter := (Number -> String;)    # takes a Number, returns a String

format_usd ( cents: Number -> String;
    "$" + (cents / 100.0).to_s()
)

format_eur ( cents: Number -> String;
    "€" + (cents / 100.0).to_s()
)

formatter: Currency_Formatter = format_usd
formatter(1050)               # "$10.5"

formatter = format_eur        # ok — same shape: (Number) -> String
formatter(1050)               # "€10.5"

formatter = ( cents; cents )  # raises Tape::Type_Contract_Violation — wrong shape
```

A declared return type is enforced on its own, with no signature involved:

```tape
lying ( a -> Number; 'not a number' )
lying(5)   # raises Tape::Type_Contract_Violation — declared Number, actually returned String
```

## Structs

1. `<...>` attaches runtime-inspectable metadata (a struct) to a standalone value. Tagging a *Type* declaration/reference itself uses `\` instead, to stay unambiguous with a plain struct value and with comparisons — `Array\<String> {}` (inline literal), `Array\Task_Schema {}`/`Array\String {}` (a named reference to an already-declared struct or Type), `Primary_Key\4815` (a bare integer, a "version tag")
2. `\` chains: `Thing\One\Two {}` tags `Thing` with `One`, which is itself tagged with `Two`. `.tag` is `One`, `.tag.tag` is `Two`
3. Each declared tag is its own type — `Abc\<Number> {}` and `Abc\<String> {}` don't share `Self`/methods, and `Thing\One\Two` and `Thing\One\Three` are distinct too
4. A reference matches a declared tag by type (like overload resolution), including types it composes and not just its own name, at every link of the chain. Referencing a real Type with no matching variant yet auto-declares one; referencing anything else with no match raises `Tape::Undeclared_Tagged_Type`
5. Reachable through `.tag` (`.tag.types`, or `.tag.some_name` for named members) — bound before `Self(;)` runs, never forwarded as constructor args
6. `x.tag = new_tag` re-tags at runtime, but only on a value whose type was declared with a tag, and only when `new_tag` composes at least everything the current tag does, at every chain link (`=>=`) — otherwise `Tape::Tag_Signature_Violation`
7. Naming an *undeclared* identifier with bare `<...>` (no `\`, e.g. `Named<...>`) builds a plain, named struct instead of raising — a name that's already taken by a real Type still takes priority and behaves as above
8. A bare named struct's member can be annotated with the struct's own name (`Node <name: String, parent: Node>`) — and two structs can reference each other. An empty `Name <>` is a forward declaration a later `Name <...>` fills in; redeclaring an already-filled struct with a *different* shape raises `Tape::Undeclared_Tagged_Type`

```tape
String\<dict: Dictionary> {
    to_s (; "dict: `tag.dict`" )
}
String\<num: Number> {
    to_s (; "number: `tag.num`" )
}

String\<{x=1}>().to_s()   # "dict: {x: 1}"
String\<5>().to_s()       # "number: 5"

Format_A {} Format_B {} Format_C {}
Payload\Format_A\Format_B\Format_C {
    trace (; [self.tag.@type_names.0, self.tag.tag.@type_names.0, self.tag.tag.tag.@type_names.0] )
}
Payload\Format_A\Format_B\Format_C().trace()   # ['Format_A', 'Format_B', 'Format_C']

Thing := <String, Number>   # anonymous struct -- @.name is nil
n := Named<String, Number>  # bare <...>, no `\` -- Named is undeclared, so this builds a plain named struct instead
n.@name                     # 'Named'

Tree <
    value: Number
    children: Array
    parent: Tree             # a member typed with the struct's own name
>
```

## Enums (not finalized — don't rely on yet)

```tape
Task_Type [
	TODO
	BUG,
	DONE: Priority             # type-annotated -- still Symbol-valued, annotation is metadata only
	CANCELLED: Priority = 99   # type-annotated with an explicit value
	ARCHIVED := 'archived'     # self-declared value, no annotation
]

Task_Type.TODO      # :TODO
Task_Type.keys      # [TODO, BUG, DONE, CANCELLED, ARCHIVED]
Task_Type.count     # 5
```

Enums are syntactically present but not finalized: each member's `: Type` annotation is parsed and stored, but not enforced — nothing raises if a value doesn't match its declared type. The older forced-type spelling (`TYPE_IDENT :: Type { ... }`) no longer exists. Don't rely on Enum type-checking yet.

## Shorthand Nil-Initialization

Trailing comma declares variable as nil if undefined. 

```tape
Type {
	undefined_var,      # equivalent to `undefined_var := nil`	
}

here_too,               # here_too := nil
```

A bare annotated identifier with nothing assigned behaves the same way — no need to write `= nil` just to make an already-self-declaring annotation (`x: Number`, or a struct annotation) actually declare something:

```tape
thing: <String, Number>   # same as thing: <String, Number> = nil
thing                     # nil

x: Number                 # same as x: Number = nil
x                         # nil
```
