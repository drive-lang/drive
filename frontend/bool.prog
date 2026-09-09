Bool {
	truthiness,

	# todo: Think about what else might make a boolean true
	Self ( value := true;
		self.truthiness = value != false and value != nil and value != 0 and value != 0.0
	)

	# note; Not `"`truthiness`"` because interpolating truthiness (a raw Ruby true/false) wouldre-wrap it via maybe_instance back into this exact Bool singleton and call .to_s again,infinitely. Branching avoids ever stringifying truthiness itself.
	# todo;
	to_s (;
		if truthiness
			"true"
		else
			"false"
		end
	)
}
