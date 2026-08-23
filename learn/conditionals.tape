### Introduction

`if`/`elif`/`else`/`end` branches on a condition, and the whole thing is an expression -- its last-evaluated branch is its value, so it can be assigned directly.
###
water := 2

mood := if water > 5
	'plenty'
elif water > 0
	'rationing'
else
	'desperate'
end

@assert mood == 'rationing', 'the elif branch should win when water is between 0 and 5'


### unless is negated if

`unless condition` runs its body when `condition` is falsy -- exactly `if !condition` spelled differently for readability.
###
raining := false

shelter_note := unless raining
	'no rush building the shelter'
else
	'get the shelter up now'
end

@assert shelter_note == 'no rush building the shelter', 'unless should run its body when the condition is falsy'


### Inline modifier form

`if` can trail a single statement instead of wrapping it in a block -- reads like a plain sentence.
###
rescued := true
warning := 'someone is coming' if rescued
@assert warning == 'someone is coming', 'inline if should run when the condition is truthy'

found_water := true
note := 'fill the bottles' if found_water
@assert note == 'fill the bottles', 'inline if should run when the condition is truthy'


### Truthiness

`nil`, `false`, `0`, and `0.0` are falsy. Everything else -- empty strings, empty arrays, any instance -- is truthy.
###
describe ( value;
	if value
		'truthy'
	else
		'falsy'
	end
)

@assert describe(nil) == 'falsy', 'nil should be falsy'
@assert describe(false) == 'falsy', 'false should be falsy'
@assert describe(0) == 'truthy', '0 should be truthy like in Ruby'
@assert describe(0.0) == 'truthy', '0.0 should be truthy'
@assert describe('') == 'truthy', 'an empty string should be truthy'
@assert describe([]) == 'truthy', 'an empty array should be truthy'
