Array {
	values, # is the internal backing array

	new ( values := [];
		self.values = values
	)

	# add to back/end
	push ( item; @ruby )
	append := push
	add_one_item_to_end := push
	add_one_item_to_back := push
	enqueue := push

	# add to front
	prepend ( item; @ruby )
	unshift := prepend
	add_one_item_to_front := prepend

	# remove from back/end
	pop (; @ruby )
	remove_one_item_from_end := pop
	remove_one_item_from_back := pop

	# remove_from_front
	shift (; @ruby )
	dequeue := shift
	drop_first := shift
	remove_one_item_from_front := shift

	# get one random item
	random (; @ruby )
	length (; @ruby )
	first ( count := 1; @ruby )
	last ( count := 1; @ruby )
	slice ( from, to; @ruby )
	reverse (; @ruby )
	join ( separator; @ruby )
	concat ( other; @ruby )
	flatten (; @ruby )
	sort (; @ruby )
	uniq (-> Array; @ruby )
	empty? (; @ruby )
	get ( index; @ruby )
	index ( item; @ruby ) # index of the first matching element, or nil if not found

	find ( func;
		for values
			if func(it)
				return it
			end
		end
		nil
	)

	# note; Implemented in Lost (not @ruby) so `==` goes through the interpreter -- a @ruby proxy would fall through to Ruby's native Array#include?, which uses Ruby's own == and never sees an Lost-level operator overload (e.g. a custom Instance's `@operator ==`)
	include? ( item;
		for values
			if it == item
				return true
			end
		end
		false
	)

	any? ( func;
		for values
			if func(it)
				return true
			end
		end
		false
	)

	all? ( func;
		for values
			if !func(it)
				return false
			end
		end
		true
	)

	map ( func;
		result := []
		for values
			result.push(func(it, at))
		end
		result
	)

	filter ( func;
		result := []
		for values
			if func(it)
				result.push(it)
			end
		end
		result
	)

	accumulate ( initial_value, func;
		accumulator := initial_value
		for values
			accumulator = func(accumulator, it)
		end
		accumulator
	)

	each ( func;
		for values
			func(it)
		end
	)

	to_s (;
		pieces := values.map((it; if it === String
			it.pretty_print()
		else
			"`it`"
		end ))
		"[`pieces.join(', ')`]"
	)

	@operator << @infix 600 ( left, right;
		left.append(right)
		right
	)

	# note; Implemented in Lost, same reason as include? above the the Ruby-level Array#== (array.rb)compares elements with Ruby's own native == via the underlying Ruby array, and never sees an Lost-level `@operator ==` overload on a custom Instance (e.g. two structurally-equal Members compared unequal). Declaring this here takes precedence over that Ruby fallback(an operand's own declarations are always checked before it -- see #find_operator_overload).
	@operator == @infix ( left, right;
		if !right or left.length() != right.length()
			return false
		end

		for left.values
			unless it == right.get(at)
				return false
			end
		end

		true
	)
}
