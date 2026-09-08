require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# tapes/visitor.tape's Warnings_Visitor mixin -- composed into tapes/css.tape's Css_Lint_Visitor and
# tapes/html2.tape's Html_Lint_Visitor. See test/css_test.rb and test/html2_test.rb for those.
class Visitor_Test < Base_Test
	VISITOR = "@load 'tapes/visitor.tape'"

	def test_warn_pushes_onto_warnings
		out = Drive.interp "
		#{VISITOR}
		Thing | Warnings_Visitor {}
		t := Thing()
		t.warn('uh oh')
		t.warnings"
		assert_equal ['uh oh'], out.values
	end

	def test_warn_appends_in_order
		out = Drive.interp "
		#{VISITOR}
		Thing | Warnings_Visitor {}
		t := Thing()
		t.warn('first')
		t.warn('second')
		t.warnings"
		assert_equal ['first', 'second'], out.values
	end

	# Regression coverage for the composition mutable-state-sharing bug (#dup_composed_value,
	# test/composition_test.rb) from the composed side: two different types each composing
	# Warnings_Visitor must not share one `warnings` Array between them.
	def test_warnings_are_independent_across_composing_types
		out = Drive.interp "
		#{VISITOR}
		Thing_A | Warnings_Visitor {}
		Thing_B | Warnings_Visitor {}
		a := Thing_A()
		b := Thing_B()
		a.warn('from a')
		b.warn('from b')
		(a.warnings, b.warnings)"
		assert_equal [['from a'], ['from b']], out.values.map(&:values)
	end

	# Same, but two instances of the *same* composing type.
	def test_warnings_are_independent_across_instances_of_the_same_type
		out = Drive.interp "
		#{VISITOR}
		Thing | Warnings_Visitor {}
		a := Thing()
		b := Thing()
		a.warn('from a')
		(a.warnings, b.warnings)"
		assert_equal [['from a'], []], out.values.map(&:values)
	end
end
