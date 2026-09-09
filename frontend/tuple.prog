Tuple {
	values,

	to_s (;
		pieces := values.map((it; if it === String
			it.to_string()
		else
			"`it`"
		end ))
		"(`pieces.join(', ')`)"
	)
}
