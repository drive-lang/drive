require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

# These tests are mostly in chronological order. I may have inserted some at times. It would be great to preserve this order.

class Interpreter_Test < Base_Test
	def test_preload_dot_air
		refute_raises RuntimeError do
			Tape.interp_file './tapes/preload.tape'
		end
	end

	def test_numeric_literals
		assert_equal 48, Tape.interp('48')
		assert_equal 15.16, Tape.interp('15.16')
		assert_equal 2342, Tape.interp('23_42')
	end

	def test_true_false_nil_literals
		assert_equal true, Tape.interp('true')
		assert_equal false, Tape.interp('false')
		assert_instance_of NilClass, Tape.interp('nil')
	end

	def test_uninterpolated_strings
		assert_equal 'Walt!', Tape.interp('"Walt!"')
		assert_equal 'Vincent!', Tape.interp("'Vincent!'")
	end

	def test_raises_undeclared_identifier_when_reading
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp 'hatch'
		end
	end

	def test_does_not_raise_undeclared_identifier_when_declaring
		refute_raises Tape::Undeclared_Identifier do
			Tape.interp 'found := true'
		end
	end

	def test_variable_assignment_and_lookup
		out = Tape.interp 'name := "Locke", name'
		assert_equal 'Locke', out
	end

	def test_constant_assignment_and_lookup
		out = Tape.interp 'ENVIRONMENT := :development, ENVIRONMENT'
		assert_equal :development, out
	end

	def test_cannot_assign_incompatible_type
		# todo; raises Cannot_Reassign_Undeclared_Identifier
		assert_raises Tape::Cannot_Assign_Incompatible_Type do
			Tape.interp 'MyType {}
			My_Type = :anything'
		end

		refute_raises Tape::Cannot_Assign_Incompatible_Type do
			Tape.interp 'MyType {}
			My_Type = Other {}'
		end
	end

	def test_nil_assignment_operator
		out = Tape.interp 'nothing,'
		assert_instance_of NilClass, out
	end

	def test_anonymous_func_expr
		out = Tape.interp '(;)'
		assert_instance_of Tape::Func, out
		assert_empty out.expressions
		refute out.name
	end

	def test_empty_func_declaration
		out = Tape.interp 'open (;)'
		assert_instance_of Tape::Func, out
		assert_empty out.expressions
		assert_equal 'open', out.name.value
	end

	def test_basic_func_declaration
		out = Tape.interp 'enter ( numbers := "4815162342"; )'
		assert_equal 1, out.parameters.count
		assert_empty out.expressions
		assert_instance_of Tape::Param_Expr, out.parameters.first
		assert_instance_of Tape::String_Expr, out.parameters.first.default
	end

	def test_advanced_func_declaration
		out = Tape.interp 'add ( a, b; a + b )'
		assert_equal 2, out.parameters.count
		assert_equal 1, out.expressions.count
		assert_instance_of Tape::Infix_Expr, out.expressions.last
		refute out.parameters.first.default
	end

	def test_complex_func_declaration
		out = Tape.interp 'run ( a, labeled b, c := 4, labeled d := 8;
			c + d
		)'
		assert_equal 4, out.parameters.count
		assert_equal 1, out.expressions.count

		a = out.parameters[0]
		assert_equal 'a', a.name.value
		refute a.label
		refute a.default

		b = out.parameters[1]
		assert b.label
		assert_equal 'labeled', b.label.value
		refute b.default

		c = out.parameters[2]
		assert c.default
		refute c.label

		d = out.parameters[3]
		assert d.label
		assert d.default

		assert_instance_of Tape::Infix_Expr, out.expressions.last
	end

	def test_empty_type_declaration
		out = Tape.interp 'Island {}'
		assert_instance_of Tape::Type, out
		assert_empty out.expressions
		assert_equal 'Island', out.name
	end

	def test_basic_type_declaration
		out = Tape.interp 'Hatch {
			computer := nil

			enter ( numbers;
				# do something with the numbers
			)
		}'
		assert_instance_of Tape::Type, out
		assert_instance_of NilClass, out[:computer]
		assert_instance_of Tape::Func, out[:enter]
	end

	def test_inline_type_composition_declaration
		out = Tape.interp 'Number {}
		Integer | Number {}'
		assert_instance_of Tape::Type, out
		assert_equal %w(Integer Number), out.types
	end

	def test_inbody_type_composition_declaration
		out = Tape.interp 'Numeric {
			numerator,
		}
		Number | Numeric {}
		Float {
			| Number
		}'
		assert_instance_of Tape::Type, out
		assert_equal %w(Float Number Numeric), out.types
	end

	def test_invalid_type_declaration
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp 'Number | Numeric {}'
		end
	end

	def test_potential_colon_ambiguity
		out = Tape.interp 'assign_to_nil,'
		assert_instance_of NilClass, out

		out = Tape.interp 'func ( assign_to_nil; )'
		assert_instance_of Tape::Func, out
		assert_instance_of Tape::Param_Expr, out.parameters.first
		assert_equal 'assign_to_nil', out.parameters.first.name.value
	end

	def test_infix_arithmetic
		assert_equal 12, Tape.interp('4 + 8')
		assert_equal 4, Tape.interp('1 + 2 * 3 / 4 % 5 ^ 6')
		assert_equal 8, Tape.interp('(1 + (2 * 3 / 4) % 5) << 2')
	end

	def test_nested_type_declaration
		out = Tape.interp '
		Computer {
		}

		Island {
			Hatch {
				Commodore_64 | Computer {}
			}
		}

		Island.Hatch.Commodore_64'
		assert_instance_of Tape::Type, out
	end

	def test_constants_cannot_be_reassigned
		assert_raises Tape::Cannot_Reassign_Constant do
			Tape.interp 'ENVIRONMENT := :development
			ENVIRONMENT = :production'
		end
	end

	def test_variable_declarations
		out = Tape.interp 'cool := "Cooper"'
		assert_equal 'Cooper', out

		out = Tape.interp 'delta := 0.017'
		assert_equal 0.017, out
	end

	def test_declared_variable_lookup
		out = Tape.interp 'number := 42
		number'
		assert_equal 42, out
	end

	def test_variable_can_be_reassigned
		out = Tape.interp 'number := 42'
		assert_equal 42, out

		out = Tape.interp 'number := 42
		number = 8'
		assert_equal 8, out
	end

	def test_inclusive_range
		out = Tape.interp '4...42'
		assert_instance_of Tape::Range, out
		assert_equal 4..42, out
		assert out.include? 4
		assert out.include? 23
		assert out.include? 42
	end

	def test_right_exclusive_range
		out = Tape.interp '4..<42'
		assert_instance_of Tape::Range, out
		assert_equal 4...42, out
		assert out.include? 4
		assert out.include? 41
		refute out.include? 42
	end

	def test_left_exclusive_range
		out = Tape.interp '4>..42'
		assert_instance_of Tape::Range, out
		assert_equal 5..42, out
		refute out.include? 4
		assert out.include? 5
		assert out.include? 42
	end

	def test_left_and_right_exclusive_range
		out = Tape.interp '4>.<42'
		assert_instance_of Tape::Range, out
		assert_equal 5...42, out
		refute out.include? 4
		assert out.include? 5
		assert out.include? 41
		refute out.include? 42
	end

	def test_empty_left_and_right_exclusive_range
		out = Tape.interp '0>.<0'
		assert_equal 1...0, out
		refute out.include? -1
		refute out.include? 0
		refute out.include? 1
		refute out.include? 0.5
	end

	def test_simple_comparison_operators
		assert Tape.interp '1 == 1'
		refute Tape.interp '1 != 1'
		assert Tape.interp '1 != 2'
		assert Tape.interp '1 < 2'
		refute Tape.interp '1 > 2'

		# It doesn't make sense to test all these since I'm just calling through to Ruby
	end

	def test_boolean_logic
		assert Tape.interp 'true && true'
		refute Tape.interp 'true && false'
		assert Tape.interp 'true and true'
		refute Tape.interp 'true and false'
	end

	def test_arithmetic_operators
		out = Tape.interp '1 + 2 / 3 - 4 * 5'
		assert_equal -19, out

		# Right now this functions like the Ruby operator, but it could also be the power operator
		out = Tape.interp '2 ^ 3'
		assert_equal 1, out

		out = Tape.interp '1 << 2'
		assert_equal 4, out

		out = Tape.interp '1 << 3'
		assert_equal 8, out
	end

	def test_double_operators
		out = Tape.interp '1 - -9'
		assert_equal 10, out

		out = Tape.interp '4 + -8'
		assert_equal -4, out

		out = Tape.interp '8 - +15'
		assert_equal -7, out
	end

	def test_empty_array
		out = Tape.interp '[]'
		assert_equal [], out.values
		assert_instance_of Tape::Array, out
	end

	def test_non_empty_arrays
		out = Tape.interp '[1]'
		assert_instance_of Tape::Array, out
		assert_equal [1], out.values

		out = Tape.interp '[1, "test", 5]'
		assert_instance_of Tape::Array, out
		assert_equal Tape::Array.new([1, 'test', 5]).values, out.values
	end

	def test_tuples
		out = Tape.interp '(1, 2)'
		assert_kind_of Tape::Tuple, out
		assert_equal [1, 2], out.values

		out = Tape.interp 't := ("Hello", "from" ,"Tuple")
		t_first := t.0
		t2 := (t.0, t.1, t.2)
		(t_first, t == t2, t_first == t2, t2)'
		assert_equal "Hello", out.values.first
		assert out.values[1]
		refute out.values[2]
		assert_equal ["Hello", "from", "Tuple"], out.values.last.values
	end

	def test_empty_dictionary
		out = Tape.interp '{}'
		assert_kind_of Tape::Dictionary, out
		assert_equal out.hash, {}
	end

	def test_create_dictionary_with_identifiers_as_keys_without_commas
		out = Tape.interp '{a b c}'
		assert_equal %i(a b c), out.hash.keys
		out.hash.values.each do |value|
			assert_instance_of NilClass, value
		end
	end

	def test_create_dictionary_with_identifiers_as_keys_with_commas
		out = Tape.interp '{a, b}'
		out.hash.values.each do |value|
			assert_instance_of NilClass, value
		end
	end

	def test_create_dictionary_with_keys_and_values_with_mixed_infix_notation
		out = Tape.interp '{ x:0 y=1 z}'
		refute_instance_of NilClass, out.hash.values.first
		refute_instance_of NilClass, out.hash.values[1]
		assert_instance_of NilClass, out.hash.values.last
	end

	def test_create_dictionary_with_keys_and_values_with_mixed_infix_notation_and_commas
		out = Tape.interp '{ x:4, y=8, z}'
		assert_equal 4, out.hash.values.first
		assert_equal 8, out.hash.values[1]
		assert_instance_of NilClass, out.hash.values.last
	end

	def test_create_dictionary_with_local_value
		out = Tape.interp 'x:=4, y:=2, { x=x, y=y }'
		assert_equal out.hash, { x: 4, y: 2 }
	end

	def test_symbol_as_dictionary_keys
		out = Tape.interp '{ :x = 1 }'
		assert_equal out.hash, { x: 1 }
	end

	def test_string_as_dictionary_keys
		out = Tape.interp '{ "x" = 1 }'
		assert_equal out.hash, { x: 1 }
	end

	def test_colon_as_dictionary_infix_operator
		out = Tape.interp 'x := 123, { x: x }'
		assert_equal out.hash, { x: 123 }
	end

	def test_equals_as_dictionary_infix_operator
		out = Tape.interp 'x := 123, { x = x }'
		assert_equal out.hash, { x: 123 }
	end

	def test_dictionary_keys
		out = Tape.interp '{ a b c }.keys()'
		assert_equal [:a, :b, :c], out.values
	end

	def test_dictionary_values
		out = Tape.interp '{ a b c }.values()'
		assert_equal [nil, nil, nil], out.values

		out = Tape.interp '{ a=1, b= "two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Tape.interp '{ a=1, b="two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Tape.interp '{ a=1, b:"two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values
	end

	def test_dictionary_subscript
		out = Tape.interp "dict := {x}
		original := dict[:x]
		dict[:x] = 4815
		(original, dict[:x])"
		assert_equal [nil, 4815], out.values
	end

	def test_dictionary_subscript_string_and_symbol_do_not_behave_differently
		out = Tape.interp "dict := {x=4815}
		(dict['x'], dict[:x])"
		assert_equal [4815, 4815], out.values
	end

	def test_too_many_dictionary_subscript_arguments
		assert_raises Tape::Too_Many_Subscript_Expressions do
			Tape.interp "dict := {x=4815}
			dict[:x, 123]"
		end

		assert_raises Tape::Too_Many_Subscript_Expressions do
			Tape.interp "dict := {x=4815}
			dict[:x, 123] = 162342"
		end
	end

	def test_nested_dictionary_subscript
		out = Tape.interp '{ a: { b: 42 } }[:a][:b]'
		assert_equal 42, out
	end

	def test_dictionary_subscript_nonexistent_key
		out = Tape.interp '{ a: 1 }[:nonexistent]'
		assert_nil out
	end

	def test_dictionary_subscript_with_variable
		out = Tape.interp 'key := :a, dict := { a: 99 }, dict[key]'
		assert_equal 99, out
	end

	def test_dictionary_subscript_in_expression
		out = Tape.interp '{ x: 10 }[:x] + 5'
		assert_equal 15, out
	end

	def test_empty_dictionary_subscript
		out = Tape.interp '{}[:key]'
		assert_nil out
	end

	def test_invalid_dictionary_infix
		assert_raises Tape::Invalid_Dictionary_Infix_Operator do
			Tape.interp '{ x > x }'
		end
	end

	def test_assigning_function_to_variable
		out = Tape.interp 'funk := ( a, b, c; )'
		assert_equal 3, out.parameters.count
	end

	def test_composed_type_declaration
		out = Tape.interp '
		Transform {}
		Rotation {}
		Entity {
			| Transform
			~ Rotation
		}'
		assert_kind_of Tape::Type, out
		assert_kind_of Tape::Composition_Expr, out.expressions.first
		assert_kind_of Tape::Composition_Expr, out.expressions.last
		assert_equal 'Rotation', out.expressions.last.identifier.value
		assert_equal '~', out.expressions.last.operator.value
	end

	def test_composed_type_declaration_before_body
		out = Tape.interp '
		Transform {}, Physics {}
		Entity | Transform ~ Physics {}'
		assert_kind_of Tape::Type, out
		assert_kind_of Tape::Composition_Expr, out.expressions.first
		assert_kind_of Tape::Composition_Expr, out.expressions.last
		assert_equal 'Physics', out.expressions.last.identifier.value
		assert_equal '~', out.expressions.last.operator.value
	end

	def test_complex_type_declaration
		out = Tape.interp 'Transform {
			position,
			rotation,

			x := 0
			y := 0

			to_s (;
				"Transform!"
			)
		}'
		assert_kind_of Tape::Infix_Expr, out.expressions[0]
		assert_kind_of Tape::Infix_Expr, out.expressions[1]
		assert_kind_of Tape::Infix_Expr, out.expressions[2]
		assert_kind_of Tape::Infix_Expr, out.expressions[3]
		assert_kind_of Tape::Func_Expr, out.expressions[4]
	end

	def test_undeclared_type_init_with_new_keyword
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp 'Type.new'
		end
	end

	def test_raises_non_type_initialization_error
		assert_raises Tape::Cannot_Initialize_Non_Type_Identifier do
			Tape.interp 'x := 1, x.new'
		end
	end

	def test_declared_type_init_with_new_keyword
		out = Tape.interp 'Type {}, Type.new'
		assert_instance_of Tape::Instance, out
		assert_equal 'Type', out.name
	end

	# Bare `X.new` is equivalent to `X()` — it runs `new(;)`, so required constructor params raise.
	def test_bare_new_runs_constructor
		out = Tape.interp 'Thing {
			x,
			new (;
				self.x = 123
			)
		}, Thing.new.x'
		assert_equal 123, out

		assert_raises Tape::Missing_Argument do
			Tape.interp 'Thing { x, new ( x; self.x = x ) }, Thing.new'
		end
	end

	def test_complex_type_init
		out = Tape.interp 'Transform {
			position,
			rotation,

			x := 4
			y := 8

			to_s (;
				"Transform!"
			)

			new ( position := 0; )
		}, Transform.new'
		assert_kind_of Tape::Instance, out
		assert_equal 'Transform', out.name
		assert_kind_of ::Array, out.expressions
		assert_equal 6, out.expressions.count
		assert_kind_of Tape::Func_Expr, out.expressions.last
	end

	def test_complex_type_with_value_lookup
		out = Tape.interp 'Vector1 { x := 4 }
		Vector1.new.x
		'
		assert_equal 4, out
	end

	def test_instance_complex_value_lookup
		out = Tape.interp 'Vector2 { x := 1, y := 2 }
		Transform {
			position := Vector2.new
		}
		t := Transform.new
		(t.position, t.position.y)
		'
		assert_kind_of Tape::Tuple, out
		assert_kind_of Tape::Instance, out.values.first
		assert_equal 2, out.values.last
	end

	def test_type_declaration_with_parens
		out = Tape.interp 'Vector2 { x := 0, y := 1 }
		pos := Vector2()'
		assert_instance_of Tape::Instance, out
		data = { 'x' => 0, 'y' => 1, 'name' => 'Vector2', 'display_name' => 'Vector2', 'types' => Tape::Array.new(['Vector2']) }
		assert_equal data, out.declarations
	end

	# `.name =`/`.types =` (set during construction) are plain Ruby attr writes; when the backing Ruby class is shared with a *composed* type (`Tasks | Table {}` resolves to Tape::Table, a Ruby-backed builtin), that class's own Type#initialize already baked its own name ("Table") into @declarations['name'] at construction, which an Tape-level `instance.name` dot-read used to stay stuck on instead of the real composed type's name.
	def test_composed_instance_reports_its_own_name_not_the_backing_ruby_class_regression
		out = Tape.interp "@load 'tapes/table'
			Tasks | Table {}
			t := Tasks()
			(t.name, t.types)"
		assert_equal 'Tasks', out.values.first
		assert_equal %w(Tasks Table), out.values.last.values
	end

	def test_dot_slash
		assert_raises Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Tape.interp './x := 123'
		end
	end

	def test_look_up_dot_slash_without_dot_slash
		assert_raises Tape::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Tape.interp '../x := 123'
		end
	end

	def test_look_up_dot_slash_with_dot_slash
		out = Tape.interp '~/y := 543
		~/y'
		assert_equal 543, out
	end

	def test_function_call_with_arguments
		out = Tape.interp '
		add ( a, b; a+b )
		add(4, 8)'
		assert_equal 12, out
	end

	def test_named_call_arguments_bind_by_declared_name_regardless_of_order
		src = 'sub ( a, b; a - b )'
		assert_equal -1, Tape.interp("#{src}\nsub(a := 1, b := 2)")
		assert_equal -1, Tape.interp("#{src}\nsub(b := 2, a := 1)") # reordered -- same result
	end

	def test_named_call_arguments_can_follow_positional_arguments
		src = 'sub ( a, b; a - b )'
		assert_equal -1, Tape.interp("#{src}\nsub(1, b := 2)")
	end

	def test_positional_argument_after_named_raises
		assert_raises Tape::Positional_Argument_After_Named do
			Tape.interp 'add ( a, b; a + b )
				add(a := 1, 2)'
		end
	end

	def test_duplicate_named_argument_raises
		assert_raises Tape::Duplicate_Named_Argument do
			Tape.interp 'add ( a, b; a + b )
				add(a := 1, a := 2)'
		end
	end

	def test_argument_given_by_name_and_position_raises
		assert_raises Tape::Argument_Given_By_Name_And_Position do
			Tape.interp 'add ( a, b; a + b )
				add(1, a := 2)'
		end
	end

	# An unknown name is the actual mistake, so it has to be reported even when some other (unrelated) param is also left without a value as a side effect of that same typo -- not masked by a confusing Missing_Argument that never mentions the real problem.
	def test_unknown_named_argument_raises_even_when_another_param_is_also_left_missing
		assert_raises Tape::Unknown_Named_Argument do
			Tape.interp 'add ( a, b; a + b )
				add(a := 1, c := 2)' # `c` isn't a param; `b` is consequently never filled
		end
	end

	def test_named_call_arguments_fall_back_to_defaults_when_omitted
		out = Tape.interp <<~CODE
		    greet ( name := "World"; "Hello, `name`" )
		    (greet(), greet(name := "Tape"))
		CODE
		assert_equal ['Hello, World', 'Hello, Tape'], out.values
	end

	def test_named_call_arguments_do_not_leak_into_caller_scope
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp 'add ( a, b; a + b )
				add(a := 1, b := 2)
				a' # `a` was never declared in the caller -- only inside add's own call scope
		end
	end

	def test_named_call_arguments_work_through_constructors
		out = Tape.interp <<~CODE
		    Point {
		    	x,
		    	y,
		    	new ( x, y;
		    		self.x = x
		    		self.y = y
		    	)
		    }
		    p := Point(y := 4, x := 3)
		    (p.x, p.y)
		CODE
		assert_equal [3, 4], out.values
	end

	# Labels (`:`, checked positionally against the declared label) and named arguments (`:=`, bound by declared name) are separate mechanisms with separate syntax -- a call can use a label on an early positional argument, then switch to named arguments for the rest.
	def test_named_call_arguments_are_distinct_from_labels
		out = Tape.interp <<~CODE
		    send ( to person, subject := 'hi'; "`person`: `subject`" )
		    send(to: 'Alice', subject := 'bye')
		CODE
		assert_equal 'Alice: bye', out
	end

	def test_compound_operator
		out = Tape.interp 'add ( amount := 1, to := 0;
			to += amount
		)
		add(5, 37)'
		assert_equal 42, out
	end

	def test_long_dot_chain
		shared_code = '
		A {
			B {
				C {
					d := 4
				}
			}
		}'

		out = Tape.interp "#{shared_code}
		A.B"
		assert_instance_of Tape::Type, out

		out = Tape.interp "#{shared_code}
		A.B.C.new()"
		assert_instance_of Tape::Instance, out

		out = Tape.interp "#{shared_code}
		A.B.C.new().d"
		assert_equal 4, out
	end

	def test_closures_do_capture_values
		out = Tape.interp '
		counter := -1
		increment ( count;
			counter += count
		)
		increment(counter)
		counter
		'
		assert_equal -2, out
	end

	def test_calling_functions
		refute_raises RuntimeError do
			out = Tape.interp '
			square ( input;
				input * input
			)

			result := square(5)
			result'
			assert_equal 25, out
		end
	end

	def test_function_call_as_argument
		out = Tape.interp '
		add ( amount := 1, to := 4;
			to + amount
		)
		inc := add() # should return 5
		add(inc, 1)'
		assert_equal 6, out
	end

	def test_complex_return_with_simple_conditional
		out = Tape.interp 'return (1+2*3/4) + (1+2*3/4) if 1 + 2 > 2'
		assert_equal 4, out.value
	end

	def test_truthy_falsy_logic
		assert_equal 1, Tape.interp('if true 1 else 0 end')
		assert_equal 1, Tape.interp('if 0 1 else 0 end') # truthiness follows Ruby's own rules -- only nil/false are falsy, 0 is truthy
		assert_equal 0, Tape.interp('if nil 1 else 0 end')
	end

	def test_returns_with_end_of_line_conditional
		out = Tape.interp 'return 3 if true'
		assert_equal 3, out.value
	end

	def test_standalone_array_index_expr
		out = Tape.interp '4.8.15.16.23.42'
		assert_equal [4, 8, 15, 16, 23, 42], out.values
	end

	def test_array_access_by_dot_index
		out = Tape.interp 'things := [4, 8, 15]
		things.0'
		assert_equal 4, out
	end

	def test_array_nested_non_array_dot_index
		assert_raises Tape::Invalid_Dot_Infix_Left_Operand do
			Tape.interp 'things := [4, 8, 15]
		things.0.1'
		end
	end

	def test_nested_array_access_by_dot_index
		out = Tape.interp 'things := [4, [8, 15, 16], 23, [42, 108, 418, 3]]
		(things.1.0, things.3.1)'
		assert_instance_of Tape::Tuple, out
		assert_equal 8, out.values.first
		assert_equal 108, out.values.last
	end

	def test_function_scope
		out = Tape.interp 'x := 123
		double (; x * 2 )
		double()'
		assert_equal 246, out
	end

	def test_function_scope_some_more
		out = Tape.interp 'x := 108

		Doubler {
			double (; x * 2 )
		}

		Doubler().double()'
		assert_equal 216, out
	end

	def test_returns
		out = Tape.interp 'return 1'
		assert_instance_of Tape::Return, out
		assert_equal 1, out.value

		out = Tape.interp '
		eject (;
			if true
				return "true!"
			end

			return "should not get here"
		)
		eject()'
		assert_equal "true!", out
	end

	def test_type_does_have_new_function
		out = Tape.interp '
		Atom {
			new (;)
		}'
		assert out.has? :new
	end

	def test_instance_does_not_have_new_function
		out = Tape.interp '
		Atom {
			new (;)
		}
		a := Atom()
		b := Atom.new()
		(a, b)'
		refute out.values.first.has? :new
		refute out.values.last.has? :new
	end

	def test_while_loops
		out = Tape.interp '
		x := 0
		while x < 4
			x += 1
		end
		x'
		assert_equal 4, out
	end

	def test_fancy_while_loops
		out = Tape.interp '
		x := 0
		y := 0
		z := 0
		while x < 4
			x += 1
		elwhile y > -8
			y -= 1
		else
			z = 1_516
		end
		(x, y, z)'
		assert_equal [4, -8, 1516], out.values
	end

	def test_until_loops
		out = Tape.interp '
		x := 1
		until x >= 23
			x += 2
		end
		'
		assert_equal 23, out
	end

	def test_fancy_until_loops
		out = Tape.interp '
		x := 1
		y := 0
		until x >= 23
			x += 2
		else
			y = x
		end
		(x, y)
		'
		assert_equal [23, 23], out.values
	end

	def test_control_flows_as_expressions
		out = Tape.interp '
		condition := false
		x := unless condition # Equivalent to "if !condition"
			4
		else
			-4
		end
		'
		assert_equal 4, out
	end

	def test_if_and_unless_control_flows
		out = Tape.interp '
		a := if true
			4
		end

		b := if false
			8
		end

		c := unless true
			15
		end

		d := if not true
			23
		else
			16
		end

		(a, b, c, d)
		'
		assert_equal [4, nil, nil, 16], out.values
	end

	def test_nil_instances_are_shared
		out = Tape.interp '
		x,
		y,

		equal := x == y
		(x, y, equal)'
		assert_equal out.values[0].object_id, out.values[1].object_id
		assert_equal true, out.values[2]
	end

	def test_accessing_declarations_through_type_composition
		out = Tape.interp "
		Vec2 {
			x := 0, y := 0

			new ( x, y;
				self.x = x
				self.y = y
			)

			multiply! ( times;
				self.x *= times
				self.y *= times
			)

		}

		Transform | Vec2 {
			new ( position := Vec2();
				self.x = position.x
				y = position.y
			)

			to_s (;
				'Transform(`x`,`y`)'
			)

			scale! ( value;
				multiply!(value)
			)
		}

		pos := Vec2(4, 8)
		t := Transform(pos)
		a := t.to_s()
		t.scale!(3)
		b := t.to_s()

		# Let's remove Vec2 from a type that composes with Transform
		Xform | Transform ~ Vec2 {}

		(a, b, t)"

		# Testing in order of the values in the tuple
		assert_equal "Transform(4,8)", out.values[0]
		assert_equal "Transform(12,24)", out.values[1]

		assert_instance_of Tape::Instance, out.values[2]
		assert_equal 12, out.values[2][:x]
		assert_equal 24, out.values[2][:y]
	end

	def test_random_composition_example
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			Vec2 {
				x := 0, y := 0

				new ( x, y;
					self.x = x
					self.y = y
				)
			}
			v := Vec2(4, 8)

			Transform | Vec2 {
				new ( position := Vec2();
					self.x = position.x
					y = position.y
				)
			}
			t := Transform(Vec2(15, 16))

			Xform | Transform ~ Vec2 {
				# ~Vec2 removes x and y declarations, but retains Transform's new(;) so unless you declare a new initializer here, you are still required to pass in position arg from Transform, which depends on x and y, which have been removed.
				new ( p: Vec2; )
			}
			x := Xform(v)
			"
			assert_instance_of Tape::Instance, out
			assert_equal ['Xform', 'Transform'], out.types
		end
	end

	def test_union_composition
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp '
			Aa {
				a := 1
			}
			Bb {
				a := 4, b := 2, unique := 10
			}

			Union | Aa | Bb {}

			u := Union()
			(u.a, u.b, u.unique)
			'
			assert_equal [1, 2, 10], out.values
		end
	end

	def test_difference_composition
		shared_code = "
			Aa {
				a := 8
				common := 15
			}

			Bb {
				b := 42
				common := 16
			}

			AaBb | Aa | Bb {}

			Diff | AaBb ~ Bb {
				common := 23
			}

			d := Diff()".freeze

		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "#{shared_code}
			a := Aa()
			b := Bb()
			(d.a, a.common, b.common, d.common)"
			assert_equal [8, 15, 16, 23], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			d.b"
		end
	end

	def test_intersection_composition
		shared_code = "
			Aa { a := 4,  common := 8 }
			Bb { b := 15, common := 16 }

			Intersected | Aa & Bb {}

			i := Intersected()"

		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "#{shared_code}
			i.common"
			assert_equal 8, out
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			i.a"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			i.b"
		end
	end

	def test_symmetric_difference_composition
		shared_code = "
			Aa { a := 4, common := 10 }
			Bb { b := 8, common := 10 }

			Sym_Diff | Aa ^ Bb {}
			s := Sym_Diff()\n"

		out = Tape.interp "#{shared_code} (s.a, s.b)"
		assert_equal [4, 8], out.values

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code} s.common"
		end
	end

	def test_union_composition_is_left_biased
		out = Tape.interp "
		Aa { a := 4 }
		Bb { a := 8 }
		Union | Aa | Bb {}
		Union().a"
		assert_equal 4, out
	end

	def test_composition_with_inbody_declarations
		out = Tape.interp "
		Aa { a := 15 }
		Bb { a := 16, b, }
		Union {
			# With or without space is valid
			| Aa
			|Bb
		}
		u := Union()
		(u.a, u.b)"
		assert_equal [15, nil], out.values
	end

	def test_routes
		out = Tape.interp 'get://some/thing/:id ( id;
			do_something()
		)'

		assert_instance_of Tape::Route, out
		assert_equal 'get', out.http_method.value
		assert_equal 'some/thing/:id', out.path
		assert_equal 1, out.handler.parameters.count
		assert_equal 1, out.handler.expressions.count
	end

	def test_html_element
		out = Tape.interp "My_Div {
			element := 'div'

			id := 'my_div'
			class := 'my_class'
			data_something := 'some data attribute'

			render (;
				'Text content of this div'
			)
		}

		it := My_Div()
		(My_Div, it, it.render())"
		assert_instance_of Tape::Type, out.values[0]
		assert_instance_of Tape::Instance, out.values[1]
		assert_instance_of String, out.values[2]
		assert_equal 'Text content of this div', out.values[2]
	end

	def test_loading_external_source_files
		out = Tape.interp "@load 'tapes/preload.tape', (Bool, Bool())"

		assert_instance_of Tape::Type, out.values[0]
		assert_kind_of Tape::Instance, out.values[1]
		assert_instance_of Tape::Bool, out.values[1]
	end

	def test_standalone_load_into_current_scope
		out = Tape.interp "@load 'test/fixtures/test_module.tape'
		(MODULE_NAME, MODULE_VALUE, module_func(10))"

		assert_instance_of Tape::Tuple, out
		assert_equal "Test_Module", out.values[0]
		assert_equal 42, out.values[1]
		assert_equal 20, out.values[2]
	end

	def test_load_assignment_into_variable_identifier
		out = Tape.interp "mod := @load 'test/fixtures/test_module.tape'
		(mod, mod.MODULE_NAME, mod.MODULE_VALUE, mod.module_func(10))"

		assert_instance_of Tape::Tuple, out
		assert_instance_of Tape::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "mod := @load 'test/fixtures/test_module.tape'
			MODULE_NAME"
		end
	end

	def test_load_assignment_into_class_identifier
		out = Tape.interp "Module := @load 'test/fixtures/test_module.tape'
		(Module, Module.MODULE_NAME, Module.MODULE_VALUE, Module.module_func(10))"

		assert_instance_of Tape::Tuple, out
		assert_instance_of Tape::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "Module := @load 'test/fixtures/test_module.tape'
			MODULE_NAME"
		end
	end

	def test_load_assignment_into_constant_identifier
		out = Tape.interp "MODULE := @load 'test/fixtures/test_module.tape'
		(MODULE, MODULE.MODULE_NAME, MODULE.MODULE_VALUE, MODULE.module_func(10))"

		assert_instance_of Tape::Tuple, out
		assert_instance_of Tape::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "MODULE := @load 'test/fixtures/test_module.tape'
			MODULE_NAME"
		end
	end

	def test_load_same_file_into_multiple_scopes
		out = Tape.interp "
		lib1 := @load 'test/fixtures/test_module.tape'
		lib2 := @load 'test/fixtures/test_module.tape'

		(lib1, lib2, lib1.MODULE_VALUE, lib2.MODULE_VALUE, lib1 != lib2)"

		assert_instance_of Tape::Tuple, out
		assert_instance_of Tape::Scope, out.values[0]
		assert_instance_of Tape::Scope, out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 42, out.values[3]
		assert out.values[4]

		# Scopes are different objects even though loaded from same file
		refute_equal out.values[0].object_id, out.values[1].object_id
	end

	def test_double_loading_file
		assert_raises Tape::Cannot_Reassign_Constant do
			out = Tape.interp "
			@load 'test/fixtures/constants.tape'
			CODE = 123"
		end
	end

	def test_for_loop
		out = Tape.interp "
		NUMBERS := [4, 8, 15, 16, 23, 42]
		numbers := []

		for NUMBERS
			numbers << it
		end

		(numbers == NUMBERS, numbers, NUMBERS)"
		assert out.values[0]
	end

	def test_for_loop_with_scopes
		out = Tape.interp <<~TAPE
		    Numbers {
		    	numbers := []

				new ( numbers;
					self.numbers = numbers
				)

		    	multiply ( by;
					result := []
		    		for self.numbers
		    			result.push(it * by)
		    		end
		    		result
		    	)
		    }

		    Numbers([1, 2, 3]).multiply(2)
		TAPE
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_by_strides
		out = Tape.interp "
		NUMBERS := [4, 8, 15, 16, 23, 42]
		numbers := []

		for NUMBERS by 2
			numbers << it
		end

		numbers"
		assert_equal [[4, 8], [15, 16], [23, 42]], out.values.map(&:values)
	end

	def test_for_loop_at_and_it_builtins
		out = Tape.interp "
		indices := []

		for [4, 8, 15, 16, 23, 42]
			indices << '`at`: `it`'
		end

		indices"
		assert_equal ['0: 4', '1: 8', '2: 15', '3: 16', '4: 23', '5: 42'], out.values
	end

	def test_for_loop_with_ranges
		out = Tape.interp "
		zero := []
		one := []
		two := []
		three := []

		for 1...5
			zero << it
		end

		for 1>.<5
			one << it
		end

		for 1>..5
			two << it
		end

		for 1..<5
			three << it
		end


		(zero, one, two, three)"
		assert_equal [1, 2, 3, 4, 5], out.values[0].values
		assert_equal [2, 3, 4], out.values[1].values
		assert_equal [2, 3, 4, 5], out.values[2].values
		assert_equal [1, 2, 3, 4], out.values[3].values
	end

	def test_for_loop_skip
		out = Tape.interp "
		result := []
		for [1, 2, 3, 4, 5]
			if it == 3
				skip
			end
			result << it
		end
		result"
		assert_equal [1, 2, 4, 5], out.values
	end

	def test_for_loop_stop
		out = Tape.interp "
		result := []
		for [1, 2, 3, 4, 5]
			if it == 3
				stop
			end
			result << it
		end
		result"
		assert_equal [1, 2], out.values
	end

	def test_for_loop_skip_with_index
		out = Tape.interp "
		result := []
		for ['a', 'b', 'c', 'd']
			if at == 1 or at == 2
				skip
			end
			result << it
		end
		result"
		assert_equal ['a', 'd'], out.values
	end

	def test_for_loop_stop_with_index
		out = Tape.interp "
		result := []
		for ['a', 'b', 'c', 'd']
			if at == 2
				stop
			end
			result << it
		end
		result"
		assert_equal ['a', 'b'], out.values
	end

	def test_nested_for_loop_stop
		out = Tape.interp "
		result := []

		for 0...10
			skip if it == 4

			if it % 2 == 0
				result << 'START `it`'
				for 0...10
					result << it
					stop if it == 2
				end
				result << 'STOP `it`'
			end

			if it == 6
				stop
			end
		end

		result
		"
		assert_equal ["START 0", 0, 1, 2, "STOP 0", "START 2", 0, 1, 2, "STOP 2", "START 6", 0, 1, 2, "STOP 6"], out.values
	end

	def test_for_loop_map
		out = Tape.interp "
		for [1, 2, 3, 4, 5] map
			it * 2
		end"
		assert_equal [2, 4, 6, 8, 10], out.values
	end

	def test_for_loop_map_with_index
		out = Tape.interp "
		for ['a', 'b', 'c'] map
			'`at`:`it`'
		end"
		assert_equal ['0:a', '1:b', '2:c'], out.values
	end

	def test_for_loop_map_with_stride
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6] map by 2
			it.0 + it.1
		end"
		assert_equal [3, 7, 11], out.values
	end

	def test_for_loop_select
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6] select
			it % 2 == 0
		end"
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_select_with_index
		out = Tape.interp "
		for ['a', 'b', 'c', 'd', 'e'] select
			at < 3
		end"
		assert_equal ['a', 'b', 'c'], out.values
	end

	def test_for_loop_select_with_stride
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] select by 2
			it.0 + it.1 > 5
		end"
		assert_equal [[3, 4], [5, 6], [7, 8]], out.values.map(&:values)
	end

	def test_for_loop_reject
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6] reject
			it % 2 == 0
		end"
		assert_equal [1, 3, 5], out.values
	end

	def test_for_loop_reject_with_index
		out = Tape.interp "
		for ['a', 'b', 'c', 'd', 'e'] reject
			at < 2
		end"
		assert_equal ['c', 'd', 'e'], out.values
	end

	def test_for_loop_reject_with_stride
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] reject by 2
			it.0 + it.1 > 5
		end"
		assert_equal [[1, 2]], out.values.map(&:values)
	end

	def test_for_loop_count
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6] count
			it % 2 == 0
		end"
		assert_equal 3, out
	end

	def test_for_loop_count_with_index
		out = Tape.interp "
		for ['a', 'b', 'c', 'd', 'e'] count
			at >= 2
		end"
		assert_equal 3, out
	end

	def test_for_loop_count_with_stride
		out = Tape.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] count by 2
			it.0 + it.1 > 5
		end"
		assert_equal 3, out
	end

	def test_for_loop_map_with_skip
		out = Tape.interp "
		for [1, 2, 3, 4, 5] map
			skip if it == 3
			it * 2
		end"
		assert_equal [2, 4, nil, 8, 10], out.values
	end

	def test_for_loop_map_with_stop
		out = Tape.interp "
		for [1, 2, 3, 4, 5] map
			stop if it == 4
			it * 2
		end"
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_verbs_do_not_mutate
		out = Tape.interp "
		original := [1, 2, 3, 4, 5]
		doubled := for original map
			it * 2
		end
		original"
		assert_equal [1, 2, 3, 4, 5], out.values
	end

	def test_while_loop_skip
		out = Tape.interp "
		result := []
		x := 0
		while x < 5
			x += 1
			if x == 3
				skip
			end
			result << x
		end
		result"
		assert_equal [1, 2, 4, 5], out.values
	end

	def test_while_loop_stop
		out = Tape.interp "
		result := []
		x := 0
		while x < 10
			x += 1
			if x == 4
				stop
			end
			result << x
		end
		result"
		assert_equal [1, 2, 3], out.values
	end

	def test_until_loop_skip
		out = Tape.interp "
		result := []
		x := 0
		until x >= 5
			x += 1
			if x == 2 or x == 4
				skip
			end
			result << x
		end
		result"
		assert_equal [1, 3, 5], out.values
	end

	def test_until_loop_stop
		out = Tape.interp "
		result := []
		x := 0
		until x >= 10
			x += 1
			if x == 3
				stop
			end
			result << x
		end
		result"
		assert_equal [1, 2], out.values
	end

	def test_readable_unpack_parameter
		out = Tape.interp "
		Vector {
			x := 0
			y := 0

			new ( x, y;
				self.x = x
				self.y = y
			)
		}

		add ( @add_readable_scope vec;
			x + y
		)

		v := Vector(3, 4)
		add(v)"
		assert_equal 7, out
	end

	def test_readable_unpack_with_identifier
		out = Tape.interp "
		Point {
			a := 0
			b := 0


			new ( a, b;
				self.a = a
				self.b = b
			)
		}

		calc (;
			p := Point(10, 20)
			@add_readable_scope p
			a + b
		)

		calc()"
		assert_equal 30, out
	end

	def test_readable_unpack_with_local_declarations
		out = Tape.interp "
		Point {
			a := 0
			b := 0

			new ( a, b;
				self.a = a
				self.b = b
			)
		}

		p := Point(4, 8)
		@add_readable_scope p
		one := a + b
		@remove_readable_scope p

		@add_readable_scope Point(15, 16)
		(one, a + b)"
		assert_equal [12, 31], out.values
	end

	def test_unpack_and_nested_functions
		out = Tape.interp "
		Point {
			a := 0
			b := 0

			new ( a, b;
				self.a = a
				self.b = b
			)
		}

		outer (;
			p := Point(23, 42)
			@add_readable_scope p

			inner (;
				a + b
			)

			inner()
		)
		outer()"
		assert_equal 65, out
	end

	def test_readable_unpack_write_shadows_local_and_leaves_source_untouched
		# `x = 999` is allowed (finds x via the readable fallback), but Scope#[]= never routes through readable_scopes, so it lands as a fresh local instead, leaving vec untouched.
		out = Tape.interp "
		Vector {
			x := 0
			new ( x; self.x = x )
		}

		add ( @add_readable_scope vec;
			x = 999
			x
		)

		v := Vector(3)
		local_result := add(v)
		(local_result, v.x)"
		assert_equal [999, 3], out.values
	end

	def test_privacy_and_binding
		shared_code = <<~CODE
		    Type {
				# Instance declarations
		    	number := 4
		    	_private := 8

				# Static declarations
				Self.nilled,
		    	Self.static := 15
		    	Self._static_private := 16

				calling_private_through_instance (; _private )
		    	calling_static_through_instance (; static )
		    	calling_static_private_through_instance (; _static_private )

		    	Self.calling_static_through_static (; static )
		    	Self.calling_static_private_through_static (; _static_private )
		    }
		CODE

		out = Tape.interp "#{shared_code}
		Type().number"
		assert_equal 4, out

		out = Tape.interp "#{shared_code}
		Type().calling_private_through_instance()"
		assert_equal 8, out

		out = Tape.interp "#{shared_code}
		Type().static"
		assert_equal 15, out

		out = Tape.interp "#{shared_code}
		Type().calling_static_through_instance()"
		assert_equal 15, out

		out = Tape.interp "#{shared_code}
		Type().calling_static_private_through_instance()"
		assert_equal 16, out

		out = Tape.interp "#{shared_code}
		Type.calling_static_through_static()"
		assert_equal 15, out

		out = Tape.interp "#{shared_code}
		Type.calling_static_private_through_static()"
		assert_equal 16, out

		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Type()._private"
		end

		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Type()._static_private"
		end

		assert_raises Tape::Cannot_Call_Private_Static_Member_On_Type do
			Tape.interp "#{shared_code}
			Type._static_private"
		end

		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "
			Inner { _secret := 42 }
		    Outer { inner := Inner() }
            Outer().inner._secret"
		end

		out = Tape.interp "#{shared_code}
		Type.static = 4815
		Type.static"
		assert_equal 4815, out

		out = Tape.interp "#{shared_code}
		Type.nilled"
		assert_nil out

		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Type()._private = 100"
		end

		assert_raises Tape::Cannot_Call_Private_Static_Member_On_Type do
			Tape.interp "#{shared_code}
		    Type._static_private = 100"
		end

		assert_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Tape.interp "#{shared_code}
			Type.number"
		end

		assert_raises Tape::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Tape.interp "../whatever"
		end

		assert_raises Tape::Invalid_Scope_Syntax do
			Tape.interp "../123"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "Type { ../whatever }"
		end

		assert_raises Tape::Invalid_Scope_Syntax do
			x Tape.interp "Type { ../123 }"
		end
	end

	def test_proxy_string_members
		out = Tape.interp "String().length"
		assert_equal 0, out

		out = Tape.interp "'hello'.length"
		assert_equal 5, out

		out = Tape.interp "'a'.ord"
		assert_equal 97, out

		out = Tape.interp "'A'.ord"
		assert_equal 65, out

		out = Tape.interp "'walt!'.upcase()"
		assert_equal "WALT!", out

		out = Tape.interp "'WALT!'.downcase()"
		assert_equal "walt!", out

		assert_raises Tape::Invalid_Ruby_Proxy_Directive_Usage do
			Tape.interp "@ruby whatever"
		end

		assert_raises Tape::Invalid_Ruby_Proxy_Directive_Usage do
			Tape.interp "@ruby 123"
		end

		assert_raises Tape::Invalid_Ruby_Proxy_Directive_Usage do
			Tape.interp "Type { @ruby 123, }"
		end
	end

	def test_binding_and_privacy_with_composition
		shared_code = <<~CODE
		    Base {
		    	base_instance_public := 1
		    	_base_instance_private := 2

		    	Self.base_static_public := 10
		    	Self._base_static_private := 20
		    }

		    Other {
		    	other_instance := 3
		    	_other_private := 4

		    	Self.other_static_public := 30
		    	Self._other_static_private := 40
		    }
		CODE

		# Union composition - should merge all members
		out = Tape.interp "#{shared_code}
		Merged | Base | Other {}
		m := Merged()
		(m.base_instance_public, m.other_instance)"
		assert_equal [1, 3], out.values

		# Static members accessible from union
		out = Tape.interp "#{shared_code}
		Merged | Base | Other {}
		Merged.base_static_public"
		assert_equal 10, out

		out = Tape.interp "#{shared_code}
		Merged | Base | Other {}
		Merged.other_static_public"
		assert_equal 30, out

		# Instance can access static from union
		out = Tape.interp "#{shared_code}
		Merged | Base | Other {}
		Merged().base_static_public"
		assert_equal 10, out

		# Privacy preserved through union
		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Merged | Base | Other {}
			Merged()._base_instance_private"
		end

		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Merged | Base | Other {}
			Merged()._other_private"
		end

		assert_raises Tape::Cannot_Call_Private_Static_Member_On_Type do
			Tape.interp "#{shared_code}
			Merged | Base | Other {}
			Merged._base_static_private"
		end

		# Binding preserved - cannot access instance members on Type
		assert_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Tape.interp "#{shared_code}
			Merged | Base | Other {}
			Merged.base_instance_public"
		end

		assert_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Tape.interp "#{shared_code}
			Merged | Base | Other {}
			Merged.other_instance"
		end

		# Difference composition - static members removed correctly
		out = Tape.interp "#{shared_code}
		Diff | Base ~ Other {}
		Diff().base_instance_public"
		assert_equal 1, out

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Diff | Base ~ Other {}
			Diff().other_instance"
		end

		# Static members also removed
		out = Tape.interp "#{shared_code}
		Diff | Base ~ Other {}
		Diff.base_static_public"
		assert_equal 10, out

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Diff | Base ~ Other {}
			Diff.other_static_public"
		end

		# Privacy maintained after difference
		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Diff | Base ~ Other {}
			Diff()._base_instance_private"
		end

		# Intersection composition - keeps only shared members
		shared_code = <<~CODE
		    Left {
		    	shared_instance := 1
		    	_shared_private := 2
		    	left_only := 3

		    	Self.shared_static := 10
		    	Self._shared_static_private := 20
		    	Self.left_static_only := 30
		    }

		    Right {
		    	shared_instance := 4
		    	_shared_private := 5
		    	right_only := 6

		    	Self.shared_static := 40
		    	Self._shared_static_private := 50
		    	Self.right_static_only := 60
		    }
		CODE

		# Intersection keeps shared instance members
		out = Tape.interp "#{shared_code}
		Inter | Left & Right {}
		Inter().shared_instance"
		assert_equal 1, out

		# Intersection removes non-shared instance members
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter().left_only"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter().right_only"
		end

		# Intersection keeps shared static members
		out = Tape.interp "#{shared_code}
		Inter | Left & Right {}
		Inter.shared_static"
		assert_equal 10, out

		# Intersection removes non-shared static members
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.left_static_only"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.right_static_only"
		end

		# Privacy preserved through intersection
		assert_raises Tape::Cannot_Call_Private_Instance_Member do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter()._shared_private"
		end

		assert_raises Tape::Cannot_Call_Private_Static_Member_On_Type do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter._shared_static_private"
		end

		# Binding preserved through intersection
		assert_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Tape.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.shared_instance"
		end

		# Symmetric difference composition - keeps only non-shared members
		# Symmetric diff keeps unique instance members from Left
		out = Tape.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym().left_only"
		assert_equal 3, out

		# Symmetric diff keeps unique instance members from Right
		out = Tape.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym().right_only"
		assert_equal 6, out

		# Symmetric diff removes shared instance members
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym().shared_instance"
		end

		# Symmetric diff keeps unique static members from Left
		out = Tape.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym.left_static_only"
		assert_equal 30, out

		# Symmetric diff keeps unique static members from Right
		out = Tape.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym.right_static_only"
		assert_equal 60, out

		# Symmetric diff removes shared static members
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym.shared_static"
		end

		# Binding preserved through symmetric difference
		assert_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Tape.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym.left_only"
		end
	end

	def test_static_declarations_fixture
		out = Tape.interp_file 'test/fixtures/static_declarations.tape'
		assert_equal true, out
	end

	def test_puts_directive
		output          = StringIO.new
		original_stdout = $stdout
		$stdout         = output

		begin
			result = Tape.interp "@puts 'Walt!'"
			assert_equal 'Walt!', result
			# @puts now reflects the argument's own quote char when it's a literal.
			assert_equal "'Walt!'\n", output.string
		ensure
			$stdout = original_stdout
		end
	end

	def test_multiple_unpacks
		shared_code = <<~TAPE
		    Point {
		    	a := 0
		    	b := 0

		    	new ( a, b;
		    		self.a = a
		    		self.b = b
		    	)
		    }
		TAPE

		out = Tape.interp "#{shared_code}
		p := Point(4, 8)
		@add_readable_scope p
		(a, b)"
		assert_equal [4, 8], out.values

		# note: Unpacks function like a stack, the most recent unpack is the one whose identifier takes precedence.
		out = Tape.interp "#{shared_code}
		p := Point(4, 8)
		p2 := Point(15, 16)
		@add_readable_scope p
		@add_readable_scope p2
		(a, b)"
		assert_equal [15, 16], out.values

		out = Tape.interp "#{shared_code}
		p := Point(4, 8)
		p2 := Point(15, 16)
		@add_readable_scope p
		@remove_readable_scope p2
		(a, b)"
		assert_equal [4, 8], out.values
	end

	def test_using_pound_proxy_as_expression
		code = <<~CODE
		    String | String {
		        upcase (;
		        	@ruby + " (SWIZZLED)"
		        )
		    }
			"test".upcase()
		CODE
		assert_equal "TEST (SWIZZLED)", Tape.interp(code)
	end

	def test_reading_files
		out = Tape.interp "File_System.read_file_to_string('test/fixtures/hello_read.txt')"
		assert_equal "Hello, Read!\n", out.value # note: There is a newline at the end of the file, so it has to be included here
	end

	def test_html_fence_with_interpolation
		out = Tape.interp "
		name := 'Cooper'
		```html
		<h1>Welcome `name`</h1>
		```"
		assert_instance_of ::String, out
		assert_equal '<h1>Welcome Cooper</h1>', out.strip
	end

	def test_html_fence_without_interpolation
		out = Tape.interp '```html
		<p>Plain text</p>
		```'
		assert out.include?('<p>Plain text</p>')
	end

	def test_html_fence_in_route_handler
		out = Tape.interp "
		@load 'tapes/server.tape'

		App | Server {
			get:// home (;
				title := 'My Page'
				```html
				<h1>`title`</h1>
				```
			)
		}

		app := App()
		app.home()"
		assert out.include?('<h1>My Page</h1>')
	end

	def test_html_fence_multiline_with_interpolation
		out = Tape.interp "
		name := 'Alice'
		count := 42
		```html
		<div>
			<h1>Hello `name`</h1>
			<p>You have `count` messages</p>
		</div>
		```"
		assert out.include?('Hello Alice')
		assert out.include?('You have 42 messages')
	end

	# note: The idea is, given (abc,1)
	# if abc exists, use that value
	# if not abc exists, declare abc=nil
	def test_walrus_basic_assignment
		assert_equal 4, Tape.interp('x := 4, x')
		assert_equal 'hello', Tape.interp('x := "hello", x')
	end

	def test_walrus_reinitializes_type
		assert_equal 'hello', Tape.interp('x := 4, x := "hello", x')
	end

	def test_walrus_same_type_reassign_with_equals
		assert_equal 8, Tape.interp('x := 4, x = 8, x')
	end

	def test_walrus_type_contract_violation
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'x := 4, x = "hello"'
		end
	end

	def test_walrus_contract_violation_message
		err = assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'x := 4, x = "hello"'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message
	end

	def test_manual_type_annotation_contract
		err = assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'x: Number = 4, x = "hey"'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message

		# Fine if redeclared
		Tape.interp 'x: Number = 4, x := "hey"'

		err = assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'x: Number = 4, x := "hey", x = 8'
		end
		assert_match 'Number', err.message # the actual value 8 -- reported as the family name
		assert_match 'String', err.message
	end

	# `x: Number = 'oops'` (a literal RHS) is caught statically before the interpreter ever runs (see type_checker_test.rb) -- these cover the gap that leaves open: a *non-literal* RHS (an identifier, a function, ...) whose actual value mismatches the annotation on the very first, self-declaring assignment. The static checker silently skips non-literal RHS entirely, so this has to be caught dynamically in #interp_infix_assignment, the same place reassignment already is.
	def test_first_assignment_type_contract_with_non_literal_rhs
		# Plain nominal annotation.
		err = assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'bad := "oops"
				x: Number = bad'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message

		# Signature-typed annotation, assigning a real function whose actual shape doesn't match.
		err = assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'wrong ( a, b; a + b )
				x: (Number -> String;) = wrong'
		end
		assert_match '(Number -> String;)', err.message

		# Inline signature form (no separate alias), same check.
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'wrong ( a, b; a + b )
				x: (Number -> String;) = wrong'
		end

		# Same check applies to a typed member declared inside a Type/Instance body, not just top level.
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'bad := "oops"
				Thing {
					x: Number = bad
				}
				Thing()'
		end

		# And inside a constructor, self-declaring from a param.
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp 'Thing {
					new ( v;
						x: Number = v
					)
				}
				Thing("oops")'
		end
	end

	def test_new_comma_nil_init
		assert_raises(Tape::Undeclared_Identifier) do
			Tape.interp <<~CODE
			    x := (abc,1)
				(x, abc)
			CODE
		end

		out = Tape.interp <<~CODE
		    abc := 2, (abc,1),
		CODE
		assert_equal [2, 1], out.values
	end

	def test_neat_usage_of_operator_overloads
		prelude = <<~CODE
		    Clock {
		    	hour, minute, second,
		    	period, # am/pm
		    }

		    @operator : @infix 700 ( hour, minute;
		    	time := Clock()
		    	time.hour = hour
		    	time.minute = minute
		    	time
		    )

		    @operator pm @postfix 600 ( left: Clock;
		        left.period = 'pm'
		        left
		    )
		CODE

		out = Tape.interp <<~CODE
		    #{prelude}
			# You can now make `11:22pm` evaluate to something!
			11:22pm
		CODE
		assert_instance_of Tape::Instance, out
		assert_equal 11, out.get('hour')
		assert_equal 22, out.get('minute')
		assert_equal 'pm', out.get('period')
	end

	def test_prefix_operator_overload
		out = Tape.interp <<~CODE
		    Currency {
		    	amount,
		    	name,
		    	code,
		    }

		    @operator $ @prefix 900 ( amount;
		    	c := Currency()
		    	c.amount = amount
		    	c.name = 'US Dollar'
		    	c.code = 'USD'
		    	c
		    )

		    $42
		CODE
		assert_instance_of Tape::Instance, out
		assert_equal 42, out.get('amount')
		assert_equal 'US Dollar', out.get('name')
		assert_equal 'USD', out.get('code')
	end

	def test_operator_overload_scoped_to_function
		out = Tape.interp <<~CODE
		    scoped_result := compute (;
		    	@operator + @infix 700 ( left, right;
		    		left * right
		    	)
		    	3 + 4
		    )

		    normal_result := 3 + 4

		    [scoped_result(), normal_result]
		CODE

		assert_equal [12, 7], out.values
	end

	def test_whacky_prefix_operator_overload
		out = Tape.interp <<~CODE
		    @operator !! @prefix 900 ( n;
		    	n * n
		    )

		    !!5
		CODE
		assert_equal 25, out
	end

	def test_pipeing_with_operator_overloads
		out = Tape.interp <<~CODE
		    @operator -> @infix 300 ( left, right;
		    	right(left)
		    )

		    double ( n;
				n * 2
			)

		    add_fifteen ( n;
				n + 15
			)

		    4 -> double -> add_fifteen
		CODE
		assert_equal 23, out
	end

	def test_string_interpolation_can_see_custom_operators_declared_elsewhere_in_the_program
		# Same operators/functions as the test above, interpolated instead -- used to only evaluate to "4" (stopped at the first token it didn't recognize), since interp_string re-parsed the substring in total isolation from the rest of the program's @operator registrations.
		out = Tape.interp <<~CODE
		    @operator -> @infix 300 ( left, right;
		    	right(left)
		    )

		    double ( n;
		    	n * 2
		    )

		    add_fifteen ( n;
		    	n + 15
		    )

		    "`4 -> double -> add_fifteen`"
		CODE
		assert_equal '23', out
	end

	def test_dictionary_in_for_loops
		out = Tape.interp <<~CODE
		    dict := {
		    	x = 4,
		    	y = 8
		    }

		    collection := []
		    for dict
		    	collection << (at, it) # at is the string key, it is the vlaue
		    end

		    collection
		CODE
		assert_equal 2, out.values.count
		assert_equal [Tape::Tuple.new([:x, 4]), Tape::Tuple.new([:y, 8])], out.values
	end

	def test_dictionary_in_for_loops_key_and_value_builtins
		out = Tape.interp <<~CODE
		    dict := {
		    	x = 4,
		    	y = 8
		    }

		    collection := []
		    for dict
		    	collection << (key, value)
		    end

		    collection
		CODE
		assert_equal 2, out.values.count
		assert_equal [Tape::Tuple.new([:x, 4]), Tape::Tuple.new([:y, 8])], out.values
	end

	def test_dictionary_in_for_loops_stride_is_ignored
		out = Tape.interp <<~CODE
		    dict := {
		    	a = 15,
		    	b = 16,
				c = 23
		    }

		    collection := []
		    for dict by 2
		    	collection << (at, it) # at is the string key, it is the vlaue
		    end

		    collection
		CODE
		assert_equal 3, out.values.count
		assert_equal [Tape::Tuple.new([:a, 15]), Tape::Tuple.new([:b, 16]), Tape::Tuple.new([:c, 23])], out.values
	end

	def test_type_comparison_operators
		shared = <<~CODE
		    Num {}
		CODE
		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
		    Right | Num {}
			l := Left()
			r := Right()
			(Left === Right, Left === Left, l === r, l === l)
		CODE
		assert_equal [false, true, false, true], out.values

		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
		    Right | Num {}
			l := Left()
			r := Right()
			(Left =!= Right, Right =!= Right, l =!= r, r =!= r)
		CODE
		assert_equal [true, false, true, false], out.values

		# Siblings that only share a common composed base (Num) are NOT comparable via =/= -- neither one's types are a subset of theother's, even though they overlap. This is what distinguishes =/= from a plain "do these share any composed type" check.
		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
		    Right | Num {}
			l := Left()
			r := Right()
			(Left =>= Right, Right =>= Left, l =>= r, r =>= l)
		CODE
		assert_equal [false, false, false, false], out.values

		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
		    Right | Num {}
			l := Left()
			r := Right()
			(Left =<= Right, Right =<= Left, l =<= r, r =<= l)
		CODE
		assert_equal [false, false, false, false], out.values

		# `A =>= B` is true when A's composed types are a superset of B's -- i.e. A composes with at least everything B does. Left composes Num, so Left has "at least" Num, but not the other way around.
		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
			l := Left()
			n := Num()
			(Left =>= Num, Num =>= Left, Left =>= Left, l =>= n, n =>= l)
		CODE
		assert_equal [true, false, true, true, false], out.values

		# =<= mirrors =>= with the operands' roles reversed.
		out = Tape.interp <<~CODE
			#{shared}
		    Left | Num {}
			l := Left()
			n := Num()
			(Num =<= Left, Left =<= Num, Left =<= Left, n =<= l, l =<= n)
		CODE
		assert_equal [true, false, true, true, false], out.values

		# `A =/= B` is true when A and B share no composed types at all. A/B share nothing. Left/Right both compose Num, so they're not disjoint even though neither composes the other. Left/Num aren't disjoint either, since Left composes Num directly.
		out = Tape.interp <<~CODE
			#{shared}
		    Aa {}
		    Bb {}
		    Left | Num {}
		    Right | Num {}
			a := Aa()
			b := Bb()
			l := Left()
			r := Right()
			(Aa =/= Bb, Aa =/= Aa, Left =/= Right, Left =/= Num, a =/= b, l =/= r, l =/= Num)
		CODE
		assert_equal [true, false, false, false, true, false, false], out.values
	end

	# `Any` (tapes/preload.tape) is a universal wildcard -- everything except nil counts as Any via `==`/`===`, with no composition required (`Thing | Any {}` isn't needed).
	def test_any_type_is_universally_equal_via_double_and_triple_equals
		out = Tape.interp <<~CODE
		    Thing { x := 1 }
		    t := Thing()
		    (String == Any, Any == String, Number == Any, Thing == Any, t == Any, Any == t, 4 == Any, 'hi' == Any)
		CODE
		assert_equal [true, true, true, true, true, true, true, true], out.values

		out = Tape.interp <<~CODE
		    Thing { x := 1 }
		    t := Thing()
		    (String === Any, Any === String, t === Any, Any === t)
		CODE
		assert_equal [true, true, true, true], out.values
	end

	# nil is the one thing that doesn't count as Any -- "if you're not nil, you're Any at the very least" stops short of nil itself.
	def test_nil_is_not_any
		out = Tape.interp '(nil == Any, Any == nil, nil === Any, Any === nil)'
		assert_equal [false, false, false, false], out.values
	end

	# != / =!= are the natural negation, kept consistent with == / === above rather than falling through to identity-based comparison.
	def test_any_type_negated_comparisons_stay_consistent
		out = Tape.interp '(String != Any, Any != String, String =!= Any, Any =!= String)'
		assert_equal [false, false, false, false], out.values

		out = Tape.interp '(nil != Any, Any != nil, nil =!= Any, Any =!= nil)'
		assert_equal [true, true, true, true], out.values
	end

	# `===` is documented as "mutual `=>=`" -- Any wouldn't actually be a universal supertype if `X === Any` were true while `X =>= Any` stayed false, so `=>=`/`=<=`/`=/=` get the same wildcard treatment as `==`/`===` above, not just the two operators the feature originally shipped with.
	def test_any_type_is_universal_via_superset_and_disjoint_operators
		out = Tape.interp '(String =>= Any, Any =>= String, String =<= Any, Any =<= String)'
		assert_equal [true, true, true, true], out.values

		# Any is never disjoint from anything non-nil -- the same "you're Any at the very least" rule.
		out = Tape.interp '(String =/= Any, Any =/= String)'
		assert_equal [false, false], out.values

		# nil stays the one exception here too: not a superset relationship, and disjoint (shares nothing).
		out = Tape.interp '(nil =>= Any, Any =>= nil, nil =<= Any, Any =<= nil, nil =/= Any, Any =/= nil)'
		assert_equal [false, false, false, false, true, true], out.values
	end

	def test_regex_match_operators
		# =~ behaves like Ruby's String#=~: returns the match index, or nil.
		assert_equal 5, Tape.interp("'hello123' =~ '\\d+'")
		assert_nil Tape.interp("'hello' =~ '\\d+'")

		# !~ is the boolean negation of a match.
		assert_equal false, Tape.interp("'hello123' !~ '\\d+'")
		assert_equal true, Tape.interp("'hello' !~ '\\d+'")

		# Works through variables too, not just literals.
		out = Tape.interp <<~CODE
		    x := 'foo_bar'
		    x =~ '_'
		CODE
		assert_equal 3, out

		out = Tape.interp <<~CODE
		    x := 'foobar'
		    x !~ '_'
		CODE
		assert_equal true, out
	end

	def test_function_signatures
		out = Tape.interp 'Num_To_Str := (Number -> String;)'
		assert_kind_of Tape::Func_Signature, out
		assert_equal ['Number'], out.param_types
		assert_equal 'String', out.return_type

		# Named + typed param — the name is discarded, only the type survives.
		out = Tape.interp '(a: Number -> String;)'
		assert_equal ['Number'], out.param_types
		assert_equal 'String', out.return_type

		# Zero-arg signature.
		out = Tape.interp '(-> String;)'
		assert_equal [], out.param_types
		assert_equal 'String', out.return_type

		# Bare and named+typed params can mix in the same param list.
		out = Tape.interp '(Number, a: Number -> String;)'
		assert_equal %w(Number Number), out.param_types
		assert_equal 'String', out.return_type

		# Named param with no type annotation is a malformed signature — every param slot in a signature literal must carry a type.
		assert_raises Tape::Invalid_Func_Signature do
			Tape.interp '(a -> String;)'
		end

		# Bare as a top-level expression, not just as the RHS of :=.
		out = Tape.interp '(Number -> String;)'
		assert_kind_of Tape::Func_Signature, out

		# Regression: an ordinary Type declaration with a method must still parse as a real type — now unambiguous, since a signature literal never starts with a Capitalized type name anymore.
		out = Tape.interp <<~CODE
		    Person {
		    	greet (; "hi" )
		    }
		    Person().greet()
		CODE
		assert_equal 'hi', out
	end

	def test_function_return_type_enforcement
		# Declared return type matches what's actually returned.
		out = Tape.interp <<~CODE
		    identity ( a: Number -> Number; a )
		    identity(5)
		CODE
		assert_equal 5, out

		# Return types are not validated until the functino is called, so this will not raise a contra t violation
		refute_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    identity ( a: Number -> String; 'not a number' )
			CODE
		end

		# Declared return type doesn't match the actual value.
		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    identity ( a: Number -> Number; 'not a number' )
			    identity(5)
			CODE
		end
		assert_equal 'Number', error.contract
		assert_equal 'String', error.actual

		# A signature has no implementation, so it can't be called.
		assert_raises Tape::Cannot_Call_Func_Signature do
			Tape.interp <<~CODE
			    double: (Number -> Number;)
			    double()
			CODE
		end

		refute_raises Tape::Cannot_Call_Func_Signature do
			Tape.interp <<~CODE
			    double: (Number -> Number;) = (a: Number -> Number; a*2)
			    double(2)
			CODE
		end

		# No declared return type — nothing is checked, any value is fine.
		out = Tape.interp <<~CODE
		    identity ( a; 'anything' )
		    identity(5)
		CODE
		assert_equal 'anything', out

		# Signature-only declarations have no body, so there's nothing to enforce against — declaring one must not raise.
		out = Tape.interp <<~CODE
		    double: (Number -> Number;)
		    'ok'
		CODE
		assert_equal 'ok', out

		# A function (anonymous or named) can declare its own return type inline, at the end of its param list, instead of via the `name: Type { }` prefix.
		out = Tape.interp <<~CODE
		    f := ( a: Number -> Number; a * 2 )
		    f(21)
		CODE
		assert_equal 42, out

		out = Tape.interp <<~CODE
		    example ( a: Number -> Number; a * 2 )
		    example(21)
		CODE
		assert_equal 42, out

		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    f := ( a: Number -> Number; 'oops' )
			    f(1)
			CODE
		end
		assert_equal 'Number', error.contract
		assert_equal 'String', error.actual
	end

	# The return-type check used to compare only the value's own primary type name, not its full composed-type set -- a value composed with (not literally named) the declared return type was wrongly rejected as a mismatch, even though returning it is exactly the safe, covariant case (every Task IS a Table).
	def test_function_return_type_enforcement_accepts_composed_types
		out = Tape.interp <<~CODE
		    Table {}
		    Task | Table {}
		    make ( -> Table; Task() )
		    make().types
		CODE
		assert_equal %w(Task Table), out.values

		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    Table {}
			    Unrelated {}
			    make ( -> Table; Unrelated() )
			    make()
			CODE
		end
		assert_equal 'Table', error.contract
		assert_equal 'Unrelated', error.actual
	end

	def test_function_signature_matching
		# A function whose actual shape matches the signature succeeds, both on first declaration and on reassignment.
		out = Tape.interp <<~CODE
		    Num_to_str := (Number -> String;)
		    stringify ( n: Number -> String; 'x' )
		    to_string: Num_to_str = stringify
		    another ( n: Number -> String; 'y' )
		    to_string = another
		    'ok'
		CODE
		assert_equal 'ok', out

		# First declaration with a mismatched shape raises immediately.
		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    Num_to_str := (Number -> String;)
			    to_string: Num_to_str = ( x, y; x + y )
			CODE
		end
		assert_equal '(Number -> String;)', error.contract
		assert_equal '(, -> ;)', error.actual

		# Reassigning an already-valid signature-typed identifier to a mismatched shape raises too, comparing structurally rather than as a plain type name.
		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    Num_to_str := (Number -> String;)
			    stringify ( n: Number -> String; 'x' )
			    to_string: Num_to_str = stringify
			    to_string = ( x, y; x + y )
			CODE
		end
		assert_equal '(Number -> String;)', error.contract
		assert_equal '(, -> ;)', error.actual

		# Ordinary nominal type annotations are unaffected by signature resolution.
		out = Tape.interp <<~CODE
		    x: Number = 4
		    x = 8
		    x
		CODE
		assert_equal 8, out

		assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    x: Number = 4
			    x = 'oops'
			CODE
		end

		# First declaration of an ordinary nominal type is now checked too, even
		# with a non-literal RHS the static checker can't see.
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    n := 4
			    x: String = n
			CODE
		end
	end

	def test_tuple_and_struct_destructuring
		# Tuple source.
		out = Tape.interp <<~CODE
		    (a, b) := (1, 2)
		    a + b
		CODE
		assert_equal 3, out

		# Struct source.
		out = Tape.interp <<~CODE
		    (a, b) := <1, 2>
		    a + b
		CODE
		assert_equal 3, out

		# Both targets are declared in the current scope, independently readable afterward.
		out = Tape.interp <<~CODE
		    (a, b) := <Number,Number>(10, 20)
		    (a, b)
		CODE
		assert_equal [10, 20], out.values

		# An explicit `: Type` per target is checked against that position's extracted value.
		out = Tape.interp <<~CODE
		    (x: Number, y) := (1, 2)
		    x
		CODE
		assert_equal 1, out

		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp '(x: String, y) := (1, 2)'
		end
		assert_equal 'String', error.contract
		assert_equal 'Number', error.actual

		# Asking for more values than the source has raises, rather than padding with nil.
		error = assert_raises Tape::Destructuring_Arity_Mismatch do
			Tape.interp '(a, b, c) := <Number, Number>(1, 2)'
		end
		assert_equal 3, error.expected
		assert_equal 2, error.actual

		# Asking for fewer is fine -- the rest are just discarded.
		out = Tape.interp '(a, b) := <1, 2, 3>
			a + b'
		assert_equal 3, out

		# Only a Tuple/Struct can be destructured.
		assert_raises Tape::Invalid_Destructuring_Source do
			Tape.interp '(a, b) := 5'
		end

		# Every target must be a plain identifier or an existing-member dot-target.
		assert_raises Tape::Invalid_Destructuring_Target do
			Tape.interp '(1, c) := (1, 2)'
		end

		out = Tape.interp 'a := 0
			(a, b) := (1, 2)
			(a,b)'
		assert_equal [1, 2], out.values
	end

	def test_member_destructuring_targets
		# `thing.member` reassigns an existing member, same as plain `thing.member = value`.
		out = Tape.interp <<~CODE
		    Thing { member, new (; self.member = 0 ) }
		    thing := Thing()
		    (thing.member, local) := <Number, Number>(1, 1)
		    (thing.member, local)
		CODE
		assert_equal [1, 1], out.values

		# The member must already exist -- destructuring can't silently create one.
		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp <<~CODE
			    Thing { member, new (; self.member = 0 ) }
			    thing := Thing()
			    (thing.missing, local) := <Number, Number>(1, 1)
			CODE
		end

		# A constant member can't be reassigned this way either.
		assert_raises Tape::Cannot_Reassign_Constant do
			Tape.interp <<~CODE
			    Thing { MEMBER, new (; self.MEMBER = 0 ) }
			    thing := Thing()
			    (thing.MEMBER, local) := <Number, Number>(1, 1)
			CODE
		end

		# If the member has a previously-recorded type (via `:=`), the extracted value must match it.
		error = assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    Thing {
					new (;
						self.member := 0
					)
				}
			    thing := Thing()
			    (thing.member, local) := <String, Number>("oops", 1)
			CODE
		end
		assert_equal 'Number', error.contract
		assert_equal 'String', error.actual
	end

	def test_struct_member_display_regression
		out = Tape.interp <<~CODE
		    @load 'tapes/struct.tape'
		    quad := <1, id := 2, ix: Number, String>(4, 8, 1, "five")
		    quad.to_s()
		CODE
		assert_equal '<4, id: Number = 8, ix: Number = 1, "five">', out

		out = Tape.interp <<~CODE
		    @load 'tapes/struct.tape'
		    quad := <1, id := 2, ix: Number, String>(4, 8, 1, 'five')
		    quad.to_s()
		CODE
		assert_equal "<4, id: Number = 8, ix: Number = 1, 'five'>", out
	end

	def test_string_equality_regression
		assert Tape.interp('String("Alice") == String("Alice")')
		out = Tape.interp <<~CODE
		    @load 'tapes/struct.tape'
		    s := <name: String>("Alice")
		    s.members.0.value == "Alice"
		CODE
		assert out
	end

	# `!=` derives from a declared `==` (see the `!=` note two entries up) -- tapes/string.tape's own `==` overload used to assume its right operand was always another String and crashed reading `.value` off anything else. `!= nil` is the common case this broke (a String compared against something that turned out not to exist).
	def test_string_not_equal_to_nil_regression
		refute_raises do
			assert Tape.interp("String('hi') != nil")
			refute Tape.interp("String('hi') == nil")
			refute Tape.interp("String('hi') == 5")
		end
	end

	# Same class of bug in tapes/member.tape/tapes/struct.tape's own `==` overloads -- each assumed its right operand was already Member/Struct-shaped.
	def test_member_and_struct_not_equal_to_nil_regression
		refute_raises do
			out = Tape.interp <<~CODE
			    @load 'tapes/struct.tape'
			    m := Member('x', String, 4)
			    s := <1, 2>
			    (m != nil, m == nil, s != nil, s == nil)
			CODE
			assert_equal [true, false, true, false], out.values
		end
	end

	def test_self_declaration_during_construction_works_but_external_dot_does_not_regression
		out = Tape.interp <<~CODE
		    Thing {
		        new (;
		            self.member := 123
		        )
		    }
		    t := Thing()
		    t.member
		CODE
		assert_equal 123, out

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			# but actually it raises something about not being able to declare members on the type outside of new(;) or the explicit class body declarations
			Tape.interp <<~CODE
			    Thing {
			        not_new_func (;
			            self.member := 123
			        )
			    }
			    t := Thing()
			    t.not_new_func()
			CODE
		end

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp 'Number.yolo = 123'
		end

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp 'Number.yolo := 123'
		end

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp <<~CODE
			    Thing { member, new (; self.member = 0 ) }
			    thing := Thing()
			    thing.missing = 5
			CODE
		end
	end

	def test_declare_command_on_structs
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp <<~CODE
			    # @declare <id: Number, name: String = "Locke">
				(it, name)
			CODE
		end

		out = Tape.interp <<~CODE
		    @declare <id: Number, name: String = "Locke">
			(id, name)
		CODE
		assert_equal [nil, "Locke"], out.values
	end

	def test_declare_name_only_self_declares_to_nil
		out = Tape.interp <<~CODE
		    @declare "foo"
		    foo
		CODE
		assert_nil out
	end

	def test_declare_name_and_value
		out = Tape.interp <<~CODE
		    @declare "foo", 42
		    foo
		CODE
		assert_equal 42, out
	end

	def test_declare_name_value_and_type
		out = Tape.interp <<~CODE
		    @declare "foo", 42, Number
		    foo
		CODE
		assert_equal 42, out
	end

	def test_declare_value_can_be_any_expression
		out = Tape.interp <<~CODE
		    @declare "foo", 1 + 2
		    foo
		CODE
		assert_equal 3, out
	end

	def test_declare_with_no_value_argument_still_registers_the_name
		# Undeclared before, so a plain (non-annotated) read would normally raise --
		# @declare "foo" alone should self-declare it, same as the nil-init idiom.
		refute_raises Tape::Undeclared_Identifier do
			Tape.interp '@declare "foo"
			foo'
		end
	end

	def test_declare_too_many_arguments_raises
		assert_raises Tape::Invalid_Directive_Usage do
			Tape.interp '@declare "foo", 42, Number, "extra"'
		end
	end

	def test_declare_with_type_allows_matching_reassignment
		out = Tape.interp <<~CODE
		    @declare "foo", 42, Number
		    foo = 99
		    foo
		CODE
		assert_equal 99, out
	end

	def test_declare_with_type_rejects_mismatched_reassignment
		assert_raises Tape::Type_Contract_Violation do
			Tape.interp <<~CODE
			    @declare "foo", 42, Number
			    foo = "oops"
			CODE
		end
	end

	def test_declare_without_type_allows_any_reassignment
		out = Tape.interp <<~CODE
		    @declare "foo", 42
		    foo = "now a string"
		    foo
		CODE
		assert_equal 'now a string', out
	end

	def test_declare_inside_function_scope_is_local
		out = Tape.interp <<~CODE
		    make (;
		    	@declare "local_thing", 5
		    	local_thing
		    )
		    make()
		CODE
		assert_equal 5, out
	end

	def test_declare_inside_function_scope_does_not_leak_out
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp <<~CODE
			    make (;
			    	@declare "local_thing", 5
			    )
			    make()
			    local_thing
			CODE
		end
	end

	def test_percent_string_literals
		# %string preserves each identifier's own casing.
		out = Tape.interp "%string(boo Hoo COOL).values"
		assert_equal %w(boo Hoo COOL), out
		assert out.all? { |it| it.is_a? ::String }

		# %str forces lowercase.
		assert_equal %w(boo hoo cool), Tape.interp("%str(Boo hOO COOL).values")

		# %Str forces Capitalcase.
		assert_equal %w(Boo Hoo Cool), Tape.interp("%Str(boo HOO cOOl).values")

		# %STR forces UPPERCASE.
		assert_equal %w(BOO HOO COOL), Tape.interp("%STR(boo Hoo cool).values")

		# Casing has no effect on numbers or symbols
		assert_equal %w(123 ^^^ + - * /), Tape.interp("%string(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Tape.interp("%str(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Tape.interp("%Str(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Tape.interp("%STR(123 ^^^ + - * /).values")
	end

	def test_percent_symbol_literals
		# %symbol preserves each identifier's own casing.
		out = Tape.interp "%symbol(BOO hoo Cool).values"
		assert_equal %i(BOO hoo Cool), out
		assert out.all? { |it| it.is_a? ::Symbol }

		# %sym forces lowercase.
		assert_equal %i(boo hoo cool), Tape.interp("%sym(Boo HOO cOOl).values")

		# %Sym forces Capitalcase.
		assert_equal %i(Boo Hoo Cool), Tape.interp("%Sym(boo HOO cOOl).values")

		# %SYM forces UPPERCASE.
		assert_equal %i(BOO HOO COOL), Tape.interp("%SYM(boo Hoo cool).values")

		assert_equal %i(123 ^^^ + - * /), Tape.interp("%symbol(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Tape.interp("%sym(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Tape.interp("%Sym(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Tape.interp("%SYM(123 ^^^ + - * /).values")
	end

	def test_percent_literal_is_a_real_array
		out = Tape.interp "%str(a b c)"
		assert_kind_of Tape::Array, out
		assert_equal 3, out.values.count
	end

	def test_percent_literal_interpolation
		out = Tape.interp <<~CODE
		    cool := 2342
		    %str(481516 `cool`)
		CODE
		assert_equal ['481516', '2342'], out.values
		# assert out.values.all? { _1.is_a? Tape::String } # todo; this is currently false
	end

	def test_statement_expressions
		out = Tape.interp "`1+2`"
		assert_kind_of Tape::Statement, out
		assert_kind_of Tape::Infix_Expr, out.expression
		assert_equal "Statement{Tape::Infix_Expr}", out.proxy_to_s

		out = Tape.interp "`1+2`()"
		assert_equal 3, out
	end

	def test_statement_expression_stored_in_a_variable
		# The whole point of Statement -- build it once, call it later, wherever it ends up.
		out = Tape.interp <<~CODE
		    x := `1+2`
		    x()
		CODE
		assert_equal 3, out

		# Same thing, but via a `: Statement` type annotation instead of `:=`.
		out = Tape.interp <<~CODE
		    x: Statement = `1+2`
		    x()
		CODE
		assert_equal 3, out
	end

	def test_statement_expression_re_evaluates_on_every_call
		# Not memoized -- each `()` call re-interprets the wrapped expression fresh.
		out = Tape.interp <<~CODE
		    counter := 0
		    increment := `counter += 1`
		    increment()
		    increment()
		    increment()
		    counter
		CODE
		assert_equal 3, out
	end

	def test_statement_expression_can_be_displayed
		# Tape::Statement is a real Instance -- @puts must not crash on one, called or not.
		output          = StringIO.new
		original_stdout = $stdout
		$stdout         = output

		begin
			Tape.interp "@puts `1+2`"
			refute_empty output.string
		ensure
			$stdout = original_stdout
		end
	end

	def test_fancier_statement_example
		out = Tape.interp "x := `@load 'tapes/string'`"
		assert_kind_of Tape::Statement, out
	end

	def test_nested_statements_with_mixed_memoization
		# outer wraps two inner Statements, one memoized and one not, and is itself memoized too -- calling outer() a second time shouldn't re-run any of them.
		out = Tape.interp <<~CODE
		    calls_memoized   := 0
		    calls_unmemoized := 0

		    memoized_inner := `calls_memoized += 1`
		    memoized_inner.memoize = true

		    plain_inner := `calls_unmemoized += 1`

		    outer := `memoized_inner() + memoized_inner() + plain_inner() + plain_inner()`
		    outer.memoize = true

		    first  := outer()
		    second := outer()

		    (first, second, calls_memoized, calls_unmemoized)
		CODE

		first, second, calls_memoized, calls_unmemoized = out.values
		assert_equal 5, first # 1 + 1 + 1 + 2 -- memoized_inner's second call is cached, plain_inner's isn't
		assert_equal 5, second # outer is memoized too -- same cached result, nothing re-ran
		assert_equal 1, calls_memoized
		assert_equal 2, calls_unmemoized
	end

	def test_self_resolves_to_nearest_instance
		out = Tape.interp <<~CODE
		    Thing {
		        value := 42
		        get_val (; self.value )
		    }
		    Thing().get_val()
		CODE
		assert_equal 42, out
	end

	def test_Self_resolves_to_nearest_type
		out = Tape.interp <<~CODE
		    Thing {
		        klass (; Self )
		    }
		    Thing().klass() === Thing
		CODE
		assert out
	end

	def test_Self_dot_access_identical_to_class_name_dot_access
		out = Tape.interp <<~CODE
		    Thing {
		        Self.count := 5
		        get_via_Self (; Self.count )
		        get_via_name (; Thing.count )
		    }
		    t := Thing()
		    (t.get_via_Self(), t.get_via_name())
		CODE
		assert_equal [5, 5], out.values
	end

	def test_self_raises_outside_instance_context
		assert_raises Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Tape.interp 'self'
		end
	end

	def test_Self_raises_outside_type_context
		assert_raises Tape::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Tape.interp 'Self'
		end
	end

	def test_self_dot_declare_self_declares_new_member_during_construction
		out = Tape.interp <<~CODE
		    Thing {
		        new (;
		            self.member := 123
		        )
		    }
		    Thing().member
		CODE
		assert_equal 123, out

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp <<~CODE
			    Thing {
			        not_new_func (;
			            self.member := 123
			        )
			    }
			    Thing().not_new_func()
			CODE
		end
	end

	def test_Self_dot_declare_self_declares_new_static_during_type_body
		out = Tape.interp <<~CODE
		    Thing {
		        Self.count := 0
		    }
		    Thing.count
		CODE
		assert_equal 0, out

		assert_raises Tape::Cannot_Assign_Undeclared_Identifier do
			Tape.interp <<~CODE
			    Thing {
			        bump_late (; Self.new_static := 1 )
			    }
			    Thing().bump_late()
			CODE
		end
	end

	def test_self_dot_func_declares_instance_method
		out = Tape.interp <<~CODE
		    Thing {
		        self.greet (; 'hi' )
		    }
		    Thing().greet()
		CODE
		assert_equal 'hi', out
	end

	def test_Self_dot_func_declares_static_method
		out = Tape.interp <<~CODE
		    Thing {
		        Self.count := 0
		        Self.increment (; count += 1 )
		    }
		    Thing.increment()
		    Thing.increment()
		    Thing.count
		CODE
		assert_equal 2, out
	end

	def test_Self_is_callable_like_the_type_name_with_and_without_args
		out = Tape.interp <<~CODE
		    Thing {
		        value := 42
		        make_bare (; Self() )
		    }
		    Thing().make_bare().value
		CODE
		assert_equal 42, out

		out = Tape.interp <<~CODE
		    Thing {
		        value,
		        new ( v; self.value = v )
		        make_with_arg (; Self(99) )
		    }
		    Thing(1).make_with_arg().value
		CODE
		assert_equal 99, out
	end

	def test_block_comments_are_ignored
		out = Tape.interp <<~CODE
		    ###
		    this whole block, including this fake declaration, is discarded
		    x := 999
		    ###
		    4 + 8
		CODE
		assert_equal 12, out

		# a block comment as the very last expression shouldn't leak its text out as the return value, same as a trailing # comment
		out = Tape.interp <<~CODE
		    add ( a, b;
		        a + b
		        ### sum me ###
		    )
		    add(4, 8)
		CODE
		assert_equal 12, out
	end

	def test_function_body_arg_with_other_arguments
		out = Tape.interp <<~CODE
		    f ( callable: (;), num: Number;
		    	(callable(), num)
		    )

		    f( (; 4), 42 )
		CODE
		assert_equal [4, 42], out.values
	end

	def test_number_rand
		100.times do
			out = Tape.interp 'Number.rand(10)'
			assert_includes 0..10, out
		end
	end

	def test_number_rand_zero
		out = Tape.interp 'Number.rand(0)'
		assert_equal 0, out
	end
end
