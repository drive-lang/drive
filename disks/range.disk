Range {
	# A numeric range, backed by a Ruby Range (src/external/ruby/range.rb). Built with the range
	# operators, never a literal -- `1...5` (inclusive), `1..<5` (exclusive end), `1>..5` (exclusive
	# start), `1>.<5` (exclusive both).

	# --- bounds ---
	start (-> Number; @ruby )
	finish (-> Number; @ruby )
	excludes_end? (-> Bool; @ruby )

	# --- queries ---
	length (-> Number; @ruby )
	count := length
	size := length
	empty? (-> Bool;
		length() == 0
	)
	include? ( n: Number -> Bool; @ruby )
	covers? := include?
	min (-> Number; @ruby )
	max (-> Number; @ruby )
	sum (-> Number; @ruby )
	values (-> Array; @ruby )   # a fresh Array of every element
	to_a := values

	to_s (; @ruby )

	# --- iteration ---
	each ( func -> Range;
		for self
			func(it)
		end
		self
	)

	map ( func -> Array;
		result := []
		for self
			result.push(func(it))
		end
		result
	)

	filter ( func -> Array;
		result := []
		for self
			if func(it)
				result.push(it)
			end
		end
		result
	)
	select := filter

	reduce ( initial, func;
		acc := initial
		for self
			acc = func(acc, it)
		end
		acc
	)
	accumulate := reduce

	find ( func;
		for self
			if func(it)
				return it
			end
		end
		nil
	)

	any? ( func -> Bool;
		for self
			if func(it)
				return true
			end
		end
		false
	)

	all? ( func -> Bool;
		for self
			if !func(it)
				return false
			end
		end
		true
	)
}
