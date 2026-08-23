Number {
	denominator,
	numerator,
	type,

	new ( num;
		self.numerator = num
		self.denominator = 1
	)

	# note; Incomplete: only compares numerator, ignoring denominator entirely (same gap every arithmetic operator on Number already has: +/-/*// etc. below are also numerator-only). denominator is currently vestigial everywhere in Number, always 1, never derived by anything. A real fix would need every operator here to agree on what a Number actually means (a true rational via cross-multiplication for comparison, fraction-preserving arithmetic, or auto-reduce), not just this one. Kept simple on purpose: this is the canonical example of `@operator` usage.
	@operator <=> @infix ( left: Number, right: Number -> Number;
		left.numerator <=> right.numerator
	)

	@operator < @infix ( left: Number, right: Number -> Bool;
		(left <=> right) < 0
	)

	@operator > @infix ( left: Number, right: Number -> Bool;
		(left <=> right) > 0
	)

	@operator <= @infix ( left: Number, right: Number -> Bool;
		(left <=> right) <= 0
	)

	@operator >= @infix ( left: Number, right: Number -> Bool;
		(left <=> right) >= 0
	)

	Self.rand ( max := 1; @ruby )

	clamp ( min, max; @ruby )
	to_s (; @ruby )
	abs (; @ruby )
	floor (; @ruby )
	ceil (; @ruby )
	round (; @ruby )
	sqrt (; @ruby )
	even? (; @ruby )
	odd? (; @ruby )
	to_i (; @ruby )
	to_f (; @ruby )
}

# todo; Int and Flt/Float
Int | Number {}
Float | Number {}
Flt | Number {}
