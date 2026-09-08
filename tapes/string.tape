String {
	value,
	length,     # Total number of characters
	ord,        # Integer ordinal of the first character
	quotation_style: Symbol

	Self ( value := '';
		self.value = value
	)

	to_s (;
		value
	)

	to_string (-> String;
		"'" + value + "'"
	)

	@operator == @infix ( left: String, right;
		# `right: String` isn't runtime-enforced (param types never are, only literal args at the static checker), so this can be called with any `right` -- including `nil` (e.g. `!=` derives from `==` when a type has no `!=` of its own, see interp_infix). `.?value` -- rather than a bare `.value` -- returns nil instead of raising when `right` isn't a String at all.
		left.value == right.?value
	)

	@operator * @infix ( left: String, right: Number;
		result := ""
        for 0 ..< right
            result += left.value
        end
        result
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
	starts_with? ( prefix; start_with?(prefix))
	to_md5_hash (; @ruby )
	trim_left (; @ruby )
	trim_right (; @ruby )
	upcase (; @ruby )
	chars (; @ruby )
	index ( substr; @ruby )
	slice ( start, length; @ruby )
	to_f (; @ruby )
	to_i (; @ruby )
	trim (; @ruby )

	lines (;
		value.split('\n')
	)

	has_all_same_characters? (;
		value.squeeze.length <= 1
	)

	split_by_spaces (; split(' ') )
}

Str := String
