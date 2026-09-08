# Tally marks as a Number.
#
#   Tally('||')   is 2
#   Tally('|||||')   is 5
#
# Arithmetic keeps the marks (`Tally + Tally -> Tally`); comparisons and mixing with a plain
# number fall back to the count, because `new` also sets `value` (the Number backing).
#
# Usage;
#   a := Tally('|||')            #  3
#   b := Tally('|')              #  1
#   c := Tally('•') * 8          #  8
#
#   @puts c                      #  "••••••••"
#   @puts a + b                  #  "||||"     (3 + 1)
#   @puts a - b                  #  "||"       (3 - 1)
#   @puts b - a                  #  ""         (1 - 3, floored at 0)
#   @puts a * Tally('||')        #  "||||||"   (3 * 2)
#   @puts a / Tally('||')        #  "|"        (3 / 2, truncated)
#
#   @puts a > b                  #  true
#   @puts a < b                  #  false
#   @puts a == Tally('|||')      #  true
#   @puts a == 3                 #  true       (compares on the count)
#   @puts a != b                 #  true       (derived from ==)
#
#   @puts 10 - a                 #  7          (left isn't a Tally -> plain Number arithmetic on `value`)
#   @puts a.to_i()               #  3
#   @puts a.value                #  3


Tally | Number {
	marks: String

	Self ( marks: String;
		self.marks = marks
		self.value = marks.length
	)

	to_s (; marks )
	to_i (; marks.length )

	# One mark per unit, never a negative run (`'|' * -1` would raise in Ruby).
	Self.of ( count: Number -> Tally;
		safe := unless count > 0
			0
		else
			count.to_i()
		end
		Self(self.marks * safe)
	)

	@operator <=> @infix ( left, right;
		left.to_i() <=> right.to_i()
	)

	@operator == @infix ( left, right;
		left.to_i() == right.to_i()
	)

	@operator + @infix ( left, right;
		Self.of(left.to_i() + right.to_i())
	)

	@operator - @infix ( left, right;
		Self.of(left.to_i() - right.to_i())
	)

	@operator * @infix ( left, right;
		Self.of(left.to_i() * right.to_i())
	)

	@operator / @infix ( left, right;
		Self.of(left.to_i() / right.to_i())
	)
}
