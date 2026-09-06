require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'
require 'timeout'

class Parser_Test < Base_Test
	def test_identifiers
		zipped = %w(variable_or_function CONSTANT Type).zip %I(identifier IDENTIFIER Identifier)
		zipped.each do |code, type|
			out = Tape.parse code
			assert_kind_of Tape::Identifier_Expr, out.first
			assert_equal code, out.first.value
			assert_nil out.first.type
		end
	end

	def test_integers_and_floats
		out = Tape.parse '4'
		assert_kind_of Tape::Number_Expr, out.first
		assert_equal 4, out.first.value
		assert_equal :integer, out.first.type

		out = Tape.parse '2.3'
		assert_kind_of Tape::Number_Expr, out.first
		assert_equal 2.3, out.first.value
		assert_equal :float, out.first.type
	end

	def test_numbers_with_prefixes
		out = Tape.parse '-42'
		assert_kind_of Tape::Number_Expr, out.first
		assert_equal -42, out.first.value

		out = Tape.parse '+4.2'
		assert_kind_of Tape::Prefix_Expr, out.first
		assert_equal '+', out.first.operator.value
		assert_equal 4.2, out.first.expression.value
		assert_kind_of Tape::Number_Expr, out.first.expression
	end

	def test_numbers_with_underscores
		out = Tape.parse '2_000'
		assert_equal 1, out.count
		assert_kind_of Tape::Number_Expr, out.first
		assert_equal 2000, out.first.value

		out = Tape.parse '3_0_'
		assert_equal 2, out.count
		assert_kind_of Tape::Number_Expr, out.first
		assert_equal 30, out.first.value
		assert_kind_of Tape::Identifier_Expr, out.last
		assert_equal '_', out.last.value

		out = Tape.parse '_2_00'
		assert_equal 1, out.count
		refute_kind_of Tape::Number_Expr, out.first
		refute_equal 200, out.first.value

		out = Tape.parse '-20three'
		assert_equal 2, out.count
		assert_kind_of Tape::Number_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.last
		assert_equal -20, out.first.value
		assert_equal 'three', out.last.value

		out = Tape.parse '40_two'
		assert_equal 2, out.count
		assert_kind_of Tape::Number_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.last
		assert_equal 40, out.first.value
		assert_equal '_two', out.last.value

		out = Tape.parse '4__5__2__2'
		assert_equal 2, out.count
		assert_kind_of Tape::Number_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.last
		assert_equal 4, out.first.value
		assert_equal '__5__2__2', out.last.value

		out = Tape.parse 'a1234'
		assert_equal 1, out.count
		assert_kind_of Tape::Identifier_Expr, out.first
		assert_equal 'a1234', out.first.value
		refute out.first.type
	end

	def test_strings
		out = Tape.parse '"A string"'
		assert_kind_of Tape::String_Expr, out.first
		refute out.first.interpolated

		out = Tape.parse "'Another string'"
		assert_kind_of Tape::String_Expr, out.first
		refute out.first.interpolated

		out = Tape.parse '"An `interpolated` string"'
		assert_kind_of Tape::String_Expr, out.first
		assert out.first.interpolated

		out = Tape.parse "'Another `interpolated` string'"
		assert_kind_of Tape::String_Expr, out.first
		assert out.first.interpolated
	end

	def test_compound_assignments
		out = Tape.parse 'numbers += 1623'
		refute_kind_of Tape::Identifier_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 1, out.count

		out = Tape.parse 'numbers -= 1623'
		assert_kind_of Tape::Infix_Expr, out.first

		out = Tape.parse 'flag |= 2'
		assert_kind_of Tape::Infix_Expr, out.first
	end

	def test_operator_precedence
		out = Tape.parse '1 + 2 * 3 / 4 - 5 % 6'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.left
		assert_kind_of Tape::Number_Expr, out.first.left.left
		assert_equal 1, out.first.left.left.value
		assert_equal '+', out.first.left.operator.value
		assert_kind_of Tape::Infix_Expr, out.first.left.right
		assert_kind_of Tape::Infix_Expr, out.first.left.right.left
		assert_kind_of Tape::Number_Expr, out.first.left.right.left.left
		assert_equal 2, out.first.left.right.left.left.value
		assert_kind_of Tape::Number_Expr, out.first.left.right.left.right
		assert_equal 3, out.first.left.right.left.right.value
		assert_equal '/', out.first.left.right.operator.value
		assert_kind_of Tape::Number_Expr, out.first.left.right.right
		assert_equal 4, out.first.left.right.right.value
		assert_equal '-', out.first.operator.value
		assert_kind_of Tape::Infix_Expr, out.first.right
		assert_kind_of Tape::Number_Expr, out.first.right.left
		assert_equal 5, out.first.right.left.value
		assert_equal '%', out.first.right.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right.right
		assert_equal 6, out.first.right.right.value
	end

	def test_operator_precedence_with_parentheses
		out = Tape.parse '1 + ((2*3) / 4) - (5 % 6)'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.left
		assert_equal '+', out.first.left.operator.value
		assert_kind_of Tape::Number_Expr, out.first.left.left
		assert_equal 1, out.first.left.left.value
		assert_kind_of Tape::Circumfix_Expr, out.first.left.right
		assert_kind_of Tape::Infix_Expr, out.first.left.right.expressions.first
		assert_equal '/', out.first.left.right.expressions.first.operator.value
		assert_kind_of Tape::Circumfix_Expr, out.first.left.right.expressions.first.left
		assert_equal 2, out.first.left.right.expressions.first.left.expressions.first.left.value
		assert_equal '*', out.first.left.right.expressions.first.left.expressions.first.operator.value
		assert_equal 3, out.first.left.right.expressions.first.left.expressions.first.right.value
		assert_kind_of Tape::Number_Expr, out.first.left.right.expressions.first.right
		assert_equal 4, out.first.left.right.expressions.first.right.value
		assert_equal '-', out.first.operator.value
		assert_kind_of Tape::Circumfix_Expr, out.first.right
		assert_kind_of Tape::Number_Expr, out.first.right.expressions.first.left
		assert_equal 5, out.first.right.expressions.first.left.value
		assert_equal '%', out.first.right.expressions.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right.expressions.first.right
		assert_equal 6, out.first.right.expressions.first.right.value
	end

	def test_other
		out = Tape.parse 'numbers := 4815'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 1, out.count

		out = Tape.parse 'numbers,'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.left
		assert_equal '=', out.first.operator.value

		out = Tape.parse 'Type := {}'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.left
		assert_kind_of Tape::Circumfix_Expr, out.first.right
		assert_equal 1, out.count

		out = Tape.parse 'time: Float'
		assert_equal 'Float', out.first.type.value

		out = Tape.parse 'num: Int = 1 + 2'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.right
		assert_equal 'Int', out.first.left.type.value
	end

	def test_more_fixities
		out = Tape.parse '1 + 2 * 3 / 4'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Tape.parse '1 < 2'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Tape.parse '2 >= 1'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Tape.parse '1 != 2'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Tape.parse '1 == 2'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal 1, out.count

		out = Tape.parse '1 < 2, 4 > 3'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.last
		assert_equal 2, out.count
	end

	def test_ranges
		out = Tape.parse '1...2'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Number_Expr, out.first.left
		assert_equal '...', out.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 1, out.first.left.value
		assert_equal 2, out.first.right.value

		out = Tape.parse '3.0...4.0'
		assert_kind_of Tape::Number_Expr, out.first.left
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal '...', out.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 3.0, out.first.left.value
		assert_equal 4.0, out.first.right.value

		out = Tape.parse '3..<4'
		assert_kind_of Tape::Number_Expr, out.first.left
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal '..<', out.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 3, out.first.left.value
		assert_equal 4, out.first.right.value

		out = Tape.parse '5>..6'
		assert_kind_of Tape::Number_Expr, out.first.left
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal '>..', out.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 5, out.first.left.value
		assert_equal 6, out.first.right.value

		out = Tape.parse '7>.<8'
		assert_kind_of Tape::Number_Expr, out.first.left
		assert_kind_of Tape::Infix_Expr, out.first
		assert_equal '>.<', out.first.operator.value
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 7, out.first.left.value
		assert_equal 8, out.first.right.value

		out = Tape.parse '1...2, 3..<4, 5>..6, 7>.<8'
		assert_equal 4, out.count
		out.each do
			assert_kind_of Tape::Infix_Expr, it
			assert_kind_of Tape::Number_Expr, it.left
			assert_kind_of Tape::Number_Expr, it.right
		end
	end

	def test_comma_separated_expressions
		out = Tape.parse 'a, B, 5, "cool"'
		assert_equal 4, out.count
		assert_kind_of Tape::Infix_Expr, out[0]
		assert_kind_of Tape::Infix_Expr, out[1]
		assert_kind_of Tape::Number_Expr, out[2]
		assert_kind_of Tape::String_Expr, out[3]
	end

	def test_scope_operators
		# `~/` is the only symbolic scope operator; instance/type scope is `self`/`Self`.
		out = Tape.parse '~/global_scope'
		assert_kind_of Tape::Identifier_Expr, out.first
		assert_equal '~/', out.first.scope_operator.value

		# `self.`/`Self.` read as a plain `.` dot access off the bare keyword.
		assert_kind_of Tape::Infix_Expr, Tape.parse('self.this_instance').first

		# The nil-init and func-name forms desugar, tagging the identifier with the keyword itself.
		nil_init = Tape.parse('self.x,').first
		assert_equal 'self', nil_init.left.scope_operator.value
		assert_equal 'Self', Tape.parse('Self.f (;)').first.name.scope_operator.value
	end

	def test_functions
		out = Tape.parse '(;)'
		assert_kind_of Tape::Func_Expr, out.first
		assert_empty out.first.expressions
		refute out.first.name

		out = Tape.parse '(;
		)'
		assert_empty out.first.expressions
		refute out.first.name

		out = Tape.parse 'named_function (;)'
		assert_equal 'named_function', out.first.name.value
	end

	def test_function_params
		out = Tape.parse '( with_param; )'
		assert_equal 1, out.first.parameters.count
		assert_equal 0, out.first.expressions.count

		out = Tape.parse 'named ( with_param; )'
		assert_equal 'named', out.first.name.value
		assert_equal 1, out.first.parameters.count
		refute out.first.parameters.first.label
		refute out.first.parameters.first.default
		refute out.first.parameters.first.type

		out = Tape.parse '( labeled param; )'
		assert_equal 'labeled', out.first.parameters.first.label.value
		assert out.first.parameters.first.label
		refute out.first.parameters.first.default
		refute out.first.parameters.first.type

		out = Tape.parse '( default_values := 4; )'
		assert out.first.parameters.first.default
		assert_kind_of Tape::Number_Expr, out.first.parameters.first.default

		out = Tape.parse 'named ( and_labeled with_default := 8; )'
		assert_equal 'and_labeled', out.first.parameters.first.label.value
		assert_equal 'with_default', out.first.parameters.first.name.value
		assert_equal 'named', out.first.name.value

		out = Tape.parse 'named ( with, multiple, even labeled := 4, params := 5; )'
		assert_equal 4, out.first.parameters.count
		assert_equal out.first.parameters.map(&:label), [nil, nil, Tape::Lexeme.new(:identifier, 'even'), nil]
		assert_equal out.first.parameters.map(&:name), %w(with multiple labeled params).map { Tape::Lexeme.new(:identifier, _1) }
		assert_equal out.first.parameters.map(&:default).map(&:nil?), [true, true, false, false]
	end

	def test_function_bodies
		out = Tape.parse '
		square ( input;
			input * input
		)'
		refute_empty out.first.expressions
		assert_kind_of Tape::Infix_Expr, out.first.expressions[0]

		out = Tape.parse '
		nothing ( input;
			return input
		)'
		assert_kind_of Tape::Prefix_Expr, out.first.expressions[0]
		assert_kind_of Tape::Identifier_Expr, out.first.expressions[0].expression
	end

	def test_function_signatures
		out = Tape.parse 'nothing ( input;
			return input
		)'
		assert_equal 'nothing(input;)', out.first.signature
	end

	def test_complex_function
		out = Tape.parse '
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
		assert_kind_of Tape::Func_Expr, out.first
		assert_equal 'curr?', out.first.name.value
		assert_equal 3, out.first.expressions.count
		assert_equal 1, out.first.parameters.count

		early_return = out.first.expressions[0]
		assert_kind_of Tape::Conditional_Expr, early_return
		assert_kind_of Tape::Infix_Expr, early_return.condition
		assert_equal 'or', early_return.condition.operator.value
		assert_kind_of Tape::Prefix_Expr, early_return.condition.left
		assert_kind_of Tape::Prefix_Expr, early_return.condition.right
		assert_equal 1, early_return.when_true.count # todo One for return and one for false in `return false`. Maybe I should make it a prefix keyword.

		slice = out.first.expressions[1]
		assert_kind_of Tape::Infix_Expr, slice

		tap = out.first.expressions.last
		assert_kind_of Tape::Infix_Expr, tap
		assert_kind_of Tape::Func_Expr, tap.right
		assert_equal 2, tap.right.expressions.count
		assert_kind_of Tape::Infix_Expr, tap.right.expressions.first
		assert_kind_of Tape::Conditional_Expr, tap.right.expressions.last

		conditional = tap.right.expressions.last
		assert_kind_of Tape::Infix_Expr, conditional.condition
		assert_equal '===', conditional.condition.operator.value
		assert_equal 1, conditional.when_true.count # todo I don't think when_true and when_false convey that they return an array
		assert_equal 1, conditional.when_false.count

		# `expected.any? (; it == it2 )` -- a member call whose single anonymous-function argument
		# dropped its own parens (the spread-lambda sugar).
		any = conditional.when_true.first
		assert_kind_of Tape::Call_Expr, any
		assert_kind_of Tape::Infix_Expr, any.receiver
		assert_equal '.', any.receiver.operator.value
		assert_equal 'any?', any.receiver.right.value
		assert_equal 1, any.arguments.count
		assert_kind_of Tape::Func_Expr, any.arguments.first
		assert_kind_of Tape::Infix_Expr, any.arguments.first.expressions.first
		assert_equal 'it', any.arguments.first.expressions.first.left.value
		assert_equal 'it2', any.arguments.first.expressions.first.right.value
	end

	def test_function_calls
		out = Tape.parse '(;)()'
		assert_kind_of Tape::Call_Expr, out.first
		assert_kind_of Tape::Func_Expr, out.first.receiver
		assert_empty out.first.arguments

		out = Tape.parse '(;)(true)'
		refute_empty out.first.arguments
		assert_kind_of Tape::Identifier_Expr, out.first.arguments.first

		out = Tape.parse '(;)(1, 2, 3)'
		out.first.arguments.each do
			assert_kind_of Tape::Number_Expr, it
		end
	end

	def test_types
		out = Tape.parse 'String {}'
		assert_kind_of Tape::Type_Expr, out.first
		assert_equal 'String', out.first.name

		out = Tape.parse 'Transform {
			position,
			rotation,
		}'
		assert_equal 2, out.first.expressions.count

		out = Tape.parse 'Entity {
			|Transform
		}'
		assert_kind_of Tape::Composition_Expr, out.first.expressions.first
		assert_equal '|', out.first.expressions.first.operator.value
		assert_equal 'Transform', out.first.expressions.first.identifier.value
	end

	def test_mixed_inline_compositions
		out = Tape.parse 'Xform | Transform ~ Vec2 & This ^ That {}'
		assert_kind_of Tape::Composition_Expr, out.first.expressions.first
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
		out = Tape.parse 'if true
			celebrate()
		end'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Call_Expr, out.first.when_true.first

		out = Tape.parse 'wrap ( number, limit;
			if number > limit
				number = 0
			end
		 )'
		assert_kind_of Tape::Conditional_Expr, out.first.expressions[0]

		out = Tape.parse 'if 1 + 2 * 3 == 7
			"This one!"
		elif 1 + 2 * 3 == 9
			\'No, this one!\'
		else
			\'🤯\'
		end'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Conditional_Expr, out.first.when_false
		assert_kind_of Tape::String_Expr, out.first.when_false.when_false.first
	end

	def test_conditionals_at_end_of_line
		out = Tape.parse 'eat while lexemes? && curr?()'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.condition
		assert_kind_of Tape::Identifier_Expr, out.first.when_true.first
	end

	def test_unless_conditional
		out = Tape.parse 'do_this unless the_condition'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.condition
		assert_equal 'unless', out.first.type.value
		assert_equal 'the_condition', out.first.condition.value
		assert_kind_of Tape::Identifier_Expr, out.first.when_true.first
		assert_equal 'do_this', out.first.when_true.first.value
	end

	def test_until_conditional
		out = Tape.parse 'repeat_this until the_condition'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.condition
		assert_equal 'until', out.first.type.value
		assert_equal 'the_condition', out.first.condition.value
		assert_kind_of Tape::Identifier_Expr, out.first.when_true.first
		assert_equal 'repeat_this', out.first.when_true.first.value
	end

	def test_silly_elwhile
		out        = Tape.parse '
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
		assert_kind_of Tape::Conditional_Expr, while_case
		assert_equal 'while', while_case.type.value
		assert_kind_of Tape::Number_Expr, while_case.when_true.first
		assert_equal 1, while_case.when_true.first.value
		assert_kind_of Tape::Conditional_Expr, while_case.when_false

		elwhile = while_case.when_false
		assert_equal 'elwhile', elwhile.type.value
		assert_kind_of Tape::Number_Expr, elwhile.when_true.first
		assert_equal 2, elwhile.when_true.first.value
		assert_kind_of Tape::Conditional_Expr, elwhile.when_false

		elwhile = elwhile.when_false
		assert_equal 'elwhile', elwhile.type.value
		assert_kind_of Tape::Number_Expr, elwhile.when_true.first
		assert_equal 3, elwhile.when_true.first.value
		assert_kind_of Tape::Number_Expr, elwhile.when_false.first
		assert_equal 4, elwhile.when_false.first.value
	end

	def test_if_else
		# Direct copy-past from test_silly_elwhile
		out = Tape.parse '
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
		assert_kind_of Tape::Conditional_Expr, if_case
		assert_equal 'if', if_case.type.value
		assert_kind_of Tape::Number_Expr, if_case.when_true.first
		assert_equal 1, if_case.when_true.first.value
		assert_kind_of Tape::Conditional_Expr, if_case.when_false

		elif_case = if_case.when_false
		assert_equal 'elif', elif_case.type.value
		assert_kind_of Tape::Number_Expr, elif_case.when_true.first
		assert_equal 2, elif_case.when_true.first.value
		assert_kind_of Tape::Conditional_Expr, elif_case.when_false

		elif_case = elif_case.when_false
		assert_equal 'elif', elif_case.type.value
		assert_kind_of Tape::Number_Expr, elif_case.when_true.first
		assert_equal 3, elif_case.when_true.first.value
		assert_kind_of Tape::Number_Expr, elif_case.when_false.first
		assert_equal 4, elif_case.when_false.first.value
	end

	def test_circumfixes
		out = Tape.parse '[], (), {}'
		assert_equal 3, out.count
		out.each do |it|
			assert_kind_of Tape::Circumfix_Expr, it
			assert_empty it.expressions
		end

		out = Tape.parse '[1, 2, 3]'
		assert_equal 3, out.first.expressions.count
	end

	def test_type_init
		out = Tape.parse 'Type()'
		assert_kind_of Tape::Call_Expr, out.first
	end

	def test_func_call
		out = Tape.parse 'funk()'
		assert_kind_of Tape::Call_Expr, out.first
	end

	def test_call_expr_improvement
		out = Tape.parse 'Some.thing(1)'
		assert_kind_of Tape::Call_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.receiver
		assert_kind_of Tape::Number_Expr, out.first.arguments.first
	end

	def test_spread_lambda_single_anon_func_argument_drops_its_parens
		# `xs.map(x; x*2)` is sugar for `xs.map((x; x*2))` -- only when the receiver is a member
		# access / call / subscript (never a bare identifier, which stays a `f(x; body)` declaration).
		spread  = Tape.parse('xs.map(x; x * 2)').first
		wrapped = Tape.parse('xs.map((x; x * 2))').first

		assert_kind_of Tape::Call_Expr, spread
		assert_kind_of Tape::Infix_Expr, spread.receiver
		assert_equal '.', spread.receiver.operator.value
		assert_equal 1, spread.arguments.count
		assert_kind_of Tape::Func_Expr, spread.arguments.first
		assert_equal 1, spread.arguments.first.parameters.count
		assert_equal 'x', spread.arguments.first.parameters.first.name.value

		# same shape as the explicitly wrapped form
		assert_equal wrapped.class, spread.class
		assert_equal wrapped.arguments.first.class, spread.arguments.first.class
	end

	def test_spread_lambda_chains
		out = Tape.parse 'xs.map(x; x * 2).filter(n; n > 2)'
		assert_kind_of Tape::Call_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.receiver           # .filter
		assert_kind_of Tape::Call_Expr, out.first.receiver.left       # xs.map(...)
	end

	def test_spread_lambda_does_not_touch_bare_identifier_declarations
		# `f(x; body)` at a bare identifier is still a function *declaration*, unchanged.
		assert_kind_of Tape::Func_Expr, Tape.parse('double(n; n * 2)').first
	end

	def test_spread_lambda_only_for_a_lone_param_shaped_argument
		# a number then more is not "one anonymous-function argument" -- no spread, and (important) no
		# parser hang trying to read `0` as a parameter.
		result = Timeout.timeout(5) { Tape.parse('xs.accumulate(0, a, x; a + x)') rescue :parse_error }
		refute_nil result, 'parser must terminate on this shape rather than spinning'
	end

	# A literal's own *value* can coincidentally equal a meaningful punctuation character (`';'`, `'('`,
	# `','`, ...) -- #anon_func_param_list_follows? used to scan upcoming tokens by value alone, so an
	# ordinary string argument like `.join(';')` got mistaken for a param-list-shaped spread-lambda
	# argument, purely because its *content* happens to spell the real param/body separator.
	def test_spread_lambda_not_triggered_by_a_string_argument_matching_the_separator_character
		out = Tape.parse "xs.join(';')"
		assert_kind_of Tape::Call_Expr, out.first
		assert_equal 1, out.first.arguments.count
		assert_kind_of Tape::String_Expr, out.first.arguments.first
	end

	def test_spread_lambda_not_triggered_by_string_arguments_matching_other_param_list_tokens
		[',', ':', '->', '<', '>', '@', '(', ')', '[', '{'].each do |value|
			out = Tape.parse "xs.join('#{value}')"
			assert_kind_of Tape::String_Expr, out.first.arguments.first, "failed for '#{value}'"
		end
	end

	def test_join_with_a_semicolon_separator_actually_runs_correctly
		out = Tape.interp "[1, 2, 3].join(';')"
		assert_equal '1;2;3', out
	end

	# #func_declaration_follows? has the same value-vs-type shape -- a param default whose own literal
	# value contains real syntax characters (parens, the separator) must not confuse where the param
	# list/body boundary actually is.
	def test_func_declaration_with_a_punctuation_like_string_default_still_parses_correctly
		out = Tape.interp "f (x := '(;)'; x), f()"
		assert_equal '(;)', out
	end

	# Root-cause fix for the whole family above: Lexeme#is (the primitive every `curr?(...)` check goes
	# through) used to match a bare string comparator against `.value` alone, with no type check -- so
	# any literal (string/symbol/number/fence) whose own content coincidentally equalled a delimiter
	# confused whichever loop was scanning for that delimiter, not just the spread-lambda/func-decl
	# lookaheads. #parse_circumfix_expr (parses every `(...)`/`[...]`/`{...}`/`|...|` grouping -- calls,
	# tuples, arrays, dicts, struct literals) is the highest-traffic example: `until curr? closing`
	# mistook a literal argument equal to the closing character for the real delimiter, ending the
	# group early and leaving the true closer to crash the parser as an "unhandled lexeme".
	def test_call_argument_matching_the_closing_paren_does_not_end_the_call_early
		out = Tape.interp "[1, 2].join(')')"
		assert_equal '1)2', out
	end

	def test_array_literal_element_matching_the_closing_bracket_parses_correctly
		out = Tape.interp "['a', ']']"
		assert_equal ['a', ']'], out.values
	end

	def test_dictionary_value_matching_the_closing_brace_parses_correctly
		out = Tape.interp "d := {a: 1, b: '}'}
		d.b"
		assert_equal '}', out
	end

	def test_tuple_element_matching_the_closing_paren_parses_correctly
		out = Tape.interp "t := ('x', ')')
		t.1"
		assert_equal ')', out
	end

	def test_struct_member_matching_the_closing_angle_bracket_parses_correctly
		out = Tape.interp "s := <'>'>
		s.0"
		assert_equal '>', out
	end

	def test_return_is_an_identifier
		out = Tape.parse 'return 1 + 2'
		assert_kind_of Tape::Prefix_Expr, out.first
	end

	def test_return_with_conditional_at_end_of_line
		out = Tape.parse 'return x unless y'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Prefix_Expr, out.first.when_true.first
		assert_kind_of Tape::Identifier_Expr, out.first.when_true.first.expression
		assert_kind_of Tape::Identifier_Expr, out.first.condition
	end

	def test_return_with_conditionals
		out = Tape.parse 'return 3 if true'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Prefix_Expr, out.first.when_true.first
		assert_kind_of Tape::Number_Expr, out.first.when_true.first.expression
		assert_kind_of Tape::Identifier_Expr, out.first.condition
	end

	def test_identifier_dot_integer_is_an_infix
		out = Tape.parse 'something.4'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.left
		assert_kind_of Tape::Number_Expr, out.first.right
		assert_equal 4, out.first.right.value
	end

	def test_identifier_dot_float_is_an_infix
		out = Tape.parse 'not_gonna_work.4.8.15'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Identifier_Expr, out.first.left
		assert_kind_of Tape::Array_Index_Expr, out.first.right
		assert_equal '4.8.15', out.first.right.value
		assert_equal [4, 8, 15], out.first.right.indices_in_order
	end

	def test_multidot_number_lexeme
		out = Tape.parse '4.8.15.16.23.42'
		assert_kind_of Tape::Array_Index_Expr, out.first
		assert_equal '4.8.15.16.23.42', out.first.value
		assert_equal [4, 8, 15, 16, 23, 42], out.first.indices_in_order
	end

	def test_complex_return_with_conditionals
		out = Tape.parse 'return 4+2 if true'
		assert_kind_of Tape::Conditional_Expr, out.first
		assert_kind_of Tape::Prefix_Expr, out.first.when_true.first
		assert_kind_of Tape::Infix_Expr, out.first.when_true.first.expression
		assert_kind_of Tape::Identifier_Expr, out.first.condition
	end

	def test_possibly_ambigous_type_and_func_syntax_mixture
		out = Tape.parse 'x , y , z'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out[1]
		assert_kind_of Tape::Identifier_Expr, out.last

		out = Tape.parse 'x , y , z'
		assert_kind_of Tape::Infix_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out[1]
		assert_kind_of Tape::Identifier_Expr, out.last
	end

	def test_function_signature
		out = Tape.parse '(-> Identifier;)'
		assert_kind_of Tape::Func_Signature_Expr, out.first

		out = Tape.parse '(Number -> String;)'
		assert_kind_of Tape::Func_Signature_Expr, out.first

		out = Tape.parse 'string (number;)'
		assert_kind_of Tape::Func_Expr, out.first
	end

	def test_double_less_than_is_operator
		out = Tape.parse '<<'
		assert_kind_of Tape::Operator_Expr, out.first
	end

	def test_writable_unpack_prefix
		out = Tape.parse 'funk ( @writable with; )'
		assert_equal 'with', out.first.parameters.first.value
		assert_kind_of Tape::Param_Expr, out.first.parameters.first
		assert out.first.parameters.first.add_to_writable
		refute out.first.parameters.first.add_to_readable
	end

	def test_readable_unpack_prefix
		out = Tape.parse 'funk ( @readable with; )'
		assert_equal 'with', out.first.parameters.first.value
		assert_kind_of Tape::Param_Expr, out.first.parameters.first
		assert out.first.parameters.first.add_to_readable
		refute out.first.parameters.first.add_to_writable
	end

	def test_for_loops
		out = Tape.parse '
		for []
		end'
		assert_empty out.first.body
		assert_instance_of Tape::Circumfix_Expr, out.first.collection # note, The iterable becomes an Array in the interpreter.
		assert_equal '[]', out.first.collection.grouping
	end

	def test_directive_identifier
		# `@word` with nothing after it is a bare Context read (routed by `.prefixed_with_at` at interpret
		# time), not a generic operand-grabbing directive -- there's no reserved-word list anymore.
		out = Tape.parse '@whatever'
		assert_instance_of Tape::Identifier_Expr, out.first
		assert out.first.prefixed_with_at

		# A trailing `(...)` is an ordinary call on that read.
		out = Tape.parse '@whatever(a, b)'
		assert_instance_of Tape::Call_Expr, out.first
		assert_instance_of Tape::Identifier_Expr, out.first.receiver
		assert out.first.receiver.prefixed_with_at
	end

	def test_all_http_methods
		Tape::HTTP_VERBS.each do |verb|
			assert_instance_of Tape::Route_Expr, Tape.parse("#{verb}://path (;)").first
		end
	end

	def test_route_declaration_with_http_method_directives
		refute_raises Tape::Invalid_Http_Directive_Handler do
			out = Tape.parse 'get://something (;)'
			assert_equal 1, out.count
			assert_instance_of Tape::Route_Expr, out.first
			assert_equal 'get', out.first.http_method.value
			assert_equal "something", out.first.path
		end

		out = Tape.parse '@whatever "endpoint" (;)'
		refute_instance_of Tape::Route_Expr, out.first
		assert_instance_of Tape::Identifier_Expr, out[0] # bare `@whatever` Identity read
		assert out[0].prefixed_with_at
		assert_instance_of Tape::Func_Expr, out.last
	end

	def test_empty_html_element_expression
		out = Tape.parse '```html
		```'
		assert_equal 1, out.count

		assert_instance_of Tape::Html_Fence_Expr, out.first
	end

	def test_skip_and_stop_are_operators
		out = Tape.parse 'skip'
		assert_instance_of Tape::Operator_Expr, out.first

		out = Tape.parse 'stop'
		assert_instance_of Tape::Operator_Expr, out.first
	end

	def test_single_line_comments
		out = Tape.parse '# abc'
		assert_instance_of Tape::Comment_Expr, out.first

		out = Tape.parse '# abc
		# def'
		assert_instance_of Tape::Comment_Expr, out.first
		assert_instance_of Tape::Comment_Expr, out.last
		assert out.first != out.last
	end

	def test_block_comments
		out = Tape.parse '###abc###'
		assert_instance_of Tape::Comment_Expr, out.first

		out = Tape.parse '###abc
		def###'
		assert_instance_of Tape::Comment_Expr, out.first
		assert_instance_of Tape::Comment_Expr, out.last
		assert out.first == out.last

		out = Tape.parse '###abc### ###def###'
		assert_instance_of Tape::Comment_Expr, out.first
		assert_instance_of Tape::Comment_Expr, out.last
		assert out.first != out.last
	end

	def test_fence_blocks
		out = Tape.parse '```abc```'
		assert_instance_of Tape::Fence_Expr, out.first

		out = Tape.parse '```abc
		def```'
		assert_instance_of Tape::Fence_Expr, out.first
		assert_instance_of Tape::Fence_Expr, out.last
		assert out.first == out.last
	end

	def test_fence_expr_attributes
		out   = Tape.parse '```
		some content here
		```'
		fence = out.first

		assert_instance_of Tape::Fence_Expr, fence
		assert_equal :fence, fence.type
		assert_instance_of Tape::String_Expr, fence.value
		assert fence.value.value.include?('some content here')
	end

	def test_fence_expr_multiline_content
		out   = Tape.parse '```
		line one
		line two
		line three
		```'
		fence = out.first

		assert_instance_of Tape::Fence_Expr, fence
		assert_equal :fence, fence.type
		assert fence.value.value.include?('line one')
		assert fence.value.value.include?('line two')
		assert fence.value.value.include?('line three')
	end

	def test_html_fence_expr_attributes
		out        = Tape.parse '```html
		<div>Hello</div>
		```'
		html_fence = out.first

		assert_instance_of Tape::Html_Fence_Expr, html_fence
		assert_instance_of Tape::String_Expr, html_fence.body
		assert html_fence.body.value.include?('<div>Hello</div>')
		assert_equal html_fence.value, html_fence.body
		refute_nil html_fence.element
	end

	def test_html_fence_expr_with_interpolation
		out        = Tape.parse '```html
		<h1>Welcome `name`</h1>
		```'
		html_fence = out.first

		assert_instance_of Tape::Html_Fence_Expr, html_fence
		assert html_fence.body.value.include?('<h1>Welcome `name`</h1>')
		assert html_fence.body.interpolated
	end

	def test_html_fence_expr_without_interpolation
		out        = Tape.parse '```html
		<p>Plain text</p>
		```'
		html_fence = out.first

		assert_instance_of Tape::Html_Fence_Expr, html_fence
		refute html_fence.body.interpolated
	end

	def test_html_fence_strips_html_marker
		out        = Tape.parse '```html
		<span>Content</span>
		```'
		html_fence = out.first

		assert_instance_of Tape::Html_Fence_Expr, html_fence
		# The 'html' marker should be stripped from body
		refute html_fence.body.value.start_with?('html')
	end

	def test_operator_overload_parses
		assert_raises Tape::Operator_Overload_Fixity_Must_Be_One_Of do
			Tape.parse <<~CODE
			    @operator := @heehee 500 ( left, right; )
			CODE
		end

		assert_raises Tape::Operator_Overload_Precedence_Must_Be_Integer do
			Tape.parse <<~CODE
			    @operator $ @prefix hmm ( left, right; )
			CODE
		end

		assert_raises Tape::Operator_Overload_Precedence_Must_Be_Integer do
			Tape.parse <<~CODE
			    @operator + @infix notanumber ( left, right; )
			CODE
		end

		out      = Tape.parse '@operator := @infix 500 ( left, right; )'
		overload = out.first
		assert_instance_of Tape::Operator_Overload_Expr, overload
		assert_equal ':=', overload.value
		assert_equal 'infix', overload.fixity.value
		assert_equal 500, overload.precedence
		assert_instance_of Tape::Func_Expr, overload.func_expr

		{ 'infix' => '~~', 'prefix' => '!!', 'postfix' => '??' }.each do |fixity, op|
			refute_raises do
				Tape.parse "@operator #{op} @#{fixity} 300 ( x; x )"
			end
		end

		# Operator is registered so it can appear in a subsequent expression as Infix_Expr
		out   = Tape.parse "@operator ~> @infix 700 ( left, right; left )\na ~> b"
		infix = out.last
		assert_instance_of Tape::Infix_Expr, infix
		assert_equal '~>', infix.operator.value
		assert_equal 'a', infix.left.value
		assert_equal 'b', infix.right.value
	end

	def test_statement_expressions
		out = Tape.parse "`1+2`"
		assert_kind_of Tape::Statement_Expr, out.first
		assert_kind_of Tape::Infix_Expr, out.first.expression
	end

	def test_fancier_statement_example
		out = Tape.parse "x := `@load 'tapes/string'`"
		assert_kind_of Tape::Statement_Expr, out.last.right
	end
end
