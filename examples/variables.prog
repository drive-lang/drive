### Introduction

A variable's name must start with a lowercase letter or `_`, and may optionally end with `?` or `!` -- everything else about it is left to context, not punctuation. Capitalized names are reserved for types, UPPERCASE for constants, so lowercase is what's left for ordinary variables and functions.
###
survivors := 4
_headcount := 4
rescued? := false
signal_fire! := true

@assert survivors == 4
@assert _headcount == 4
@assert rescued? == false
@assert signal_fire! == true


### Inferred declaration: :=

`:=` declares a variable and infers its type from whatever's on the right -- no annotation needed, the value speaks for itself.
###
castaways := 48
island_name := 'The Island'

@assert castaways == 48
@assert island_name == "The Island"


### Annotated declaration: : Type =

`: Type =` declares a variable with an explicit type instead of leaving it to inference -- useful as documentation, or when the value alone doesn't make the intent obvious.
###
days_stranded: Number = 1
distress_code: String = 'mayday'

@assert days_stranded == 1
@assert distress_code == 'mayday'
