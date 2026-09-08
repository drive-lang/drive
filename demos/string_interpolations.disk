### Introduction

Backticks inside a string interpolate an expression -- anything from a bare identifier to a full expression -- and splice its value into the string at that point.
###
name := 'Kate'
@assert "Hello, `name`!" == 'Hello, Kate!', 'interpolation should splice a bare identifier into the string'
@assert "2 + 2 = `2 + 2`" == '2 + 2 = 4', 'interpolation should splice the result of an expression'


### Escaping

A backslash before a backtick prevents interpolation, producing a literal backtick in the output instead.
###
@assert "Literal \`backticks\`" == 'Literal \`backticks\`', 'an escaped backtick should produce a literal backtick, not interpolate'


### Any expression works, not just identifiers

Arithmetic, method calls, whatever -- interpolation just evaluates the enclosed expression and converts the result to a string.
###
survivors := 48
@assert "`survivors` survivors, `survivors / 2` per raft" == '48 survivors, 24 per raft', 'interpolation should evaluate any expression, not just identifiers'
