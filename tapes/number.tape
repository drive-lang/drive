Number {
	value,

	new ( value;
		self.value = value
	)


	# note; Comparison and arithmetic both run straight on `value`, the wrapped Ruby Numeric, so mixed
	# Integer/Float/Decimal operands behave the way Ruby's own numeric tower does. Integer division
	# stays lossy (`7 / 2` is `3`) -- that's Ruby's `Integer#/`. Kept here as the canonical `@operator`
	@operator <=> @infix ( left: Number, right: Number -> Number;
		left.value <=> right.value
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

	numerator (; @ruby )
	denominator (; @ruby )
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

# The concrete numeric types, mirroring Ruby. Each wraps the matching Ruby class (see
# src/external/ruby/number.rb): an integer literal is an `Integer`, a literal with a fractional part
# is a `Float`, and `Decimal(...)` wraps a BigDecimal. All compose `Number`, so `4 =>= Number` and
# every `Number` method is inherited.
Integer | Number {}
Float | Number {}
Decimal | Number {}

# Short aliases -- Ruby has no equivalent, but the temporal structs (tapes/date.tape etc) and DB
# schema columns lean on the brevity. `Int` is-a `Integer` is-a `Number`.
Int := Integer
Flo := Float
Dec := Decimal
