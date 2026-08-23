String {
	value,
	length,     # Total number of characters
	ord,        # Integer ordinal of the first character
	quotation_style: Symbol

	new ( value := '';
		self.value = value
	)

	to_s (;
		value
	)

	# Quoted display, matching quotation_style when this instance was built from a literal (see Interpreter#wrap_string_literal_value); defaults to double quotes otherwise. Deliberately separate from to_s: to_s is used pervasively as a plain string-building primitive via backtick interpolation (Array/Dictionary/Tuple's own to_s do exactly this internally), so quoting inside to_s itself recursively re-quotes every nested interpolation of a String value. pretty_print is only ever called explicitly, never implicitly by interpolation, so it can't recurse that way.
	pretty_print (-> String;
		if quotation_style == :single
			"'" + value + "'"
		else
			'"' + value + '"'
		end
	)

	@operator == @infix ( left: String, right;
		# `right: String` isn't runtime-enforced (param types never are, only literal args at the static checker), so this can be called with any `right` -- including `nil` (e.g. `!=` derives from `==` when a type has no `!=` of its own, see interp_infix). `.?value` -- rather than a bare `.value` -- returns nil instead of raising when `right` isn't a String at all.
		left.value == right.?value
	)

	downcase (; @ruby )
	empty? (; @ruby )
	end_with? ( suffix; @ruby )
	gsub ( pattern, replacement; @ruby )
	include? ( substr; @ruby )
	replace ( new; @ruby )
	reverse (; @ruby )
	split ( delimiter := nil; @ruby )
	start_with? ( prefix; @ruby )
	to_md5_hash (; @ruby )
	trim_left (; @ruby )
	trim_right (; @ruby )
	upcase (; @ruby )
	chars (; @ruby )
	index ( substr; @ruby )
	slice ( substr; @ruby )
	to_f (; @ruby )
	to_i (; @ruby )
	trim (; @ruby )
}
