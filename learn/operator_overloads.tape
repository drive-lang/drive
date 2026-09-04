### Introduction

`@operator` declares a custom operator: a symbol, a fixity (`@infix`/`@prefix`/`@postfix`), a precedence number, and a function body. Overloads are stored as regular functions in whatever scope declares them -- so one declared inside a function only exists for the duration of that call, and never leaks out:
###
scoped := compute (;
	@operator + @infix 700 ( left, right;
		left * right
	)
	3 + 4
)

@assert 3 + 4 == 7, '+ should still mean addition everywhere else'
@assert scoped() == 12, '+ should mean multiplication only inside compute'


### Building a pipeline operator

`@infix` takes a left and right operand. Charlie feeds a value through a chain of functions, left to right, each one receiving what came before it:
###
@operator -> @infix 300 ( left, right;
	right(left)
)

double ( n; n * 2 )
add_fifteen ( n; n + 15 )

piped := 4 -> double -> add_fifteen
@assert piped == 23, 'the pipeline operator should chain left to right'


### Inventing new literal-like syntax

`@infix` and `@postfix` can combine to make something that reads like a brand new literal. Here `:` builds a `Clock` from two numbers, and `pm` tags it afterward:
###
Clock { hour, minute, period, }

@operator : @infix 700 ( hour, minute;
	t := Clock()
	t.hour = hour
	t.minute = minute
	t
)

@operator pm @postfix 600 ( left: Clock;
	left.period = 'pm'
	left
)

t := 11:22pm
@assert t.hour == 11 && t.minute == 22 && t.period == 'pm', 'the combined infix/postfix operators should build a Clock and tag it'


### Prefix operators

`@prefix` takes just a right operand -- here `$` builds a `Currency` straight out of a bare number, reading like a literal.
###
Currency { amount, name, code, }

@operator $ @prefix 900 ( amount;
	c := Currency()
	c.amount = amount
	c.name = 'US Dollar'
	c.code = 'USD'
	c
)

price := $42
@assert price.name == 'US Dollar' && price.code == 'USD' && price.amount == 42, '$ should build a Currency straight from a bare number'


### A type's own overload wins over a global one

Dispatch checks the left operand's own declarations first, before falling back to whatever's in scope -- so a type can override an operator for just its own instances without disturbing the global meaning everywhere else:
###
@operator ~> @infix 300 ( left, right; 999 )

Wrapped {
	val,
	Self ( v; self.val = v )
	@operator ~> @infix 300 ( left, right; left.val )
}

a := Wrapped(42)
wrapped_result := a ~> 1
global_result  := 5 ~> 1
@assert wrapped_result == 42, "Wrapped's own ~> should win over the global one"
@assert global_result == 999, 'everything else should still get the global ~>'
