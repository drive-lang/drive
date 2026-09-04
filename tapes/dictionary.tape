Dictionary {
	hash,

	Self ( hash := {};
		self.hash = hash
	)

	keys (; @ruby )
	values (; @ruby )
	has_key? ( key; @ruby )
	delete ( key; @ruby )
	merge ( other; @ruby )
	count (; @ruby )
	empty? (; @ruby )
	clear (; @ruby )
	fetch ( key, default; @ruby )

	to_s (;
		ks     := keys()
		vs     := values()
		pieces := ks.map(( key, at;
			v := vs.get(at)
			displayed := if v === String
				v.pretty_print()
			else
				"`v`"
			end
			"`key`: `displayed`"
		))
		"{`pieces.join(', ')`}"
	)
}
