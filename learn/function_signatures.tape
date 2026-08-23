### Introduction

`(Param -> Type;)` is a signature -- a value describing a function's shape (its param types and return type) with no implementation at all, just the same `-> Type` a real function's own declaration uses.
###
distress_formatter := (Number -> String;) # This is a function signature literal
@assert "`distress_formatter`" == '(Number -> String;)', 'a signature should describe its own shape'


### Self-declaring form

A function itself declares its return type the same way, `-> Type` at the end of its param list before `;`. Naming a signature this way (`name: (Params -> Type;)`) lets a variable be typed as "any function with this shape," rather than typed as one specific function.
###
send_sos ( strength: Number -> String;
	"SOS at strength `strength`"
)

send_flare ( strength: Number -> String;
	"Flare at strength `strength`"
)

radio: (Number -> String;) = send_sos
@assert radio(5) == 'SOS at strength 5', 'radio should dispatch to whichever function it currently holds'

radio = send_flare   # ok -- same shape: (Number) -> String
@assert radio(5) == 'Flare at strength 5', 'reassigning to a same-shaped function should work'


### Assigning checks the shape, not the name

Reassigning a signature-typed identifier checks the actual param/return types of whatever function is assigned -- a mismatched shape raises `Lost::Type_Contract_Violation`, the same runtime contract `:=` itself uses.
###
# radio = (strength; strength)  -- raises Lost::Type_Contract_Violation: wrong shape, no declared types at all
