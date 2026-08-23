### Introduction

A function's name follows the same rule as a variable's -- lowercase or `_` to start. Declaration is `name ( params; body )`: params come before the `;`, the body after. The last expression evaluated is the return value, with no explicit `return` required.
###
add ( a, b;
	a + b
)

@assert add(4, 8) == 12, 'the last expression evaluated should be the return value'


### No parameters

A function with no params still needs the `;` -- it just has nothing before it.
###
greet_camp (;
	'Good morning, castaways!'
)

@assert greet_camp() == 'Good morning, castaways!', 'a param-less function still needs the leading ;'


### Default parameter values

A param can declare its own default with `:=`, used whenever the caller doesn't supply that argument.
###
gather_water ( liters := 1;
	"Gathered `liters` liter(s) of water"
)

@assert gather_water() == 'Gathered 1 liter(s) of water', 'an omitted argument should fall back to its default'
@assert gather_water(5) == 'Gathered 5 liter(s) of water', 'a supplied argument should override the default'


### Early return

`return` exits the function immediately with a value, instead of waiting for the last expression.
###
check_supplies ( count;
	if count == 0
		return 'out of supplies'
	end
	"`count` supplies remaining"
)

@assert check_supplies(0) == 'out of supplies', 'return should exit before the last expression runs'
@assert check_supplies(3) == '3 supplies remaining', 'without return, the last expression is the value'
