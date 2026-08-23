@load 'lost/member.tape'

### Valid members syntax:

m := Member()
<Member, mem1: Member, mem2 := Member(), mem3: Member = Member(), m, Member\String>
###

Struct {
	members: Array\Member    = []
	names: Array\String      = []
	type_names: Array\String = []
	values: Array            = []

	has? ( member: Member -> Bool;
		members.include?(member)
	)

	include? ( query;
		members.any?(( it;
			it.name == query or it.type == query
		))
	)

	to_s ( compact := false;
		formatted_members := members.map((it; it.to_s(compact) )).join(', ')
		"<`formatted_members`>"
	)

	# todo; implement set comparison as well
	@operator == @infix ( left, right;
		# `.?members`, not `.members` -- `right` isn't guaranteed to be Struct-shaped (e.g. `!=` derives from `==` when a type has no `!=` of its own, see interp_infix); Array's own `==` (lost/array.tape) already handles a nil right side safely.
		left.members == right.?members
	)

	@operator + @infix ( left, right;
		info := Struct()
		info.members = left.members + right.members
		info
	)
}
