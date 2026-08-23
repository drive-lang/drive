### skip: continue to the next iteration

`skip` abandons the rest of the current iteration's body and moves straight to the next one, like `continue` in other languages. Kate is sorting the plane wreckage, skipping anything that isn't a suitcase:
###
wreckage := ['suitcase', 'seat', 'suitcase', 'engine', 'suitcase']
suitcases := []
for wreckage
	skip if it != 'suitcase'
	suitcases.push(it)
end
@assert suitcases == ['suitcase', 'suitcase', 'suitcase'], 'skip should abandon the rest of the body for non-matching iterations'


### stop: exit the loop entirely

`stop` breaks out of the loop immediately, like `break`. Sawyer keeps stacking firewood until he's got enough for the signal fire:
###
firewood := [1, 1, 1, 1, 1, 1]
logs_used := 0
for firewood
	stop if logs_used == 4
	logs_used += 1
end
@assert logs_used == 4, 'stop should exit the loop as soon as the condition is met'


### return propagates through loops

`return` exits the enclosing FUNCTION, not just the loop -- it keeps unwinding even from inside a `for`, `while`, or `until` body, because that body is still part of the same function. Searching the camp for Vincent the dog:
###
find_vincent ( survivors;
	for survivors
		return it if it == 'Vincent'
	end
	nil
)

@assert find_vincent(['Jack', 'Kate', 'Vincent', 'Sawyer']) == 'Vincent', 'return inside a for loop should exit the enclosing function'
@assert find_vincent(['Jack', 'Kate']) == nil, 'falling through the loop without a match should return the trailing nil'


### ...but not through a callback passed to another function

`return` only ever exits the function it's lexically written in -- a `(; ... )` passed as an argument (like `.each`'s callback) is a DIFFERENT function, not part of `find_vincent` at all. When it hits `return`, it returns from itself; `each` (which just called it like any other function) never finds out, and `find_vincent` falls through to its own trailing `nil`. Same reason Python's `return` inside a lambda passed to `map` doesn't return from the caller either -- a passed-in function is still its own function, no matter who calls it or from where.
###
find_vincent_via_each ( survivors;
	survivors.each((it;
		return it if it == 'Vincent'   # only exits this anonymous function
	))
	nil
)

@assert find_vincent_via_each(['Jack', 'Kate', 'Vincent', 'Sawyer']) == nil, "return inside a callback shouldn't reach past it -- not Vincent!"
