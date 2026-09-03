### Introduction

A constant's name must be UPPERCASE, and once declared it can never be reassigned -- attempting to `=` a new value onto it raises `Tape::Cannot_Reassign_Constant`.
###
TOTAL_SURVIVORS := 48
FLIGHT_NUMBER := 815
@assert "survivors: `TOTAL_SURVIVORS`" == "survivors: 48"
@assert "flight: `FLIGHT_NUMBER`" == "flight: 815"

# TOTAL_SURVIVORS = 47  -- raises Tape::Cannot_Reassign_Constant


### The rule applies to any declaration form
The same protection holds whether the constant was declared with `:=` or `: Type =` -- what matters is that the identifier itself is UPPERCASE, not how it was declared.
###
MAX_RAFT_CAPACITY: Number = 4

@assert MAX_RAFT_CAPACITY === Integer  # exact type: an integer literal is an Integer
@assert MAX_RAFT_CAPACITY =>= Number   # ...which composes Number, so it's-a Number
@assert MAX_RAFT_CAPACITY == 4

# MAX_RAFT_CAPACITY = 6  -- raises Tape::Cannot_Reassign_Constant
