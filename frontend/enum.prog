Enum {
	@operator == @infix ( left, right;
		left.@keys == right.@keys and left.@values == right.@values and left.@types == right.@types
	)

	to_s (;
		str := "`self.@name or self.@type` [ "
		for self.@keys
			str += "`it` "
		end
		str += ']'
	)
}
