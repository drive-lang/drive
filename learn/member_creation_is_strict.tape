### Introduction

A member has to be declared inside a type's own body before anything outside can write to it. Plain `.` access from the outside can never create a new member -- it can only read or write one that already exists:
###
Castaway {
	name := 'unknown'
}

survivor := Castaway()
survivor.name = 'Jack'      # fine -- name already exists
@assert survivor.name == 'Jack', 'writing to an existing member should work'

# survivor.number = 4       -- raises Tape::Cannot_Assign_Undeclared_Identifier, number was never declared


### Self-declaring with self is legitimate -- but only during construction

`self.member := value` inside a type's own method self-declares a brand new member, same as writing `member := value` in the class body directly. That's allowed in the class body itself and inside `new(;)` (and anything `new(;)` calls) -- while the instance is still being built. (`self` is keyword sugar for the `./` scope operator -- see learn/types.tape.)
###
Raft {
	new (; self.planks := 6 )
}

r := Raft()
@assert r.planks == 6, 'self.planks should be self-declared during construction'


### A later method can't grow the instance's shape

Once construction finishes, self-declaring a brand new member the same way -- from some OTHER method, called after `new(;)` has already returned -- raises the same error external `.` access would. An instance's shape is locked in once it's built:
###
Raft2 {
	new (; self.planks := 6 )

	add_sail (;
		self.sail := true   # too late -- construction already finished so self.sail cannot be declared here
	)
}

r2 := Raft2()
# r2.add_sail() would raise Tape::Cannot_Assign_Undeclared_Identifier
@assert r2.planks == 6, 'the member declared during construction is still fine to use'
