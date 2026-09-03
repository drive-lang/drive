Enum {
	type,
	keys := []
	values := []
	types := []
	count := 0

	@operator == @infix ( left, right;
		left.keys == right.keys and left.values == right.values and left.types == right.types
	)

	to_s (;
		str := "`name || type` [ "
		for keys
			str += "`it` "
		end
		str += ']'
	)
}
