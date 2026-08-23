Member {
	name: String
	type: Any
	value: Any

	new ( name: String, value := nil, type := nil;
		self.name  = name
		self.value = value
		self.type  = type
	)

	to_s ( compact := false;
		# A member can genuinely hold `false` as its value (`done := false`), which is falsy in Lost -- same as `nil` under a plain truthy check (`if value`), even though only `nil` actually means "no value was ever set". Every branch below checks presence via `has_value` instead, so a real `false` value still prints as one rather than looking unset.
		has_value := value != nil

		# `.?pretty_print()` -- for an unnamed schema-only member (`<String, Number>`), `value` is the bare String Type object itself, not an actual instance, so a plain `.pretty_print()` would raise Cannot_Call_Instance_Member_On_Type. Falls back to `value` itself (its own to_s -- the type's name) when that's the case.
		displayed_value := if has_value and type.?name == 'String'
			value.?pretty_print() or value
		else
			value
		end

		if compact
			return if name and has_value
				"`name`=`displayed_value`"
			elsif name and not has_value
				name
			elsif has_value
				displayed_value
			end
		end

		if name
			if type and has_value
				"`name`: `type.?display_name` = `displayed_value`"
			elif type and not has_value
				"`name`: `type.?display_name`"
			elif has_value and not type
				"`name` := `displayed_value`"
			else
				"`name`: Any"
			end
		else
			if has_value
				"`displayed_value`"
			elif type
				"`type.?display_name`"
			else
				"Any"
			end
		end
	)

	@operator == @infix ( left: Member, right;
		# `right: Member` isn't runtime-enforced -- `.?name`/`.?type`/`.?value` (rather than bare `.`) keep this from raising when `right` isn't Member-shaped at all (e.g. `!=` derives from `==` when a type has no `!=` of its own, see interp_infix), same fix as lost/string.tape's own `==`.
		left.name == right.?name and left.type == right.?type and left.value == right.?value
	)
}
