### Introduction

A named function is registered in its own enclosing scope the moment it's declared -- so its body can refer to its own name and call itself, even though the declaration hasn't finished being written yet.
###
factorial ( n;
	if n <= 1
		1
	else
		n * factorial(n - 1)
	end
)

@assert factorial(5) == 120, 'a named function should be able to call itself'


### Two functions can call each other

The same registration lets sibling functions call one another, in either direction, as long as both are declared in the same enclosing scope by the time either is actually called.
###
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

@assert is_even(10) == true, 'mutually recursive functions should be able to call each other'
@assert is_odd(7) == true, 'mutually recursive functions should be able to call each other'
