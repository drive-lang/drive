require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class Parser_Test < Base_Test
	def test_identifiers
		zipped = %w(variable_or_function CONSTANT Type).zip %I(identifier IDENTIFIER Identifier)
		zipped.each do |code, type|
			out = Lost.parse code
			assert_kind_of Lost::Identifier_Expr, out.first
			assert_equal code, out.first.value
			assert_nil out.first.type
		end
	end

	def test_integers_and_floats
		out = Lost.parse '4'
		assert_kind_of Lost::Number_Expr, out.first
		assert_equal 4, out.first.value
		assert_equal :integer, out.first.type

		out = Lost.parse '2.3'
		assert_kind_of Lost::Number_Expr, out.first
		assert_equal 2.3, out.first.value
		assert_equal :float, out.first.type
	end

	def test_numbers_with_prefixes
		out = Lost.parse '-42'
		assert_kind_of Lost::Number_Expr, out.first
		assert_equal -42, out.first.value

		out = Lost.parse '+4.2'
		assert_kind_of Lost::Prefix_Expr, out.first
		assert_equal '+', out.first.operator.value
		assert_equal 4.2, out.first.expression.value
		assert_kind_of Lost::Number_Expr, out.first.expression
	end

	def test_numbers_with_underscores
		out = Lost.parse '2_000'
		assert_equal 1, out.count
		assert_kind_of Lost::Number_Expr, out.first
		assert_equal 2000, out.first.value

		out = Lost.parse '3_0_'
		assert_equal 2, out.count
		assert_kind_of Lost::Number_Expr, out.first
		assert_equal 30, out.first.value
		assert_kind_of Lost::Identifier_Expr, out.last
		assert_equal '_', out.last.value

		out = Lost.parse '_2_00'
		assert_equal 1, out.count
		refute_kind_of Lost::Number_Expr, out.first
		refute_equal 200, out.first.value

		out = Lost.parse '-20three'
		assert_equal 2, out.count
		assert_kind_of Lost::Number_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.last
		assert_equal -20, out.first.value
		assert_equal 'three', out.last.value

		out = Lost.parse '40_two'
		assert_equal 2, out.count
		assert_kind_of Lost::Number_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.last
		assert_equal 40, out.first.value
		assert_equal '_two', out.last.value

		out = Lost.parse '4__5__2__2'
		assert_equal 2, out.count
		assert_kind_of Lost::Number_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.last
		assert_equal 4, out.first.value
		assert_equal '__5__2__2', out.last.value

		out = Lost.parse 'a1234'
		assert_equal 1, out.count
		assert_kind_of Lost::Identifier_Expr, out.first
		assert_equal 'a1234', out.first.value
		refute out.first.type
	end

	def test_strings
		out = Lost.parse '"A string"'
		assert_kind_of Lost::String_Expr, out.first
		refute out.first.interpolated

		out = Lost.parse "'Another string'"
		assert_kind_of Lost::String_Expr, out.first
		refute out.first.interpolated

		out = Lost.parse '"An `interpolated` string"'
		assert_kind_of Lost::String_Expr, out.first
		assert out.first.interpolated

		out = Lost.parse "'Another `interpolated` string'"
		assert_kind_of Lost::String_Expr, out.first
		assert out.first.interpolated
	end

	def test_compound_assignments
		out = Lost.parse 'numbers += 1623'
		refute_kind_of Lost::Identifier_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 1, out.count

		out = Lost.parse 'numbers -= 1623'
		assert_kind_of Lost::Infix_Expr, out.first

		out = Lost.parse 'flag |= 2'
		assert_kind_of Lost::Infix_Expr, out.first
	end

	def test_operator_precedence
		out = Lost.parse '1 + 2 * 3 / 4 - 5 % 6'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.left
		assert_kind_of Lost::Number_Expr, out.first.left.left
		assert_equal 1, out.first.left.left.value
		assert_equal '+', out.first.left.operator.value
		assert_kind_of Lost::Infix_Expr, out.first.left.right
		assert_kind_of Lost::Infix_Expr, out.first.left.right.left
		assert_kind_of Lost::Number_Expr, out.first.left.right.left.left
		assert_equal 2, out.first.left.right.left.left.value
		assert_kind_of Lost::Number_Expr, out.first.left.right.left.right
		assert_equal 3, out.first.left.right.left.right.value
		assert_equal '/', out.first.left.right.operator.value
		assert_kind_of Lost::Number_Expr, out.first.left.right.right
		assert_equal 4, out.first.left.right.right.value
		assert_equal '-', out.first.operator.value
		assert_kind_of Lost::Infix_Expr, out.first.right
		assert_kind_of Lost::Number_Expr, out.first.right.left
		assert_equal 5, out.first.right.left.value
		assert_equal '%', out.first.right.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right.right
		assert_equal 6, out.first.right.right.value
	end

	def test_operator_precedence_with_parentheses
		out = Lost.parse '1 + ((2*3) / 4) - (5 % 6)'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.left
		assert_equal '+', out.first.left.operator.value
		assert_kind_of Lost::Number_Expr, out.first.left.left
		assert_equal 1, out.first.left.left.value
		assert_kind_of Lost::Circumfix_Expr, out.first.left.right
		assert_kind_of Lost::Infix_Expr, out.first.left.right.expressions.first
		assert_equal '/', out.first.left.right.expressions.first.operator.value
		assert_kind_of Lost::Circumfix_Expr, out.first.left.right.expressions.first.left
		assert_equal 2, out.first.left.right.expressions.first.left.expressions.first.left.value
		assert_equal '*', out.first.left.right.expressions.first.left.expressions.first.operator.value
		assert_equal 3, out.first.left.right.expressions.first.left.expressions.first.right.value
		assert_kind_of Lost::Number_Expr, out.first.left.right.expressions.first.right
		assert_equal 4, out.first.left.right.expressions.first.right.value
		assert_equal '-', out.first.operator.value
		assert_kind_of Lost::Circumfix_Expr, out.first.right
		assert_kind_of Lost::Number_Expr, out.first.right.expressions.first.left
		assert_equal 5, out.first.right.expressions.first.left.value
		assert_equal '%', out.first.right.expressions.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right.expressions.first.right
		assert_equal 6, out.first.right.expressions.first.right.value
	end

	def test_other
		out = Lost.parse 'numbers := 4815'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 1, out.count

		out = Lost.parse 'numbers,'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.left
		assert_equal '=', out.first.operator.value

		out = Lost.parse 'Type := {}'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.left
		assert_kind_of Lost::Circumfix_Expr, out.first.right
		assert_equal 1, out.count

		out = Lost.parse 'time: Float'
		assert_equal 'Float', out.first.type.value

		out = Lost.parse 'num: Int = 1 + 2'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.right
		assert_equal 'Int', out.first.left.type.value
	end

	def test_more_fixities
		out = Lost.parse '1 + 2 * 3 / 4'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '1 < 2'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '2 >= 1'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '1 != 2'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '1 == 2'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '1 < 2, 4 > 3'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.last
		assert_equal 2, out.count
	end

	def test_ranges
		out = Lost.parse '1...2'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Number_Expr, out.first.left
		assert_equal '...', out.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 1, out.first.left.value
		assert_equal 2, out.first.right.value

		out = Lost.parse '3.0...4.0'
		assert_kind_of Lost::Number_Expr, out.first.left
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal '...', out.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 3.0, out.first.left.value
		assert_equal 4.0, out.first.right.value

		out = Lost.parse '3..<4'
		assert_kind_of Lost::Number_Expr, out.first.left
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal '..<', out.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 3, out.first.left.value
		assert_equal 4, out.first.right.value

		out = Lost.parse '5>..6'
		assert_kind_of Lost::Number_Expr, out.first.left
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal '>..', out.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 5, out.first.left.value
		assert_equal 6, out.first.right.value

		out = Lost.parse '7>.<8'
		assert_kind_of Lost::Number_Expr, out.first.left
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal '>.<', out.first.operator.value
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 7, out.first.left.value
		assert_equal 8, out.first.right.value

		out = Lost.parse '1...2, 3..<4, 5>..6, 7>.<8'
		assert_equal 4, out.count
		out.each do
			assert_kind_of Lost::Infix_Expr, it
			assert_kind_of Lost::Number_Expr, it.left
			assert_kind_of Lost::Number_Expr, it.right
		end
	end

	def test_comma_separated_expressions
		out = Lost.parse 'a, B, 5, "cool"'
		assert_equal 4, out.count
		assert_kind_of Lost::Infix_Expr, out[0]
		assert_kind_of Lost::Infix_Expr, out[1]
		assert_kind_of Lost::Number_Expr, out[2]
		assert_kind_of Lost::String_Expr, out[3]
	end

	def test_scope_operators
		out = Lost.parse './this_instance'
		assert_kind_of Lost::Identifier_Expr, out.first
		assert_equal './', out.first.scope_operator.value

		out = Lost.parse '~/global_scope'
		assert_kind_of Lost::Identifier_Expr, out.first
		assert_equal '~/', out.first.scope_operator.value
	end

	def test_functions
		out = Lost.parse '(;)'
		assert_kind_of Lost::Func_Expr, out.first
		assert_empty out.first.expressions
		refute out.first.name

		out = Lost.parse '(;
		)'
		assert_empty out.first.expressions
		refute out.first.name

		out = Lost.parse 'named_function (;)'
		assert_equal 'named_function', out.first.name.value
	end

	def test_function_params
		out = Lost.parse '( with_param; )'
		assert_equal 1, out.first.parameters.count
		assert_equal 0, out.first.expressions.count

		out = Lost.parse 'named ( with_param; )'
		assert_equal 'named', out.first.name.value
		assert_equal 1, out.first.parameters.count
		refute out.first.parameters.first.label
		refute out.first.parameters.first.default
		refute out.first.parameters.first.type

		out = Lost.parse '( labeled param; )'
		assert_equal 'labeled', out.first.parameters.first.label.value
		assert out.first.parameters.first.label
		refute out.first.parameters.first.default
		refute out.first.parameters.first.type

		out = Lost.parse '( default_values := 4; )'
		assert out.first.parameters.first.default
		assert_kind_of Lost::Number_Expr, out.first.parameters.first.default

		out = Lost.parse 'named ( and_labeled with_default := 8; )'
		assert_equal 'and_labeled', out.first.parameters.first.label.value
		assert_equal 'with_default', out.first.parameters.first.name.value
		assert_equal 'named', out.first.name.value

		out = Lost.parse 'named ( with, multiple, even labeled := 4, params := 5; )'
		assert_equal 4, out.first.parameters.count
		assert_equal out.first.parameters.map(&:label), [nil, nil, Lost::Lexeme.new(:identifier, 'even'), nil]
		assert_equal out.first.parameters.map(&:name), %w(with multiple labeled params).map { Lost::Lexeme.new(:identifier, _1) }
		assert_equal out.first.parameters.map(&:default).map(&:nil?), [true, true, false, false]
	end

	def test_function_bodies
		out = Lost.parse '
		square ( input;
			input * input
		)'
		refute_empty out.first.expressions
		assert_kind_of Lost::Infix_Expr, out.first.expressions[0]

		out = Lost.parse '
		nothing ( input;
			return input
		)'
		assert_kind_of Lost::Prefix_Expr, out.first.expressions[0]
		assert_kind_of Lost::Identifier_Expr, out.first.expressions[0].expression
	end

	def test_function_signatures
		out = Lost.parse 'nothing ( input;
			return input
		)'
		assert_equal 'nothing(input;)', out.first.signature
	end

	def test_complex_function
		out = Lost.parse '
		curr? ( sequence;
			if not remainder or not lexemes?
				return false
			end

			slice := remainder.slice(0, sequence.count)
			slice.(;
				expected := sequence[at]

				if expected === Array
					expected.any? (;
						it == it2
					)
				else
					it == expected
				end
			)
		)'
		assert_kind_of Lost::Func_Expr, out.first
		assert_equal 'curr?', out.first.name.value
		assert_equal 3, out.first.expressions.count
		assert_equal 1, out.first.parameters.count

		early_return = out.first.expressions[0]
		assert_kind_of Lost::Conditional_Expr, early_return
		assert_kind_of Lost::Infix_Expr, early_return.condition
		assert_equal 'or', early_return.condition.operator.value
		assert_kind_of Lost::Prefix_Expr, early_return.condition.left
		assert_kind_of Lost::Prefix_Expr, early_return.condition.right
		assert_equal 1, early_return.when_true.count # todo One for return and one for false in `return false`. Maybe I should make it a prefix keyword.

		slice = out.first.expressions[1]
		assert_kind_of Lost::Infix_Expr, slice

		tap = out.first.expressions.last
		assert_kind_of Lost::Infix_Expr, tap
		assert_kind_of Lost::Func_Expr, tap.right
		assert_equal 2, tap.right.expressions.count
		assert_kind_of Lost::Infix_Expr, tap.right.expressions.first
		assert_kind_of Lost::Conditional_Expr, tap.right.expressions.last

		conditional = tap.right.expressions.last
		assert_kind_of Lost::Infix_Expr, conditional.condition
		assert_equal '===', conditional.condition.operator.value
		assert_equal 1, conditional.when_true.count # todo I don't think when_true and when_false convey that they return an array
		assert_equal 1, conditional.when_false.count

		any = conditional.when_true.first
		assert_kind_of Lost::Infix_Expr, any
		assert_kind_of Lost::Func_Expr, any.right
		assert_kind_of Lost::Infix_Expr, any.right.expressions.first
		assert_equal 'it', any.right.expressions.first.left.value
		assert_equal 'it2', any.right.expressions.first.right.value
	end

	def test_function_calls
		out = Lost.parse '(;)()'
		assert_kind_of Lost::Call_Expr, out.first
		assert_kind_of Lost::Func_Expr, out.first.receiver
		assert_empty out.first.arguments

		out = Lost.parse '(;)(true)'
		refute_empty out.first.arguments
		assert_kind_of Lost::Identifier_Expr, out.first.arguments.first

		out = Lost.parse '(;)(1, 2, 3)'
		out.first.arguments.each do
			assert_kind_of Lost::Number_Expr, it
		end
	end

	def test_types
		out = Lost.parse 'String {}'
		assert_kind_of Lost::Type_Expr, out.first
		assert_equal 'String', out.first.name

		out = Lost.parse 'Transform {
			position,
			rotation,
		}'
		assert_equal 2, out.first.expressions.count

		out = Lost.parse 'Entity {
			|Transform
		}'
		assert_kind_of Lost::Composition_Expr, out.first.expressions.first
		assert_equal '|', out.first.expressions.first.operator.value
		assert_equal 'Transform', out.first.expressions.first.identifier.value
	end

	def test_mixed_inline_compositions
		out = Lost.parse 'Xform | Transform ~ Vec2 & This ^ That {}'
		assert_kind_of Lost::Composition_Expr, out.first.expressions.first
		assert_equal '|', out.first.expressions[0].operator.value
		assert_equal 'Transform', out.first.expressions[0].identifier.value
		assert_equal '~', out.first.expressions[1].operator.value
		assert_equal 'Vec2', out.first.expressions[1].identifier.value
		assert_equal '&', out.first.expressions[2].operator.value
		assert_equal 'This', out.first.expressions[2].identifier.value
		assert_equal '^', out.first.expressions[3].operator.value
		assert_equal 'That', out.first.expressions[3].identifier.value
	end

	def test_control_flows
		out = Lost.parse 'if true
			celebrate()
		end'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Call_Expr, out.first.when_true.first

		out = Lost.parse 'wrap ( number, limit;
			if number > limit
				number = 0
			end
		 )'
		assert_kind_of Lost::Conditional_Expr, out.first.expressions[0]

		out = Lost.parse 'if 1 + 2 * 3 == 7
			"This one!"
		elif 1 + 2 * 3 == 9
			\'No, this one!\'
		else
			\'🤯\'
		end'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Conditional_Expr, out.first.when_false
		assert_kind_of Lost::String_Expr, out.first.when_false.when_false.first
	end

	def test_conditionals_at_end_of_line
		out = Lost.parse 'eat while lexemes? && curr?()'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.condition
		assert_kind_of Lost::Identifier_Expr, out.first.when_true.first
	end

	def test_unless_conditional
		out = Lost.parse 'do_this unless the_condition'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.condition
		assert_equal 'unless', out.first.type.value
		assert_equal 'the_condition', out.first.condition.value
		assert_kind_of Lost::Identifier_Expr, out.first.when_true.first
		assert_equal 'do_this', out.first.when_true.first.value
	end

	def test_until_conditional
		out = Lost.parse 'repeat_this until the_condition'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.condition
		assert_equal 'until', out.first.type.value
		assert_equal 'the_condition', out.first.condition.value
		assert_kind_of Lost::Identifier_Expr, out.first.when_true.first
		assert_equal 'repeat_this', out.first.when_true.first.value
	end

	def test_silly_elwhile
		out        = Lost.parse '
		while a
			1
		elwhile b
			2
		elwhile c
			3
		else
			4
		end
		'
		while_case = out.first
		assert_kind_of Lost::Conditional_Expr, while_case
		assert_equal 'while', while_case.type.value
		assert_kind_of Lost::Number_Expr, while_case.when_true.first
		assert_equal 1, while_case.when_true.first.value
		assert_kind_of Lost::Conditional_Expr, while_case.when_false

		elwhile = while_case.when_false
		assert_equal 'elwhile', elwhile.type.value
		assert_kind_of Lost::Number_Expr, elwhile.when_true.first
		assert_equal 2, elwhile.when_true.first.value
		assert_kind_of Lost::Conditional_Expr, elwhile.when_false

		elwhile = elwhile.when_false
		assert_equal 'elwhile', elwhile.type.value
		assert_kind_of Lost::Number_Expr, elwhile.when_true.first
		assert_equal 3, elwhile.when_true.first.value
		assert_kind_of Lost::Number_Expr, elwhile.when_false.first
		assert_equal 4, elwhile.when_false.first.value
	end

	def test_if_else
		# Direct copy-past from test_silly_elwhile
		out = Lost.parse '
		if a
			1
		elif b
			2
		elif c
			3
		else
			4
		end
		'

		# elif elif else
		if_case = out.first
		assert_kind_of Lost::Conditional_Expr, if_case
		assert_equal 'if', if_case.type.value
		assert_kind_of Lost::Number_Expr, if_case.when_true.first
		assert_equal 1, if_case.when_true.first.value
		assert_kind_of Lost::Conditional_Expr, if_case.when_false

		elif_case = if_case.when_false
		assert_equal 'elif', elif_case.type.value
		assert_kind_of Lost::Number_Expr, elif_case.when_true.first
		assert_equal 2, elif_case.when_true.first.value
		assert_kind_of Lost::Conditional_Expr, elif_case.when_false

		elif_case = elif_case.when_false
		assert_equal 'elif', elif_case.type.value
		assert_kind_of Lost::Number_Expr, elif_case.when_true.first
		assert_equal 3, elif_case.when_true.first.value
		assert_kind_of Lost::Number_Expr, elif_case.when_false.first
		assert_equal 4, elif_case.when_false.first.value
	end

	def test_circumfixes
		out = Lost.parse '[], (), {}'
		assert_equal 3, out.count
		out.each do |it|
			assert_kind_of Lost::Circumfix_Expr, it
			assert_empty it.expressions
		end

		out = Lost.parse '[1, 2, 3]'
		assert_equal 3, out.first.expressions.count
	end

	def test_type_init
		out = Lost.parse 'Type()'
		assert_kind_of Lost::Call_Expr, out.first
	end

	def test_func_call
		out = Lost.parse 'funk()'
		assert_kind_of Lost::Call_Expr, out.first
	end

	def test_call_expr_improvement
		out = Lost.parse 'Some.thing(1)'
		assert_kind_of Lost::Call_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.receiver
		assert_kind_of Lost::Number_Expr, out.first.arguments.first
	end

	def test_return_is_an_identifier
		out = Lost.parse 'return 1 + 2'
		assert_kind_of Lost::Prefix_Expr, out.first
	end

	def test_return_with_conditional_at_end_of_line
		out = Lost.parse 'return x unless y'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Prefix_Expr, out.first.when_true.first
		assert_kind_of Lost::Identifier_Expr, out.first.when_true.first.expression
		assert_kind_of Lost::Identifier_Expr, out.first.condition
	end

	def test_return_with_conditionals
		out = Lost.parse 'return 3 if true'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Prefix_Expr, out.first.when_true.first
		assert_kind_of Lost::Number_Expr, out.first.when_true.first.expression
		assert_kind_of Lost::Identifier_Expr, out.first.condition
	end

	def test_identifier_dot_integer_is_an_infix
		out = Lost.parse 'something.4'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.left
		assert_kind_of Lost::Number_Expr, out.first.right
		assert_equal 4, out.first.right.value
	end

	def test_identifier_dot_float_is_an_infix
		out = Lost.parse 'not_gonna_work.4.8.15'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Identifier_Expr, out.first.left
		assert_kind_of Lost::Array_Index_Expr, out.first.right
		assert_equal '4.8.15', out.first.right.value
		assert_equal [4, 8, 15], out.first.right.indices_in_order
	end

	def test_multidot_number_lexeme
		out = Lost.parse '4.8.15.16.23.42'
		assert_kind_of Lost::Array_Index_Expr, out.first
		assert_equal '4.8.15.16.23.42', out.first.value
		assert_equal [4, 8, 15, 16, 23, 42], out.first.indices_in_order
	end

	def test_complex_return_with_conditionals
		out = Lost.parse 'return 4+2 if true'
		assert_kind_of Lost::Conditional_Expr, out.first
		assert_kind_of Lost::Prefix_Expr, out.first.when_true.first
		assert_kind_of Lost::Infix_Expr, out.first.when_true.first.expression
		assert_kind_of Lost::Identifier_Expr, out.first.condition
	end

	def test_possibly_ambigous_type_and_func_syntax_mixture
		out = Lost.parse 'x , y , z'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out[1]
		assert_kind_of Lost::Identifier_Expr, out.last

		out = Lost.parse 'x , y , z'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out[1]
		assert_kind_of Lost::Identifier_Expr, out.last
	end

	def test_function_signature
		out = Lost.parse '(-> Identifier;)'
		assert_kind_of Lost::Func_Signature_Expr, out.first

		out = Lost.parse '(Number -> String;)'
		assert_kind_of Lost::Func_Signature_Expr, out.first

		out = Lost.parse 'string (number;)'
		assert_kind_of Lost::Func_Expr, out.first
	end

	def test_double_less_than_is_operator
		out = Lost.parse '<<'
		assert_kind_of Lost::Operator_Expr, out.first
	end

	def test_writable_unpack_prefix
		out = Lost.parse 'funk ( @writable with; )'
		assert_equal 'with', out.first.parameters.first.value
		assert_kind_of Lost::Param_Expr, out.first.parameters.first
		assert out.first.parameters.first.add_to_writable
		refute out.first.parameters.first.add_to_readable
	end

	def test_readable_unpack_prefix
		out = Lost.parse 'funk ( @readable with; )'
		assert_equal 'with', out.first.parameters.first.value
		assert_kind_of Lost::Param_Expr, out.first.parameters.first
		assert out.first.parameters.first.add_to_readable
		refute out.first.parameters.first.add_to_writable
	end

	def test_for_loops
		out = Lost.parse '
		for []
		end'
		assert_empty out.first.body
		assert_instance_of Lost::Circumfix_Expr, out.first.collection # note, The iterable becomes an Array in the interpreter.
		assert_equal '[]', out.first.collection.grouping
	end

	def test_directive_identifier
		out = Lost.parse '@whatever'
		refute_instance_of Lost::Directive_Expr, out.first

		out = Lost.parse '@whatever(a, b)'
		assert_instance_of Lost::Directive_Expr, out.first
		assert_instance_of Lost::Identifier_Expr, out.first.name
		assert_instance_of Lost::Circumfix_Expr, out.first.expression
	end

	def test_all_http_methods
		Lost::HTTP_VERBS.each do |verb|
			assert_instance_of Lost::Route_Expr, Lost.parse("#{verb}://path (;)").first
		end
	end

	def test_route_declaration_with_http_method_directives
		refute_raises Lost::Invalid_Http_Directive_Handler do
			out = Lost.parse 'get://something (;)'
			assert_equal 1, out.count
			assert_instance_of Lost::Route_Expr, out.first
			assert_equal 'get', out.first.http_method.value
			assert_equal "something", out.first.path
		end

		out = Lost.parse '@whatever "endpoint" (;)'
		assert_equal 2, out.count
		refute_instance_of Lost::Route_Expr, out.first
		assert_instance_of Lost::Directive_Expr, out[0]
		assert_instance_of Lost::Func_Expr, out[1]
	end

	def test_empty_html_element_expression
		out = Lost.parse '```html
		```'
		assert_equal 1, out.count

		assert_instance_of Lost::Html_Fence_Expr, out.first
	end

	def test_skip_and_stop_are_operators
		out = Lost.parse 'skip'
		assert_instance_of Lost::Operator_Expr, out.first

		out = Lost.parse 'stop'
		assert_instance_of Lost::Operator_Expr, out.first
	end

	def test_single_line_comments
		out = Lost.parse '# abc'
		assert_instance_of Lost::Comment_Expr, out.first

		out = Lost.parse '# abc
		# def'
		assert_instance_of Lost::Comment_Expr, out.first
		assert_instance_of Lost::Comment_Expr, out.last
		assert out.first != out.last
	end

	def test_block_comments
		out = Lost.parse '###abc###'
		assert_instance_of Lost::Comment_Expr, out.first

		out = Lost.parse '###abc
		def###'
		assert_instance_of Lost::Comment_Expr, out.first
		assert_instance_of Lost::Comment_Expr, out.last
		assert out.first == out.last

		out = Lost.parse '###abc### ###def###'
		assert_instance_of Lost::Comment_Expr, out.first
		assert_instance_of Lost::Comment_Expr, out.last
		assert out.first != out.last
	end

	def test_fence_blocks
		out = Lost.parse '```abc```'
		assert_instance_of Lost::Fence_Expr, out.first

		out = Lost.parse '```abc
		def```'
		assert_instance_of Lost::Fence_Expr, out.first
		assert_instance_of Lost::Fence_Expr, out.last
		assert out.first == out.last
	end

	def test_fence_expr_attributes
		out   = Lost.parse '```
		some content here
		```'
		fence = out.first

		assert_instance_of Lost::Fence_Expr, fence
		assert_equal :fence, fence.type
		assert_instance_of Lost::String_Expr, fence.value
		assert fence.value.value.include?('some content here')
	end

	def test_fence_expr_multiline_content
		out   = Lost.parse '```
		line one
		line two
		line three
		```'
		fence = out.first

		assert_instance_of Lost::Fence_Expr, fence
		assert_equal :fence, fence.type
		assert fence.value.value.include?('line one')
		assert fence.value.value.include?('line two')
		assert fence.value.value.include?('line three')
	end

	def test_html_fence_expr_attributes
		out        = Lost.parse '```html
		<div>Hello</div>
		```'
		html_fence = out.first

		assert_instance_of Lost::Html_Fence_Expr, html_fence
		assert_instance_of Lost::String_Expr, html_fence.body
		assert html_fence.body.value.include?('<div>Hello</div>')
		assert_equal html_fence.value, html_fence.body
		refute_nil html_fence.element
	end

	def test_html_fence_expr_with_interpolation
		out        = Lost.parse '```html
		<h1>Welcome `name`</h1>
		```'
		html_fence = out.first

		assert_instance_of Lost::Html_Fence_Expr, html_fence
		assert html_fence.body.value.include?('<h1>Welcome `name`</h1>')
		assert html_fence.body.interpolated
	end

	def test_html_fence_expr_without_interpolation
		out        = Lost.parse '```html
		<p>Plain text</p>
		```'
		html_fence = out.first

		assert_instance_of Lost::Html_Fence_Expr, html_fence
		refute html_fence.body.interpolated
	end

	def test_html_fence_strips_html_marker
		out        = Lost.parse '```html
		<span>Content</span>
		```'
		html_fence = out.first

		assert_instance_of Lost::Html_Fence_Expr, html_fence
		# The 'html' marker should be stripped from body
		refute html_fence.body.value.start_with?('html')
	end

	def test_operator_overload_parses
		assert_raises Lost::Operator_Overload_Fixity_Must_Be_One_Of do
			Lost.parse <<~CODE
			    @operator := @heehee 500 ( left, right; )
			CODE
		end

		assert_raises Lost::Operator_Overload_Precedence_Must_Be_Integer do
			Lost.parse <<~CODE
			    @operator $ @prefix hmm ( left, right; )
			CODE
		end

		assert_raises Lost::Operator_Overload_Precedence_Must_Be_Integer do
			Lost.parse <<~CODE
			    @operator + @infix notanumber ( left, right; )
			CODE
		end

		out      = Lost.parse '@operator := @infix 500 ( left, right; )'
		overload = out.first
		assert_instance_of Lost::Operator_Overload_Expr, overload
		assert_equal ':=', overload.value
		assert_equal 'infix', overload.fixity.value
		assert_equal 500, overload.precedence
		assert_instance_of Lost::Func_Expr, overload.func_expr

		{ 'infix' => '~~', 'prefix' => '!!', 'postfix' => '??' }.each do |fixity, op|
			refute_raises do
				Lost.parse "@operator #{op} @#{fixity} 300 ( x; x )"
			end
		end

		# Operator is registered so it can appear in a subsequent expression as Infix_Expr
		out   = Lost.parse "@operator ~> @infix 700 ( left, right; left )\na ~> b"
		infix = out.last
		assert_instance_of Lost::Infix_Expr, infix
		assert_equal '~>', infix.operator.value
		assert_equal 'a', infix.left.value
		assert_equal 'b', infix.right.value
	end

	def test_statement_expressions
		out = Lost.parse "`1+2`"
		assert_kind_of Lost::Statement_Expr, out.first
		assert_kind_of Lost::Infix_Expr, out.first.expression
	end

	def test_fancier_statement_example
		out = Lost.parse "x := `@load 'lost/string'`"
		assert_kind_of Lost::Statement_Expr, out.last.right
	end
end
