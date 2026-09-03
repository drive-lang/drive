### Introduction

Numbers mirror Ruby: an integer literal is an `Integer`, a literal with a fractional part is a `Float`,
and both compose `Number` (Ruby's `Numeric`). Each wraps the matching Ruby value in `value`. `abs`
returns the absolute value.
###
days_off_course := -8
@assert days_off_course.abs() == 8, 'abs should return the absolute value'
@assert days_off_course.value == -8, 'value is the wrapped Ruby number itself'


### Integer, Float, Number

`===` checks the exact type; `=>=` checks "is-a" (composes at least).
###
@assert 6 === Integer, 'an integer literal is an Integer'
@assert 2.5 === Float, 'a literal with a decimal point is a Float'
@assert 6 =>= Number, 'every Integer composes Number'
@assert 2.5 =>= Number, 'every Float composes Number'
@assert (6 === Number) == false, '=== is exact -- an Integer is not literally Number'


### numerator, denominator

Straight off the wrapped Ruby number.
###
@assert 6.numerator() == 6, 'a whole number is its own numerator'
@assert 6.denominator() == 1, 'a whole number is over 1'
@assert 2.5.numerator() == 5, 'Float parts come from Ruby to_r: 2.5 is 5/2'
@assert 2.5.denominator() == 2, ''


### floor, ceil, round

###
@assert 4.2.floor() == 4, 'floor should round down'
@assert 4.2.ceil() == 5, 'ceil should round up'
@assert 4.5.round() == 5, 'round should round to nearest'


### sqrt, even?, odd?

###
@assert 16.sqrt() == 4.0, 'sqrt should return the square root'
@assert 108.even?() == true, 'even? should be true for an even number'
@assert 108.odd?() == false, 'odd? should be false for an even number'


### to_s and clamp

`to_s` converts a Number to a String -- note it prints the same either way through `@puts`, since a String's own display is unquoted.
###
@assert 42.to_s() == '42', 'to_s should convert a Number to a String'
@assert 150.clamp(0, 100) == 100, 'clamp should pull a value above the max down to it'
@assert (-5).clamp(0, 100) == 0, 'clamp should push a value below the min up to it'
