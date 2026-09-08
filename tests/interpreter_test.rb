require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# These tests are mostly in chronological order. I may have inserted some at times. It would be great to preserve this order.

class Interpreter_Test < Base_Test
	def test_global_disk
		refute_raises RuntimeError do
			Drive.interp_file './disks/global.disk'
		end
	end

	def test_numeric_literals
		assert_equal 48, Drive.interp('48')
		assert_equal 15.16, Drive.interp('15.16')
		assert_equal 2342, Drive.interp('23_42')
	end

	def test_true_false_nil_literals
		assert_equal true, Drive.interp('true')
		assert_equal false, Drive.interp('false')
		assert_instance_of NilClass, Drive.interp('nil')
	end

	def test_uninterpolated_strings
		assert_equal 'Walt!', Drive.interp('"Walt!"')
		assert_equal 'Vincent!', Drive.interp("'Vincent!'")
	end

	def test_raises_undeclared_identifier_when_reading
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'hatch'
		end
	end

	def test_does_not_raise_undeclared_identifier_when_declaring
		refute_raises Disk::Undeclared_Identifier do
			Drive.interp 'found := true'
		end
	end

	def test_variable_assignment_and_lookup
		out = Drive.interp 'name := "Locke", name'
		assert_equal 'Locke', out
	end

	def test_constant_assignment_and_lookup
		out = Drive.interp 'ENVIRONMENT := :development, ENVIRONMENT'
		assert_equal :development, out
	end

	def test_cannot_assign_incompatible_type
		# todo; raises Cannot_Reassign_Undeclared_Identifier
		assert_raises Disk::Cannot_Assign_Incompatible_Type do
			Drive.interp 'MyType {}
			My_Type = :anything'
		end

		refute_raises Disk::Cannot_Assign_Incompatible_Type do
			Drive.interp 'MyType {}
			My_Type = Other {}'
		end
	end

	def test_nil_assignment_operator
		out = Drive.interp 'nothing,'
		assert_instance_of NilClass, out
	end

	def test_anonymous_func_expr
		out = Drive.interp '(;)'
		assert_instance_of Disk::Func, out
		assert_empty out.expressions
		refute out.name
	end

	def test_empty_func_declaration
		out = Drive.interp 'open (;)'
		assert_instance_of Disk::Func, out
		assert_empty out.expressions
		assert_equal 'open', out.name.value
	end

	def test_basic_func_declaration
		out = Drive.interp 'enter ( numbers := "4815162342"; )'
		assert_equal 1, out.parameters.count
		assert_empty out.expressions
		assert_instance_of Disk::Param_Expr, out.parameters.first
		assert_instance_of Disk::String_Expr, out.parameters.first.default
	end

	def test_advanced_func_declaration
		out = Drive.interp 'add ( a, b; a + b )'
		assert_equal 2, out.parameters.count
		assert_equal 1, out.expressions.count
		assert_instance_of Disk::Infix_Expr, out.expressions.last
		refute out.parameters.first.default
	end

	def test_complex_func_declaration
		out = Drive.interp 'run ( a, labeled b, c := 4, labeled d := 8;
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

		assert_instance_of Disk::Infix_Expr, out.expressions.last
	end

	def test_empty_type_declaration
		out = Drive.interp 'Island {}'
		assert_instance_of Disk::Type, out
		assert_empty out.expressions
		assert_equal 'Island', out.name
	end

	def test_basic_type_declaration
		out = Drive.interp 'Hatch {
			computer := nil

			enter ( numbers;
				# do something with the numbers
			)
		}'
		assert_instance_of Disk::Type, out
		assert_instance_of NilClass, out[:computer]
		assert_instance_of Disk::Func, out[:enter]
	end

	def test_inline_type_composition_declaration
		out = Drive.interp 'Number {}
		Integer | Number {}'
		assert_instance_of Disk::Type, out
		assert_equal Set['Integer', 'Number'], out.types
	end

	def test_inbody_type_composition_declaration
		out = Drive.interp 'Numeric {
			numerator,
		}
		Number | Numeric {}
		Float {
			| Number
		}'
		assert_instance_of Disk::Type, out
		assert_equal Set['Float', 'Number', 'Numeric'], out.types
	end

	def test_invalid_type_declaration
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'Number | Numeric {}'
		end
	end

	def test_potential_colon_ambiguity
		out = Drive.interp 'assign_to_nil,'
		assert_instance_of NilClass, out

		out = Drive.interp 'func ( assign_to_nil; )'
		assert_instance_of Disk::Func, out
		assert_instance_of Disk::Param_Expr, out.parameters.first
		assert_equal 'assign_to_nil', out.parameters.first.name.value
	end

	def test_infix_arithmetic
		assert_equal 12, Drive.interp('4 + 8')
		assert_equal 4, Drive.interp('1 + 2 * 3 / 4 % 5 ^ 6')
		assert_equal 8, Drive.interp('(1 + (2 * 3 / 4) % 5) << 2')
	end

	def test_nested_type_declaration
		out = Drive.interp '
		Computer {
		}

		Island {
			Hatch {
				Commodore_64 | Computer {}
			}
		}

		Island.Hatch.Commodore_64'
		assert_instance_of Disk::Type, out
	end

	def test_constants_cannot_be_reassigned
		assert_raises Disk::Cannot_Reassign_Constant do
			Drive.interp 'ENVIRONMENT := :development
			ENVIRONMENT = :production'
		end
	end

	def test_variable_declarations
		out = Drive.interp 'cool := "Cooper"'
		assert_equal 'Cooper', out

		out = Drive.interp 'delta := 0.017'
		assert_equal 0.017, out
	end

	def test_declared_variable_lookup
		out = Drive.interp 'number := 42
		number'
		assert_equal 42, out
	end

	def test_variable_can_be_reassigned
		out = Drive.interp 'number := 42'
		assert_equal 42, out

		out = Drive.interp 'number := 42
		number = 8'
		assert_equal 8, out
	end

	# Disk::Range is now an Instance wrapping a Ruby ::Range (`.range`), not a ::Range subclass -- so
	# the raw-Range comparison is against `out.range`; `out.include?` still works via Enumerable.
	def test_inclusive_range
		out = Drive.interp '4...42'
		assert_instance_of Disk::Range, out
		assert_equal 4..42, out.range
		assert out.include? 4
		assert out.include? 23
		assert out.include? 42
	end

	def test_right_exclusive_range
		out = Drive.interp '4..<42'
		assert_instance_of Disk::Range, out
		assert_equal 4...42, out.range
		assert out.include? 4
		assert out.include? 41
		refute out.include? 42
	end

	def test_left_exclusive_range
		out = Drive.interp '4>..42'
		assert_instance_of Disk::Range, out
		assert_equal 5..42, out.range
		refute out.include? 4
		assert out.include? 5
		assert out.include? 42
	end

	def test_left_and_right_exclusive_range
		out = Drive.interp '4>.<42'
		assert_instance_of Disk::Range, out
		assert_equal 5...42, out.range
		refute out.include? 4
		assert out.include? 5
		assert out.include? 41
		refute out.include? 42
	end

	def test_empty_left_and_right_exclusive_range
		out = Drive.interp '0>.<0'
		assert_equal 1...0, out.range
		refute out.include? -1
		refute out.include? 0
		refute out.include? 1
		refute out.include? 0.5
	end

	def test_simple_comparison_operators
		assert Drive.interp '1 == 1'
		refute Drive.interp '1 != 1'
		assert Drive.interp '1 != 2'
		assert Drive.interp '1 < 2'
		refute Drive.interp '1 > 2'

		# It doesn't make sense to test all these since I'm just calling through to Ruby
	end

	def test_boolean_logic
		assert Drive.interp 'true && true'
		refute Drive.interp 'true && false'
		assert Drive.interp 'true and true'
		refute Drive.interp 'true and false'
	end

	def test_arithmetic_operators
		out = Drive.interp '1 + 2 / 3 - 4 * 5'
		assert_equal -19, out

		# Right now this functions like the Ruby operator, but it could also be the power operator
		out = Drive.interp '2 ^ 3'
		assert_equal 1, out

		out = Drive.interp '1 << 2'
		assert_equal 4, out

		out = Drive.interp '1 << 3'
		assert_equal 8, out
	end

	def test_double_operators
		out = Drive.interp '1 - -9'
		assert_equal 10, out

		out = Drive.interp '4 + -8'
		assert_equal -4, out

		out = Drive.interp '8 - +15'
		assert_equal -7, out
	end

	def test_empty_array
		out = Drive.interp '[]'
		assert_equal [], out.values
		assert_instance_of Disk::Array, out
	end

	def test_non_empty_arrays
		out = Drive.interp '[1]'
		assert_instance_of Disk::Array, out
		assert_equal [1], out.values

		out = Drive.interp '[1, "test", 5]'
		assert_instance_of Disk::Array, out
		assert_equal Disk::Array.new([1, 'test', 5]).values, out.values
	end

	def test_tuples
		out = Drive.interp '(1, 2)'
		assert_kind_of Disk::Tuple, out
		assert_equal [1, 2], out.values

		out = Drive.interp 't := ("Hello", "from" ,"Tuple")
		t_first := t.0
		t2 := (t.0, t.1, t.2)
		(t_first, t == t2, t_first == t2, t2)'
		assert_equal "Hello", out.values.first
		assert out.values[1]
		refute out.values[2]
		assert_equal ["Hello", "from", "Tuple"], out.values.last.values
	end

	def test_empty_dictionary
		out = Drive.interp '{}'
		assert_kind_of Disk::Dictionary, out
		assert_equal out.hash, {}
	end

	def test_create_dictionary_with_identifiers_as_keys_without_commas
		out = Drive.interp '{a b c}'
		assert_equal %i(a b c), out.hash.keys
		out.hash.values.each do |value|
			assert_instance_of NilClass, value
		end
	end

	def test_create_dictionary_with_identifiers_as_keys_with_commas
		out = Drive.interp '{a, b}'
		out.hash.values.each do |value|
			assert_instance_of NilClass, value
		end
	end

	def test_create_dictionary_with_keys_and_values_with_mixed_infix_notation
		out = Drive.interp '{ x:0 y=1 z}'
		refute_instance_of NilClass, out.hash.values.first
		refute_instance_of NilClass, out.hash.values[1]
		assert_instance_of NilClass, out.hash.values.last
	end

	def test_create_dictionary_with_keys_and_values_with_mixed_infix_notation_and_commas
		out = Drive.interp '{ x:4, y=8, z}'
		assert_equal 4, out.hash.values.first
		assert_equal 8, out.hash.values[1]
		assert_instance_of NilClass, out.hash.values.last
	end

	def test_create_dictionary_with_local_value
		out = Drive.interp 'x:=4, y:=2, { x=x, y=y }'
		assert_equal out.hash, { x: 4, y: 2 }
	end

	def test_symbol_as_dictionary_keys
		out = Drive.interp '{ :x = 1 }'
		assert_equal out.hash, { x: 1 }
	end

	def test_string_as_dictionary_keys
		out = Drive.interp '{ "x" = 1 }'
		assert_equal out.hash, { x: 1 }
	end

	def test_colon_as_dictionary_infix_operator
		out = Drive.interp 'x := 123, { x: x }'
		assert_equal out.hash, { x: 123 }
	end

	def test_equals_as_dictionary_infix_operator
		out = Drive.interp 'x := 123, { x = x }'
		assert_equal out.hash, { x: 123 }
	end

	def test_dictionary_keys
		out = Drive.interp '{ a b c }.keys()'
		assert_equal [:a, :b, :c], out.values
	end

	def test_dictionary_values
		out = Drive.interp '{ a b c }.values()'
		assert_equal [nil, nil, nil], out.values

		out = Drive.interp '{ a=1, b= "two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Drive.interp '{ a=1, b="two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Drive.interp '{ a=1, b:"two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values
	end

	def test_dictionary_subscript
		out = Drive.interp "dict := {x}
		original := dict[:x]
		dict[:x] = 4815
		(original, dict[:x])"
		assert_equal [nil, 4815], out.values
	end

	def test_dictionary_subscript_string_and_symbol_do_not_behave_differently
		out = Drive.interp "dict := {x=4815}
		(dict['x'], dict[:x])"
		assert_equal [4815, 4815], out.values
	end

	# `[]`/`[]=` (#proxy_get/#proxy_set) normalize a key to a Symbol before touching the underlying hash -- `has_key?`/`delete`/`fetch` used to skip that normalization entirely, so a String key that matched what `[]=` actually stored (a Symbol) silently never matched.
	def test_dictionary_has_key_with_string_key_matches_what_bracket_assignment_stored
		out = Drive.interp "d := {}
		d['color'] = 1
		d.has_key?('color')"
		assert_equal true, out
	end

	def test_dictionary_delete_with_string_key_removes_the_entry
		out = Drive.interp "d := {a: 1}
		d.delete('a')
		d.count()"
		assert_equal 0, out
	end

	def test_dictionary_fetch_with_string_key_finds_the_value
		out = Drive.interp "d := {a: 1}
		d.fetch('a', 99)"
		assert_equal 1, out
	end

	def test_dictionary_fetch_missing_key_returns_the_default
		out = Drive.interp "d := {}
		d.fetch('missing', 42)"
		assert_equal 42, out
	end

	# The key normalization fix has to work for a real Disk::String value (an ordinary call argument, e.g. a variable), not just a raw Ruby string literal interpreted directly by `[]`/`[]=`'s own subscript handling.
	def test_dictionary_has_key_with_a_variable_holding_a_string_still_matches
		out = Drive.interp "d := {}
		d[:x] = 1
		s := 'x'
		d.has_key?(s)"
		assert_equal true, out
	end

	# `:=` declares an identifier -- a subscript target isn't one, so `d[key] := value` isn't meaningful the way `d[key] = value` is (and used to silently declare a bogus identifier instead of writing to the dictionary).
	def test_dictionary_subscript_assignment_via_declare_operator_raises
		assert_raises Disk::Cannot_Declare_Subscript_Target do
			Drive.interp "d := {}
			d[:x] := 5"
		end
	end

	# Disk::Array had no `[]=` of its own, so `a[i] = value` fell through to the generic declarations-hash write every other Scope uses, silently declaring a bogus member instead of writing into `.values`.
	# A Disk::Range subscript slices an Array -- each of the four range operators keeps its own
	# inclusive/exclusive end behavior (`...` inclusive, `..<` exclusive end, `>..` exclusive start).
	def test_array_range_subscript
		assert_equal [20, 30, 40], Drive.interp('[10, 20, 30, 40, 50][1...3]').values
		assert_equal [20, 30],     Drive.interp('[10, 20, 30, 40, 50][1..<3]').values
		assert_equal [30, 40],     Drive.interp('[10, 20, 30, 40, 50][1>..3]').values
		assert_equal [30],         Drive.interp('[10, 20, 30, 40, 50][1>.<3]').values

		# the result is a real, linked Array -- methods chain off it
		assert_equal [21, 31, 41], Drive.interp('[10, 20, 30, 40, 50][1...3].map((x; x + 1))').values

		# a range held in a variable works too
		assert_equal [20, 30, 40], Drive.interp("r := 1...3\n[10, 20, 30, 40, 50][r]").values

		# an out-of-bounds start yields nil, same as Ruby
		assert_nil Drive.interp('[1, 2, 3][5...9]')
	end

	# `xs[2...]` -- an endless range (the operator with nothing after it): from the start index to the end.
	def test_endless_range_subscript
		assert_equal [30, 40, 50], Drive.interp('[10, 20, 30, 40, 50][2...]').values
		assert_equal [40, 50],     Drive.interp('[10, 20, 30, 40, 50][2>..]').values # exclusive start
		assert_equal 'world',      Drive.interp('"hello world"[6...]')
		assert_equal 5,            Drive.interp('[1, 2, 3, 4, 5][0...].length()')
		assert_equal [3, 4, 5],    Drive.interp("r := 2...\n[1, 2, 3, 4, 5][r]").values
		assert_nil Drive.interp('[1, 2, 3][10...]')
	end

	# `xs[...3]` -- a beginless range (the operator with no left operand): from the start up to the end
	# index. Negative end indices count from the end (`...-1` is the whole thing, `...-2` all but last).
	def test_beginless_range_subscript
		assert_equal [10, 20, 30],         Drive.interp('[10, 20, 30, 40, 50][...2]').values
		assert_equal [10, 20],             Drive.interp('[10, 20, 30, 40, 50][..<2]').values # exclusive end
		assert_equal [10, 20, 30, 40, 50], Drive.interp('[10, 20, 30, 40, 50][...-1]').values
		assert_equal [10, 20, 30, 40],     Drive.interp('[10, 20, 30, 40, 50][...-2]').values
		assert_equal [10, 20, 30, 40],     Drive.interp('[10, 20, 30, 40, 50][..<-1]').values
		assert_equal 'hello worl',         Drive.interp('"hello world"[...-2]')

		# `...` glued to a following `-` used to lex as one bogus `...-` token
		assert_equal [20, 30, 40, 50], Drive.interp('[10, 20, 30, 40, 50][1...-1]').values
	end

	def test_string_range_subscript
		assert_equal 'bcd', Drive.interp('"abcdef"[1...3]')  # inclusive
		assert_equal 'bc',  Drive.interp('"abcdef"[1..<3]')  # exclusive end
		assert_equal 'WORLD', Drive.interp('"hello world"[6...11].upcase()')
	end

	def test_array_subscript_assignment_mutates_in_place
		out = Drive.interp "a := [1, 2, 3]
		a[1] = 99
		a"
		assert_equal [1, 99, 3], out.values
	end

	def test_array_subscript_assignment_out_of_bounds_raises
		assert_raises Disk::Invalid_Array_Index do
			Drive.interp "a := [1, 2, 3]
			a[10] = 99"
		end
	end

	def test_array_subscript_assignment_via_declare_operator_raises
		assert_raises Disk::Cannot_Declare_Subscript_Target do
			Drive.interp "a := [1, 2, 3]
			a[1] := 99"
		end
	end

	def test_too_many_dictionary_subscript_arguments
		assert_raises Disk::Too_Many_Subscript_Expressions do
			Drive.interp "dict := {x=4815}
			dict[:x, 123]"
		end

		assert_raises Disk::Too_Many_Subscript_Expressions do
			Drive.interp "dict := {x=4815}
			dict[:x, 123] = 162342"
		end
	end

	def test_nested_dictionary_subscript
		out = Drive.interp '{ a: { b: 42 } }[:a][:b]'
		assert_equal 42, out
	end

	def test_dictionary_subscript_nonexistent_key
		out = Drive.interp '{ a: 1 }[:nonexistent]'
		assert_nil out
	end

	def test_dictionary_subscript_with_variable
		out = Drive.interp 'key := :a, dict := { a: 99 }, dict[key]'
		assert_equal 99, out
	end

	def test_dictionary_subscript_in_expression
		out = Drive.interp '{ x: 10 }[:x] + 5'
		assert_equal 15, out
	end

	def test_empty_dictionary_subscript
		out = Drive.interp '{}[:key]'
		assert_nil out
	end

	def test_invalid_dictionary_infix
		assert_raises Disk::Invalid_Dictionary_Infix_Operator do
			Drive.interp '{ x > x }'
		end
	end

	def test_assigning_function_to_variable
		out = Drive.interp 'funk := ( a, b, c; )'
		assert_equal 3, out.parameters.count
	end

	def test_composed_type_declaration
		out = Drive.interp '
		Transform {}
		Rotation {}
		Entity {
			| Transform
			~ Rotation
		}'
		assert_kind_of Disk::Type, out
		assert_kind_of Disk::Composition_Expr, out.expressions.first
		assert_kind_of Disk::Composition_Expr, out.expressions.last
		assert_equal 'Rotation', out.expressions.last.identifier.value
		assert_equal '~', out.expressions.last.operator.value
	end

	def test_composed_type_declaration_before_body
		out = Drive.interp '
		Transform {}, Physics {}
		Entity | Transform ~ Physics {}'
		assert_kind_of Disk::Type, out
		assert_kind_of Disk::Composition_Expr, out.expressions.first
		assert_kind_of Disk::Composition_Expr, out.expressions.last
		assert_equal 'Physics', out.expressions.last.identifier.value
		assert_equal '~', out.expressions.last.operator.value
	end

	def test_complex_type_declaration
		out = Drive.interp 'Transform {
			position,
			rotation,

			x := 0
			y := 0

			to_s (;
				"Transform!"
			)
		}'
		assert_kind_of Disk::Infix_Expr, out.expressions[0]
		assert_kind_of Disk::Infix_Expr, out.expressions[1]
		assert_kind_of Disk::Infix_Expr, out.expressions[2]
		assert_kind_of Disk::Infix_Expr, out.expressions[3]
		assert_kind_of Disk::Func_Expr, out.expressions[4]
	end

	def test_undeclared_type_init_via_call
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'Type()'
		end
	end

	# `Self` is deleted off an instance right after construction finishes, so a dot-access to it from an already-built value (a lowercase-receiver `x.Self`, as opposed to a Type's own `Ident.Self`) just fails like any other missing member.
	def test_ident_dot_self_fails_after_construction
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'x := 1, x.Self'
		end
	end

	def test_declared_type_init_via_call
		out = Drive.interp 'Type {}, Type()'
		assert_instance_of Disk::Instance, out
		assert_equal 'Type', out.name
	end

	# Bare `X.Self` is equivalent to `X()` — it runs `Self(;)`, so required constructor params raise.
	# Bare `X.Self` (no parens) is an ordinary reference to the declared function, same as any other unnamed function access -- it does not call it, let alone construct an instance. `X()` remains the real, documented way to construct.
	def test_bare_self_returns_function_reference
		out = Drive.interp 'Thing {
			x,
			Self (;
				self.x = 123
			)
		}, Thing.Self'
		assert_kind_of Disk::Func, out

		out = Drive.interp 'Thing {
			x,
			Self (;
				self.x = 123
			)
		}, Thing().x'
		assert_equal 123, out
	end

	def test_complex_type_init
		out = Drive.interp 'Transform {
			position,
			rotation,

			x := 4
			y := 8

			to_s (;
				"Transform!"
			)

			Self ( position := 0; )
		}, Transform()'
		assert_kind_of Disk::Instance, out
		assert_equal 'Transform', out.name
		assert_kind_of ::Array, out.expressions
		assert_equal 6, out.expressions.count
		assert_kind_of Disk::Func_Expr, out.expressions.last
	end

	def test_complex_type_with_value_lookup
		out = Drive.interp 'Vector1 { x := 4 }
		Vector1().x
		'
		assert_equal 4, out
	end

	def test_instance_complex_value_lookup
		out = Drive.interp 'Vector2 { x := 1, y := 2 }
		Transform {
			position := Vector2()
		}
		t := Transform()
		(t.position, t.position.y)
		'
		assert_kind_of Disk::Tuple, out
		assert_kind_of Disk::Instance, out.values.first
		assert_equal 2, out.values.last
	end

	def test_type_declaration_with_parens
		out = Drive.interp 'Vector2 { x := 0, y := 1 }
		pos := Vector2()'
		assert_instance_of Disk::Instance, out
		data = { 'x' => 0, 'y' => 1 }
		assert_equal data, out.declarations
	end

	# `.name`/`.types` are `@`-only (`@.name`/`@.composed_types`), stored as plain Ruby attrs; when the backing Ruby class is shared with a *composed* type (`Tasks | Table {}` resolves to Disk::Table, a Ruby-backed builtin), that class's own Type#initialize baked its own name ("Table") into the attr at construction, which `build_instance_of_type` must overwrite with the real composed type's name.
	def test_composed_instance_reports_its_own_name_not_the_backing_ruby_class_regression
		out = Drive.interp "@load 'disks/table'
			Tasks | Table {}
			t := Tasks()
			(t.@name, t.@composed_types)"
		assert_equal 'Tasks', out.values.first
		assert_equal %w(Tasks Table), out.values.last.set.to_a
	end

	def test_self_scope_write_outside_instance
		assert_raises Disk::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Drive.interp 'self.x := 123'
		end
	end

	def test_type_scope_write_outside_type
		assert_raises Disk::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Drive.interp 'Self.x := 123'
		end
	end

	def test_global_scope_operator_lookup
		out = Drive.interp 'Global.y := 543
		Global.y'
		assert_equal 543, out
	end

	def test_function_call_with_arguments
		out = Drive.interp '
		add ( a, b; a+b )
		add(4, 8)'
		assert_equal 12, out
	end

	def test_named_call_arguments_bind_by_declared_name_regardless_of_order
		src = 'sub ( a, b; a - b )'
		assert_equal -1, Drive.interp("#{src}\nsub(a := 1, b := 2)")
		assert_equal -1, Drive.interp("#{src}\nsub(b := 2, a := 1)") # reordered -- same result
	end

	def test_named_call_arguments_can_follow_positional_arguments
		src = 'sub ( a, b; a - b )'
		assert_equal -1, Drive.interp("#{src}\nsub(1, b := 2)")
	end

	def test_positional_argument_after_named_raises
		assert_raises Disk::Positional_Argument_After_Named do
			Drive.interp 'add ( a, b; a + b )
				add(a := 1, 2)'
		end
	end

	def test_duplicate_named_argument_raises
		assert_raises Disk::Duplicate_Named_Argument do
			Drive.interp 'add ( a, b; a + b )
				add(a := 1, a := 2)'
		end
	end

	def test_argument_given_by_name_and_position_raises
		assert_raises Disk::Argument_Given_By_Name_And_Position do
			Drive.interp 'add ( a, b; a + b )
				add(1, a := 2)'
		end
	end

	# An unknown name is the actual mistake, so it has to be reported even when some other (unrelated) param is also left without a value as a side effect of that same typo -- not masked by a confusing Missing_Argument that never mentions the real problem.
	def test_unknown_named_argument_raises_even_when_another_param_is_also_left_missing
		assert_raises Disk::Unknown_Named_Argument do
			Drive.interp 'add ( a, b; a + b )
				add(a := 1, c := 2)' # `c` isn't a param; `b` is consequently never filled
		end
	end

	def test_named_call_arguments_fall_back_to_defaults_when_omitted
		out = Drive.interp <<~CODE
		    greet ( name := "World"; "Hello, `name`" )
		    (greet(), greet(name := "Drive"))
		CODE
		assert_equal ['Hello, World', 'Hello, Drive'], out.values
	end

	def test_named_call_arguments_do_not_leak_into_caller_scope
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'add ( a, b; a + b )
				add(a := 1, b := 2)
				a' # `a` was never declared in the caller -- only inside add's own call scope
		end
	end

	def test_named_call_arguments_work_through_constructors
		out = Drive.interp <<~CODE
		    Point {
		    	x,
		    	y,
		    	Self ( x, y;
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
		out = Drive.interp <<~CODE
		    send ( to person, subject := 'hi'; "`person`: `subject`" )
		    send(to: 'Alice', subject := 'bye')
		CODE
		assert_equal 'Alice: bye', out
	end

	def test_variadic_parameter_collects_the_positional_tail
		out = Drive.interp <<~CODE
		    sum ( nums...;
		    	acc := 0
		    	for nums
		    		acc += it
		    	end
		    	acc
		    )
		    (sum(1, 2, 3, 4), sum())
		CODE
		assert_equal [10, 0], out.values
	end

	def test_variadic_after_a_fixed_parameter
		out = Drive.interp <<~CODE
		    f ( a, rest...; (a, rest) )
		    f(1, 2, 3)
		CODE
		assert_equal 1, out.values[0]
		assert_equal [2, 3], out.values[1].values
	end

	def test_args_annotation_is_the_same_as_the_ellipsis_form
		out = Drive.interp <<~CODE
		    g ( xs: Args; (xs, xs === Arguments) )
		    g(9, 8, 7)
		CODE
		assert_equal [9, 8, 7], out.values[0].values
		assert_equal true, out.values[1]
	end

	# A variadic param binds an `Arguments` (an Array subtype).
	def test_variadic_parameter_is_an_arguments_instance
		out = Drive.interp <<~CODE
		    f ( xs...; (xs === Arguments, xs =>= Array) )
		    f(1)
		CODE
		assert_equal [true, true], out.values
	end

	# `rest := <value>` at the call site: an Array spreads, anything else is a type error.
	def test_variadic_named_argument_spreads_an_array_and_rejects_a_scalar
		out = Drive.interp <<~CODE
		    f ( a, rest...; rest )
		    f(1, rest := [9, 8])
		CODE
		assert_equal [9, 8], out.values

		assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    f ( a, rest...; rest )
			    f(1, rest := 99)
			CODE
		end
	end

	# With a variadic param, an unknown named arg binds by its own name instead of raising.
	def test_variadic_function_binds_unknown_named_arguments_by_name
		out = Drive.interp <<~CODE
		    h ( args...; value )
		    h(value := 42)
		CODE
		assert_equal 42, out
	end

	def test_variadic_is_the_only_parameter
		out = Drive.interp <<~CODE
		    f ( xs...; (xs.length(), xs) )
		    f()
		CODE
		assert_equal 0, out.values[0]
		assert_equal [], out.values[1].values
	end

	def test_variadic_arguments_instance_has_array_methods
		out = Drive.interp <<~CODE
		    f ( xs...; xs.map(( n; n * 2 )) )
		    f(1, 2, 3)
		CODE
		assert_equal [2, 4, 6], out.values
	end

	# A param after a variadic is keyword-only -- it can't be filled positionally.
	def test_parameter_after_a_variadic_is_keyword_only
		out = Drive.interp <<~CODE
		    f ( a, mid..., z; (a, mid, z) )
		    f(1, 2, 3, z := 9)
		CODE
		assert_equal 1, out.values[0]
		assert_equal [2, 3], out.values[1].values
		assert_equal 9, out.values[2]

		assert_raises Disk::Missing_Argument do
			Drive.interp <<~CODE
			    f ( a, mid..., z; z )
			    f(1, 2, 3)
			CODE
		end
	end

	# A real param declared after a variadic still takes its default / named value.
	def test_defaulted_parameter_after_a_variadic
		out = Drive.interp <<~CODE
		    f ( args..., flag := 5; (args, flag) )
		    (f(1, 2).1, f(1, 2, flag := 8).1)
		CODE
		assert_equal [5, 8], out.values
	end

	# Naming the variadic param itself (`rest := ...`) goes through the spread/reject path, never
	# the by-name nicety -- regression for a bug where it silently overwrote `rest` with a scalar.
	def test_naming_the_variadic_parameter_does_not_bypass_the_spread_check
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    f ( a, rest...; rest )
			    f(1, rest := 99)
			CODE
		end
	end

	def test_variadic_keeps_the_positional_before_named_ordering_rules
		assert_raises Disk::Positional_Argument_After_Named do
			Drive.interp <<~CODE
			    f ( a, rest...; a )
			    f(a := 1, 2)
			CODE
		end

		assert_raises Disk::Argument_Given_By_Name_And_Position do
			Drive.interp <<~CODE
			    f ( a, rest...; a )
			    f(1, a := 2)
			CODE
		end

		assert_raises Disk::Duplicate_Named_Argument do
			Drive.interp <<~CODE
			    f ( args...; x )
			    f(x := 1, x := 2)
			CODE
		end
	end

	def test_labeled_argument_with_a_variadic_tail
		out = Drive.interp <<~CODE
		    f ( to a, rest...; (a, rest) )
		    f(to: 1, 2, 3)
		CODE
		assert_equal 1, out.values[0]
		assert_equal [2, 3], out.values[1].values
	end

	# A call site with typed fixed params + a variadic doesn't trip the static Type_Checker.
	def test_variadic_call_site_is_not_statically_type_checked
		refute_raises do
			Drive.interp <<~CODE
			    f ( a: Number, rest...; a )
			    f(1, "two", :three, [4])
			CODE
		end
	end

	def test_variadic_parameter_in_a_constructor
		out = Drive.interp <<~CODE
		    Bag {
		    	items,
		    	Self ( things...; self.items = things )
		    }
		    Bag(1, 2, 3).items
		CODE
		assert_equal [1, 2, 3], out.values
	end

	# Reopening `Arguments` to restrict what a variadic accepts.
	def test_arguments_push_can_be_overridden_for_a_typed_variadic
		src = <<~CODE
		    Arguments | Array {
		    	push ( item;
		    		unless item =>= Number
		    			return nil
		    		end
		    		self.append(item)
		    	)
		    }
		    collect ( nums...; nums )
		    r := collect()
		    r.push(1)
		    r.push("nope")
		    r.push(2)
		    r
		CODE
		assert_equal [1, 2], Drive.interp(src).values
	end

	def test_compound_operator
		out = Drive.interp 'add ( amount := 1, to := 0;
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

		out = Drive.interp "#{shared_code}
		A.B"
		assert_instance_of Disk::Type, out

		out = Drive.interp "#{shared_code}
		A.B.C()"
		assert_instance_of Disk::Instance, out

		out = Drive.interp "#{shared_code}
		A.B.C().d"
		assert_equal 4, out
	end

	def test_closures_do_capture_values
		out = Drive.interp '
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
			out = Drive.interp '
			square ( input;
				input * input
			)

			result := square(5)
			result'
			assert_equal 25, out
		end
	end

	def test_function_call_as_argument
		out = Drive.interp '
		add ( amount := 1, to := 4;
			to + amount
		)
		inc := add() # should return 5
		add(inc, 1)'
		assert_equal 6, out
	end

	def test_complex_return_with_simple_conditional
		out = Drive.interp 'return (1+2*3/4) + (1+2*3/4) if 1 + 2 > 2'
		assert_equal 4, out.value
	end

	def test_truthy_falsy_logic
		assert_equal 1, Drive.interp('if true 1 else 0 end')
		assert_equal 1, Drive.interp('if 0 1 else 0 end') # truthiness follows Ruby's own rules -- only nil/false are falsy, 0 is truthy
		assert_equal 0, Drive.interp('if nil 1 else 0 end')
	end

	def test_returns_with_end_of_line_conditional
		out = Drive.interp 'return 3 if true'
		assert_equal 3, out.value
	end

	def test_standalone_array_index_expr
		out = Drive.interp '4.8.15.16.23.42'
		assert_equal [4, 8, 15, 16, 23, 42], out.values
	end

	def test_array_access_by_dot_index
		out = Drive.interp 'things := [4, 8, 15]
		things.0'
		assert_equal 4, out
	end

	def test_array_nested_non_array_dot_index
		assert_raises Disk::Invalid_Dot_Infix_Left_Operand do
			Drive.interp 'things := [4, 8, 15]
		things.0.1'
		end
	end

	def test_nested_array_access_by_dot_index
		out = Drive.interp 'things := [4, [8, 15, 16], 23, [42, 108, 418, 3]]
		(things.1.0, things.3.1)'
		assert_instance_of Disk::Tuple, out
		assert_equal 8, out.values.first
		assert_equal 108, out.values.last
	end

	def test_function_scope
		out = Drive.interp 'x := 123
		double (; x * 2 )
		double()'
		assert_equal 246, out
	end

	def test_function_scope_some_more
		out = Drive.interp 'x := 108

		Doubler {
			double (; x * 2 )
		}

		Doubler().double()'
		assert_equal 216, out
	end

	def test_returns
		out = Drive.interp 'return 1'
		assert_instance_of Disk::Return, out
		assert_equal 1, out.value

		out = Drive.interp '
		eject (;
			if true
				return "true!"
			end

			return "should not get here"
		)
		eject()'
		assert_equal "true!", out
	end

	def test_type_does_have_self_function
		out = Drive.interp '
		Atom {
			Self (;)
		}'
		assert out.has? :Self
	end

	def test_instance_does_not_have_self_function
		out = Drive.interp '
		Atom {
			Self (;)
		}
		Atom()'
		refute out.has? :Self
	end

	def test_while_loops
		out = Drive.interp '
		x := 0
		while x < 4
			x += 1
		end
		x'
		assert_equal 4, out
	end

	def test_fancy_while_loops
		out = Drive.interp '
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
		out = Drive.interp '
		x := 1
		until x >= 23
			x += 2
		end
		'
		assert_equal 23, out
	end

	def test_fancy_until_loops
		out = Drive.interp '
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
		out = Drive.interp '
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
		out = Drive.interp '
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
		out = Drive.interp '
		x,
		y,

		equal := x == y
		(x, y, equal)'
		assert_equal out.values[0].object_id, out.values[1].object_id
		assert_equal true, out.values[2]
	end

	def test_accessing_declarations_through_type_composition
		out = Drive.interp "
		Vec2 {
			x := 0, y := 0

			Self ( x, y;
				self.x = x
				self.y = y
			)

			multiply! ( times;
				self.x *= times
				self.y *= times
			)

		}

		Transform | Vec2 {
			Self ( position := Vec2();
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

		assert_instance_of Disk::Instance, out.values[2]
		assert_equal 12, out.values[2][:x]
		assert_equal 24, out.values[2][:y]
	end

	def test_random_composition_example
		refute_raises Disk::Undeclared_Identifier do
			out = Drive.interp "
			Vec2 {
				x := 0, y := 0

				Self ( x, y;
					self.x = x
					self.y = y
				)
			}
			v := Vec2(4, 8)

			Transform | Vec2 {
				Self ( position := Vec2();
					self.x = position.x
					y = position.y
				)
			}
			t := Transform(Vec2(15, 16))

			Xform | Transform ~ Vec2 {
				# ~Vec2 removes x and y declarations, but retains Transform's Self(;) so unless you declare a new initializer here, you are still required to pass in position arg from Transform, which depends on x and y, which have been removed.
				Self ( p: Vec2; )
			}
			x := Xform(v)
			"
			assert_instance_of Disk::Instance, out
			assert_equal Set['Xform', 'Transform'], out.types
		end
	end

	def test_union_composition
		refute_raises Disk::Undeclared_Identifier do
			out = Drive.interp '
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

		refute_raises Disk::Undeclared_Identifier do
			out = Drive.interp "#{shared_code}
			a := Aa()
			b := Bb()
			(d.a, a.common, b.common, d.common)"
			assert_equal [8, 15, 16, 23], out.values
		end

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			d.b"
		end
	end

	def test_intersection_composition
		shared_code = "
			Aa { a := 4,  common := 8 }
			Bb { b := 15, common := 16 }

			Intersected | Aa & Bb {}

			i := Intersected()"

		refute_raises Disk::Undeclared_Identifier do
			out = Drive.interp "#{shared_code}
			i.common"
			assert_equal 8, out
		end

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			i.a"
		end

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			i.b"
		end
	end

	def test_symmetric_difference_composition
		shared_code = "
			Aa { a := 4, common := 10 }
			Bb { b := 8, common := 10 }

			Sym_Diff | Aa ^ Bb {}
			s := Sym_Diff()\n"

		out = Drive.interp "#{shared_code} (s.a, s.b)"
		assert_equal [4, 8], out.values

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code} s.common"
		end
	end

	def test_union_composition_is_left_biased
		out = Drive.interp "
		Aa { a := 4 }
		Bb { a := 8 }
		Union | Aa | Bb {}
		Union().a"
		assert_equal 4, out
	end

	def test_composition_with_inbody_declarations
		out = Drive.interp "
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
		out = Drive.interp 'get://some/thing/:id ( id;
			do_something()
		)'

		assert_instance_of Disk::Route, out
		assert_equal 'get', out.http_method.value
		assert_equal 'some/thing/:id', out.path
		assert_equal 1, out.handler.parameters.count
		assert_equal 1, out.handler.expressions.count
	end

	def test_html_element
		out = Drive.interp "My_Div {
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
		assert_instance_of Disk::Type, out.values[0]
		assert_instance_of Disk::Instance, out.values[1]
		assert_instance_of String, out.values[2]
		assert_equal 'Text content of this div', out.values[2]
	end

	def test_loading_external_source_files
		out = Drive.interp "@load 'disks/global.disk'
		(Bool, Bool())"

		assert_instance_of Disk::Type, out.values[0]
		assert_kind_of Disk::Instance, out.values[1]
		assert_instance_of Disk::Bool, out.values[1]
	end

	def test_standalone_load_into_current_scope
		out = Drive.interp "@load 'tests/fixtures/test_module.disk'
		(MODULE_NAME, MODULE_VALUE, module_func(10))"

		assert_instance_of Disk::Tuple, out
		assert_equal "Test_Module", out.values[0]
		assert_equal 42, out.values[1]
		assert_equal 20, out.values[2]
	end

	def test_load_assignment_into_variable_identifier
		out = Drive.interp "mod := @load 'tests/fixtures/test_module.disk'
		(mod, mod.MODULE_NAME, mod.MODULE_VALUE, mod.module_func(10))"

		assert_instance_of Disk::Tuple, out
		assert_instance_of Disk::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "mod := @load 'tests/fixtures/test_module.disk'
			MODULE_NAME"
		end
	end

	def test_load_assignment_into_class_identifier
		out = Drive.interp "Module := @load 'tests/fixtures/test_module.disk'
		(Module, Module.MODULE_NAME, Module.MODULE_VALUE, Module.module_func(10))"

		assert_instance_of Disk::Tuple, out
		assert_instance_of Disk::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "Module := @load 'tests/fixtures/test_module.disk'
			MODULE_NAME"
		end
	end

	def test_load_assignment_into_constant_identifier
		out = Drive.interp "MODULE := @load 'tests/fixtures/test_module.disk'
		(MODULE, MODULE.MODULE_NAME, MODULE.MODULE_VALUE, MODULE.module_func(10))"

		assert_instance_of Disk::Tuple, out
		assert_instance_of Disk::Scope, out.values[0]
		assert_equal "Test_Module", out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 20, out.values[3]

		# Verify declarations are NOT in current scope
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "MODULE := @load 'tests/fixtures/test_module.disk'
			MODULE_NAME"
		end
	end

	def test_load_same_file_into_multiple_scopes
		out = Drive.interp "
		lib1 := @load 'tests/fixtures/test_module.disk'
		lib2 := @load 'tests/fixtures/test_module.disk'

		(lib1, lib2, lib1.MODULE_VALUE, lib2.MODULE_VALUE, lib1 != lib2)"

		assert_instance_of Disk::Tuple, out
		assert_instance_of Disk::Scope, out.values[0]
		assert_instance_of Disk::Scope, out.values[1]
		assert_equal 42, out.values[2]
		assert_equal 42, out.values[3]
		assert out.values[4]

		# Scopes are different objects even though loaded from same file
		refute_equal out.values[0].object_id, out.values[1].object_id
	end

	def test_double_loading_file
		assert_raises Disk::Cannot_Reassign_Constant do
			out = Drive.interp "
			@load 'tests/fixtures/constants.disk'
			CODE = 123"
		end
	end

	def test_for_loop
		out = Drive.interp "
		NUMBERS := [4, 8, 15, 16, 23, 42]
		numbers := []

		for NUMBERS
			numbers << it
		end

		(numbers == NUMBERS, numbers, NUMBERS)"
		assert out.values[0]
	end

	def test_for_loop_with_scopes
		out = Drive.interp <<~DISK
		    Numbers {
		    	numbers := []

				Self ( numbers;
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
		DISK
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_by_strides
		out = Drive.interp "
		NUMBERS := [4, 8, 15, 16, 23, 42]
		numbers := []

		for NUMBERS by 2
			numbers << it
		end

		numbers"
		assert_equal [[4, 8], [15, 16], [23, 42]], out.values.map(&:values)
	end

	def test_for_loop_at_and_it_builtins
		out = Drive.interp "
		indices := []

		for [4, 8, 15, 16, 23, 42]
			indices << '`at`: `it`'
		end

		indices"
		assert_equal ['0: 4', '1: 8', '2: 15', '3: 16', '4: 23', '5: 42'], out.values
	end

	def test_for_loop_with_ranges
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
		for [1, 2, 3, 4, 5] map
			it * 2
		end"
		assert_equal [2, 4, 6, 8, 10], out.values
	end

	def test_for_loop_map_with_index
		out = Drive.interp "
		for ['a', 'b', 'c'] map
			'`at`:`it`'
		end"
		assert_equal ['0:a', '1:b', '2:c'], out.values
	end

	def test_for_loop_map_with_stride
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6] map by 2
			it.0 + it.1
		end"
		assert_equal [3, 7, 11], out.values
	end

	def test_for_loop_select
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6] select
			it % 2 == 0
		end"
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_select_with_index
		out = Drive.interp "
		for ['a', 'b', 'c', 'd', 'e'] select
			at < 3
		end"
		assert_equal ['a', 'b', 'c'], out.values
	end

	def test_for_loop_select_with_stride
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] select by 2
			it.0 + it.1 > 5
		end"
		assert_equal [[3, 4], [5, 6], [7, 8]], out.values.map(&:values)
	end

	def test_for_loop_reject
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6] reject
			it % 2 == 0
		end"
		assert_equal [1, 3, 5], out.values
	end

	def test_for_loop_reject_with_index
		out = Drive.interp "
		for ['a', 'b', 'c', 'd', 'e'] reject
			at < 2
		end"
		assert_equal ['c', 'd', 'e'], out.values
	end

	def test_for_loop_reject_with_stride
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] reject by 2
			it.0 + it.1 > 5
		end"
		assert_equal [[1, 2]], out.values.map(&:values)
	end

	def test_for_loop_count
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6] count
			it % 2 == 0
		end"
		assert_equal 3, out
	end

	def test_for_loop_count_with_index
		out = Drive.interp "
		for ['a', 'b', 'c', 'd', 'e'] count
			at >= 2
		end"
		assert_equal 3, out
	end

	def test_for_loop_count_with_stride
		out = Drive.interp "
		for [1, 2, 3, 4, 5, 6, 7, 8] count by 2
			it.0 + it.1 > 5
		end"
		assert_equal 3, out
	end

	def test_for_loop_map_with_skip
		out = Drive.interp "
		for [1, 2, 3, 4, 5] map
			skip if it == 3
			it * 2
		end"
		assert_equal [2, 4, nil, 8, 10], out.values
	end

	def test_for_loop_map_with_stop
		out = Drive.interp "
		for [1, 2, 3, 4, 5] map
			stop if it == 4
			it * 2
		end"
		assert_equal [2, 4, 6], out.values
	end

	def test_for_loop_verbs_do_not_mutate
		out = Drive.interp "
		original := [1, 2, 3, 4, 5]
		doubled := for original map
			it * 2
		end
		original"
		assert_equal [1, 2, 3, 4, 5], out.values
	end

	def test_while_loop_skip
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
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
		out = Drive.interp "
		Vector {
			x := 0
			y := 0

			Self ( x, y;
				self.x = x
				self.y = y
			)
		}

		add ( @splatr vec;
			x + y
		)

		v := Vector(3, 4)
		add(v)"
		assert_equal 7, out
	end

	def test_readable_unpack_with_identifier
		out = Drive.interp "
		Point {
			a := 0
			b := 0


			Self ( a, b;
				self.a = a
				self.b = b
			)
		}

		calc (;
			p := Point(10, 20)
			@splatr p
			a + b
		)

		calc()"
		assert_equal 30, out
	end

	def test_readable_unpack_with_local_declarations
		out = Drive.interp "
		Point {
			a := 0
			b := 0

			Self ( a, b;
				self.a = a
				self.b = b
			)
		}

		p := Point(4, 8)
		@splatr p
		one := a + b
		@unsplat p

		@splatr Point(15, 16)
		(one, a + b)"
		assert_equal [12, 31], out.values
	end

	def test_unpack_and_nested_functions
		out = Drive.interp "
		Point {
			a := 0
			b := 0

			Self ( a, b;
				self.a = a
				self.b = b
			)
		}

		outer (;
			p := Point(23, 42)
			@splatr p

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
		out = Drive.interp "
		Vector {
			x := 0
			Self ( x; self.x = x )
		}

		add ( @splatr vec;
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

		out = Drive.interp "#{shared_code}
		Type().number"
		assert_equal 4, out

		out = Drive.interp "#{shared_code}
		Type().calling_private_through_instance()"
		assert_equal 8, out

		out = Drive.interp "#{shared_code}
		Type().static"
		assert_equal 15, out

		out = Drive.interp "#{shared_code}
		Type().calling_static_through_instance()"
		assert_equal 15, out

		out = Drive.interp "#{shared_code}
		Type().calling_static_private_through_instance()"
		assert_equal 16, out

		out = Drive.interp "#{shared_code}
		Type.calling_static_through_static()"
		assert_equal 15, out

		out = Drive.interp "#{shared_code}
		Type.calling_static_private_through_static()"
		assert_equal 16, out

		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Type()._private"
		end

		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Type()._static_private"
		end

		assert_raises Disk::Cannot_Call_Private_Static_Member_On_Type do
			Drive.interp "#{shared_code}
			Type._static_private"
		end

		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "
			Inner { _secret := 42 }
		    Outer { inner := Inner() }
            Outer().inner._secret"
		end

		out = Drive.interp "#{shared_code}
		Type.static = 4815
		Type.static"
		assert_equal 4815, out

		out = Drive.interp "#{shared_code}
		Type.nilled"
		assert_nil out

		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Type()._private = 100"
		end

		assert_raises Disk::Cannot_Call_Private_Static_Member_On_Type do
			Drive.interp "#{shared_code}
		    Type._static_private = 100"
		end

		assert_raises Disk::Cannot_Call_Instance_Member_On_Type do
			Drive.interp "#{shared_code}
			Type.number"
		end

		assert_raises Disk::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Drive.interp "Self.whatever"
		end
	end

	def test_proxy_string_members
		out = Drive.interp "String().length"
		assert_equal 0, out

		out = Drive.interp "'hello'.length"
		assert_equal 5, out

		out = Drive.interp "'a'.ord"
		assert_equal 97, out

		out = Drive.interp "'A'.ord"
		assert_equal 65, out

		out = Drive.interp "'walt!'.upcase()"
		assert_equal "WALT!", out

		out = Drive.interp "'WALT!'.downcase()"
		assert_equal "walt!", out

		assert_raises Disk::Invalid_Ruby_Proxy_Usage do
			Drive.interp "@ruby whatever"
		end

		assert_raises Disk::Invalid_Ruby_Proxy_Usage do
			Drive.interp "@ruby 123"
		end

		assert_raises Disk::Invalid_Ruby_Proxy_Usage do
			Drive.interp "Type { @ruby 123, }"
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
		out = Drive.interp "#{shared_code}
		Merged | Base | Other {}
		m := Merged()
		(m.base_instance_public, m.other_instance)"
		assert_equal [1, 3], out.values

		# Static members accessible from union
		out = Drive.interp "#{shared_code}
		Merged | Base | Other {}
		Merged.base_static_public"
		assert_equal 10, out

		out = Drive.interp "#{shared_code}
		Merged | Base | Other {}
		Merged.other_static_public"
		assert_equal 30, out

		# Instance can access static from union
		out = Drive.interp "#{shared_code}
		Merged | Base | Other {}
		Merged().base_static_public"
		assert_equal 10, out

		# Privacy preserved through union
		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Merged | Base | Other {}
			Merged()._base_instance_private"
		end

		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Merged | Base | Other {}
			Merged()._other_private"
		end

		assert_raises Disk::Cannot_Call_Private_Static_Member_On_Type do
			Drive.interp "#{shared_code}
			Merged | Base | Other {}
			Merged._base_static_private"
		end

		# Binding preserved - cannot access instance members on Type
		assert_raises Disk::Cannot_Call_Instance_Member_On_Type do
			Drive.interp "#{shared_code}
			Merged | Base | Other {}
			Merged.base_instance_public"
		end

		assert_raises Disk::Cannot_Call_Instance_Member_On_Type do
			Drive.interp "#{shared_code}
			Merged | Base | Other {}
			Merged.other_instance"
		end

		# Difference composition - static members removed correctly
		out = Drive.interp "#{shared_code}
		Diff | Base ~ Other {}
		Diff().base_instance_public"
		assert_equal 1, out

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Diff | Base ~ Other {}
			Diff().other_instance"
		end

		# Static members also removed
		out = Drive.interp "#{shared_code}
		Diff | Base ~ Other {}
		Diff.base_static_public"
		assert_equal 10, out

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Diff | Base ~ Other {}
			Diff.other_static_public"
		end

		# Privacy maintained after difference
		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
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
		out = Drive.interp "#{shared_code}
		Inter | Left & Right {}
		Inter().shared_instance"
		assert_equal 1, out

		# Intersection removes non-shared instance members
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter().left_only"
		end

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter().right_only"
		end

		# Intersection keeps shared static members
		out = Drive.interp "#{shared_code}
		Inter | Left & Right {}
		Inter.shared_static"
		assert_equal 10, out

		# Intersection removes non-shared static members
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.left_static_only"
		end

		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.right_static_only"
		end

		# Privacy preserved through intersection
		assert_raises Disk::Cannot_Call_Private_Instance_Member do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter()._shared_private"
		end

		assert_raises Disk::Cannot_Call_Private_Static_Member_On_Type do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter._shared_static_private"
		end

		# Binding preserved through intersection
		assert_raises Disk::Cannot_Call_Instance_Member_On_Type do
			Drive.interp "#{shared_code}
			Inter | Left & Right {}
			Inter.shared_instance"
		end

		# Symmetric difference composition - keeps only non-shared members
		# Symmetric diff keeps unique instance members from Left
		out = Drive.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym().left_only"
		assert_equal 3, out

		# Symmetric diff keeps unique instance members from Right
		out = Drive.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym().right_only"
		assert_equal 6, out

		# Symmetric diff removes shared instance members
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym().shared_instance"
		end

		# Symmetric diff keeps unique static members from Left
		out = Drive.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym.left_static_only"
		assert_equal 30, out

		# Symmetric diff keeps unique static members from Right
		out = Drive.interp "#{shared_code}
		Sym | Left ^ Right {}
		Sym.right_static_only"
		assert_equal 60, out

		# Symmetric diff removes shared static members
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym.shared_static"
		end

		# Binding preserved through symmetric difference
		assert_raises Disk::Cannot_Call_Instance_Member_On_Type do
			Drive.interp "#{shared_code}
			Sym | Left ^ Right {}
			Sym.left_only"
		end
	end

	def test_static_declarations_fixture
		out = Drive.interp_file 'tests/fixtures/static_declarations.disk'
		assert_equal true, out
	end

	def capture_stdout
		out, $stdout = $stdout, StringIO.new
		yield
		$stdout.string
	ensure
		$stdout = out
	end

	def test_puts_directive
		printed = nil
		result  = nil
		printed = capture_stdout { result = Drive.interp "@puts 'Walt!'" }
		assert_equal 'Walt!', result
		assert_equal "'Walt!'\n", printed # strings always display single-quoted
	end

	# `@puts` is a Context method now (disks/context.disk) -- multiple args, parens optional, and
	# it can be captured / aliased.
	def test_puts_takes_multiple_args_and_returns_them
		printed = nil
		result  = nil
		printed = capture_stdout { result = Drive.interp '@puts 1, 2, 3' }
		assert_equal "1\n2\n3\n", printed
		assert_equal [1, 2, 3], result.values

		capture_stdout { result = Drive.interp('@puts(7)') } # explicit parens, single arg -> passthrough
		assert_equal 7, result
	end

	def test_puts_can_be_captured_and_wrapped
		printed = capture_stdout do
			out = Drive.interp <<~CODE
			    shout ( x; @puts(x.upcase()) )
			    shout('hey')
			CODE
			assert_equal 'HEY', out
		end
		assert_equal "'HEY'\n", printed
	end

	def test_puts_is_a_passthrough_inline
		result = nil
		capture_stdout { result = Drive.interp("double ( n; n * 2 )\ndouble(@puts 21)") }
		assert_equal 42, result
	end

	# `@root_path` is a no-arg Context property (moved from a directive).
	def test_root_is_the_project_path
		assert_equal Drive::ROOT_PATH, Drive.interp('@root_path')
		assert_equal Drive::ROOT_PATH, Drive.interp('@.root_path')
		assert_equal "at #{Drive::ROOT_PATH}", Drive.interp('"at `@root_path`"')
	end

	# `@` is a struct (disks/context.disk) the interpreter fills -- reflective vitals as computed
	# values, the function members (`to_s`/`puts`/...) as synthesized callable stand-ins.
	def test_context_is_a_filled_struct
		assert_kind_of Disk::Context, Drive.interp('@')
		assert_equal '@Global', Drive.interp('@.to_s()')
		assert_equal 'Point', Drive.interp("Point { x, }\nPoint.@name")
		assert_equal '@Point', Drive.interp("Point { x, }\nPoint().@to_s()")
		# a function member is callable; a data member resolves to its value
		assert_equal 'hi', Drive.interp("shout := @puts\nshout('hi')")
	end

	# `@.type` / `@.types` work on any value, not just a Type/Instance (plain `.type`/`.types` stays
	# user-space). Falls out of #context_for working on any Scope + #maybe_instance wrapping every value.
	def test_context_type_reads_on_a_plain_value
		assert_equal 'Array',   Drive.interp('[1, 2, 3].@type')
		assert_equal 'Integer', Drive.interp('4.@type')
		assert_equal 'String',  Drive.interp('"hi".@type')
		assert_equal 'Range',   Drive.interp('(1...5).@type')
		assert_equal 'Nil',     Drive.interp('nil.@type')          # #maybe_instance's nil now goes through #adopt_type
		assert Drive.interp("4.@types.include?('Number')")
	end

	# `@sleep n` is a Context method; passes through to Ruby's sleep (returns seconds slept).
	def test_sleep_intrinsic
		assert_equal 0, Drive.interp('@sleep 0.00001')
		assert_equal 0, Drive.interp('nap := @sleep, nap(0.00001)')
	end

	def test_assert_and_refute_intrinsics
		assert_equal true, Drive.interp('@assert 1 == 1')
		assert_equal false, Drive.interp('@refute 1 == 2')

		err = assert_raises(Disk::Assert_Triggered) { Drive.interp "@assert 1 == 2, 'nope'" }
		assert_equal 'nope', err.assertion_message

		assert_raises(Disk::Refute_Triggered) { Drive.interp '@refute true' }

		# a parenthesized condition followed by more of the expression, then the message
		refute_raises { Drive.interp "@assert (1 == 1) == true, 'grouped condition'" }
	end

	# ### user-declarable `@` members on a Type ###

	def test_context_member_declared_on_a_type_is_readable
		out = Drive.interp <<~CODE
		    Thing {
		    	@label: String = "widget"
		    	@meta := 42
		    }
		    (Thing.@label, Thing.@meta)
		CODE
		assert_equal ['widget', 42], out.values
	end

	def test_context_member_is_visible_through_an_instance
		out = Drive.interp <<~CODE
		    Thing { @label: String = "widget" }
		    Thing().@label
		CODE
		assert_equal 'widget', out
	end

	def test_context_annotation_without_a_value_is_nil
		assert_nil Drive.interp("Thing { @rank: Number }\nThing.@rank")
	end

	def test_context_member_is_readable_bare_inside_the_type_body
		out = Drive.interp <<~CODE
		    Thing {
		    	@label := "w"
		    	describe (; @label )
		    }
		    Thing().describe()
		CODE
		assert_equal 'w', out
	end

	def test_context_member_can_be_overwritten_but_must_already_exist
		out = Drive.interp <<~CODE
		    Thing { @label: String = "widget" }
		    Thing.@label = "gadget"
		    Thing.@label
		CODE
		assert_equal 'gadget', out

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp "Thing { @a := 1 }\nThing.@b = 2"
		end
	end

	def test_context_declaration_outside_a_type_raises
		assert_raises Disk::Context_Declaration_Outside_Type do
			Drive.interp '@x := 1'
		end
	end

	def test_context_declaration_cannot_shadow_a_builtin_member
		assert_raises Disk::Cannot_Override_Context_Member do
			Drive.interp 'Thing { @name := "x" }'
		end
		assert_raises Disk::Cannot_Override_Context_Member do
			Drive.interp 'Thing { @types := "x" }'
		end
	end

	def test_context_member_does_not_leak_into_plain_dot_access
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "Thing { @label := \"w\" }\nThing.label"
		end
	end

	def test_multiple_unpacks
		shared_code = <<~DISK
		    Point {
		    	a := 0
		    	b := 0

		    	Self ( a, b;
		    		self.a = a
		    		self.b = b
		    	)
		    }
		DISK

		out = Drive.interp "#{shared_code}
		p := Point(4, 8)
		@splatr p
		(a, b)"
		assert_equal [4, 8], out.values

		# note: Unpacks function like a stack, the most recent unpack is the one whose identifier takes precedence.
		out = Drive.interp "#{shared_code}
		p := Point(4, 8)
		p2 := Point(15, 16)
		@splatr p
		@splatr p2
		(a, b)"
		assert_equal [15, 16], out.values

		out = Drive.interp "#{shared_code}
		p := Point(4, 8)
		p2 := Point(15, 16)
		@splatr p
		@unsplat p2
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
		assert_equal "TEST (SWIZZLED)", Drive.interp(code)
	end

	def test_reading_files
		out = Drive.interp "File_System.read_file_to_string('tests/fixtures/hello_read.txt')"
		assert_equal "Hello, Read!\n", out.value # note: There is a newline at the end of the file, so it has to be included here
	end

	def test_html_fence_with_interpolation
		out = Drive.interp "
		name := 'Cooper'
		```html
		<h1>Welcome `name`</h1>
		```"
		assert_instance_of ::String, out
		assert_equal '<h1>Welcome Cooper</h1>', out.strip
	end

	def test_html_fence_without_interpolation
		out = Drive.interp '```html
		<p>Plain text</p>
		```'
		assert out.include?('<p>Plain text</p>')
	end

	def test_html_fence_in_route_handler
		out = Drive.interp "
		@load 'disks/server.disk'

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
		out = Drive.interp "
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
		assert_equal 4, Drive.interp('x := 4, x')
		assert_equal 'hello', Drive.interp('x := "hello", x')
	end

	def test_walrus_reinitializes_type
		assert_equal 'hello', Drive.interp('x := 4, x := "hello", x')
	end

	def test_walrus_same_type_reassign_with_equals
		assert_equal 8, Drive.interp('x := 4, x = 8, x')
	end

	def test_walrus_type_contract_violation
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'x := 4, x = "hello"'
		end
	end

	def test_walrus_contract_violation_message
		err = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'x := 4, x = "hello"'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message
	end

	def test_manual_type_annotation_contract
		err = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'x: Number = 4, x = "hey"'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message

		# Fine if redeclared
		Drive.interp 'x: Number = 4, x := "hey"'

		err = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'x: Number = 4, x := "hey", x = 8'
		end
		assert_match 'Number', err.message # the actual value 8 -- reported as the family name
		assert_match 'String', err.message
	end

	# `x: Number = 'oops'` (a literal RHS) is caught statically before the interpreter ever runs (see type_checker_test.rb) -- these cover the gap that leaves open: a *non-literal* RHS (an identifier, a function, ...) whose actual value mismatches the annotation on the very first, self-declaring assignment. The static checker silently skips non-literal RHS entirely, so this has to be caught dynamically in #interp_infix_assignment, the same place reassignment already is.
	def test_first_assignment_type_contract_with_non_literal_rhs
		# Plain nominal annotation.
		err = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'bad := "oops"
				x: Number = bad'
		end
		assert_match 'Number', err.message
		assert_match 'String', err.message

		# Signature-typed annotation, assigning a real function whose actual shape doesn't match.
		err = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'wrong ( a, b; a + b )
				x: (Number -> String;) = wrong'
		end
		assert_match '(Number -> String;)', err.message

		# Inline signature form (no separate alias), same check.
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'wrong ( a, b; a + b )
				x: (Number -> String;) = wrong'
		end

		# Same check applies to a typed member declared inside a Type/Instance body, not just top level.
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'bad := "oops"
				Thing {
					x: Number = bad
				}
				Thing()'
		end

		# And inside a constructor, self-declaring from a param.
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'Thing {
					Self ( v;
						x: Number = v
					)
				}
				Thing("oops")'
		end
	end

	def test_new_comma_nil_init
		assert_raises(Disk::Undeclared_Identifier) do
			Drive.interp <<~CODE
			    x := (abc,1)
				(x, abc)
			CODE
		end

		out = Drive.interp <<~CODE
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

		out = Drive.interp <<~CODE
		    #{prelude}
			# You can now make `11:22pm` evaluate to something!
			11:22pm
		CODE
		assert_instance_of Disk::Instance, out
		assert_equal 11, out.get('hour')
		assert_equal 22, out.get('minute')
		assert_equal 'pm', out.get('period')
	end

	def test_prefix_operator_overload
		out = Drive.interp <<~CODE
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
		assert_instance_of Disk::Instance, out
		assert_equal 42, out.get('amount')
		assert_equal 'US Dollar', out.get('name')
		assert_equal 'USD', out.get('code')
	end

	def test_operator_overload_scoped_to_function
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
		    @operator !! @prefix 900 ( n;
		    	n * n
		    )

		    !!5
		CODE
		assert_equal 25, out
	end

	def test_pipeing_with_operator_overloads
		out = Drive.interp <<~CODE
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

	# #interp_string's own interpolation-region regex used `.` with no /m flag, so a sub-expression
	# containing a real embedded newline (a nested `"\n"` escape, e.g. `` `arr.join("\n")` ``) couldn't
	# be matched end to end -- `.*?` can't cross a newline without /m -- so the scan silently found no
	# match and the whole `` `...` `` region was left as literal, un-interpolated text in the output.
	def test_string_interpolation_handles_a_sub_expression_containing_a_real_newline
		out = Drive.interp '
		arr := ["a", "b"]
		"X:\n`arr.join(\"\n\")`:Y"'
		assert_equal "X:\na\nb:Y", out
	end

	def test_string_interpolation_can_see_custom_operators_declared_elsewhere_in_the_program
		# Same operators/functions as the test above, interpolated instead -- used to only evaluate to "4" (stopped at the first token it didn't recognize), since interp_string re-parsed the substring in total isolation from the rest of the program's @operator registrations.
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
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
		assert_equal [Disk::Tuple.new([:x, 4]), Disk::Tuple.new([:y, 8])], out.values
	end

	def test_dictionary_in_for_loops_key_and_value_builtins
		out = Drive.interp <<~CODE
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
		assert_equal [Disk::Tuple.new([:x, 4]), Disk::Tuple.new([:y, 8])], out.values
	end

	def test_dictionary_in_for_loops_stride_is_ignored
		out = Drive.interp <<~CODE
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
		assert_equal [Disk::Tuple.new([:a, 15]), Disk::Tuple.new([:b, 16]), Disk::Tuple.new([:c, 23])], out.values
	end

	def test_type_comparison_operators
		shared = <<~CODE
		    Base {}
		CODE
		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
		    Right | Base {}
			l := Left()
			r := Right()
			(Left === Right, Left === Left, l === r, l === l)
		CODE
		assert_equal [false, true, false, true], out.values

		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
		    Right | Base {}
			l := Left()
			r := Right()
			(Left =!= Right, Right =!= Right, l =!= r, r =!= r)
		CODE
		assert_equal [true, false, true, false], out.values

		# Siblings that only share a common composed base (Base) are NOT comparable via =/= -- neither one's types are a subset of theother's, even though they overlap. This is what distinguishes =/= from a plain "do these share any composed type" check.
		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
		    Right | Base {}
			l := Left()
			r := Right()
			(Left =>= Right, Right =>= Left, l =>= r, r =>= l)
		CODE
		assert_equal [false, false, false, false], out.values

		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
		    Right | Base {}
			l := Left()
			r := Right()
			(Left =<= Right, Right =<= Left, l =<= r, r =<= l)
		CODE
		assert_equal [false, false, false, false], out.values

		# `A =>= B` is true when A's composed types are a superset of B's -- i.e. A composes with at least everything B does. Left composes Base, so Left has "at least" Base, but not the other way around.
		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
			l := Left()
			n := Base()
			(Left =>= Base, Base =>= Left, Left =>= Left, l =>= n, n =>= l)
		CODE
		assert_equal [true, false, true, true, false], out.values

		# =<= mirrors =>= with the operands' roles reversed.
		out = Drive.interp <<~CODE
			#{shared}
		    Left | Base {}
			l := Left()
			n := Base()
			(Base =<= Left, Left =<= Base, Left =<= Left, n =<= l, l =<= n)
		CODE
		assert_equal [true, false, true, true, false], out.values

		# `A =/= B` is true when A and B share no composed types at all. A/B share nothing. Left/Right both compose Base, so they're not disjoint even though neither composes the other. Left/Base aren't disjoint either, since Left composes Base directly.
		out = Drive.interp <<~CODE
			#{shared}
		    Aa {}
		    Bb {}
		    Left | Base {}
		    Right | Base {}
			a := Aa()
			b := Bb()
			l := Left()
			r := Right()
			(Aa =/= Bb, Aa =/= Aa, Left =/= Right, Left =/= Base, a =/= b, l =/= r, l =/= Base)
		CODE
		assert_equal [true, false, false, false, true, false, false], out.values
	end

	# `Any` (disks/global.disk) is a universal wildcard -- everything except nil counts as Any via `==`/`===`, with no composition required (`Thing | Any {}` isn't needed).
	def test_any_type_is_universally_equal_via_double_and_triple_equals
		out = Drive.interp <<~CODE
		    Thing { x := 1 }
		    t := Thing()
		    (String == Any, Any == String, Number == Any, Thing == Any, t == Any, Any == t, 4 == Any, 'hi' == Any)
		CODE
		assert_equal [true, true, true, true, true, true, true, true], out.values

		out = Drive.interp <<~CODE
		    Thing { x := 1 }
		    t := Thing()
		    (String === Any, Any === String, t === Any, Any === t)
		CODE
		assert_equal [true, true, true, true], out.values
	end

	# nil is the one thing that doesn't count as Any -- "if you're not nil, you're Any at the very least" stops short of nil itself.
	def test_nil_is_not_any
		out = Drive.interp '(nil == Any, Any == nil, nil === Any, Any === nil)'
		assert_equal [false, false, false, false], out.values
	end

	# != / =!= are the natural negation, kept consistent with == / === above rather than falling through to identity-based comparison.
	# `"Flying" == Flying` -- a String equals a bare Type (either operand order) when it spells the
	# type's own name. `==`/`!=` only. This is what makes `set.include?(SomeType)` work against a Set
	# that stores only type-name strings (`@.composed_types`).
	def test_string_equals_a_bare_type_by_name
		out = Drive.interp <<~CODE
		    Flying { airborne := true }
		    ('Flying' == Flying, Flying == 'Flying', 'Swimming' == Flying, 'Flying' != Flying)
		CODE
		assert_equal [true, true, false, false], out.values

		# an instance is not a bare type -- ordinary comparison applies
		assert_equal false, Drive.interp("Flying { x, }\n'Flying' == Flying()")

		# the point of it: include? against a Set / Array of type names
		out = Drive.interp <<~CODE
		    Flying { airborne := true }
		    Swimming { submerged := true }
		    Duck | Flying { name := 'duck' }
		    (Duck.@composed_types.include?(Flying), Duck.@composed_types.include?(Swimming))
		CODE
		assert_equal [true, false], out.values
	end

	def test_any_type_negated_comparisons_stay_consistent
		out = Drive.interp '(String != Any, Any != String, String =!= Any, Any =!= String)'
		assert_equal [false, false, false, false], out.values

		out = Drive.interp '(nil != Any, Any != nil, nil =!= Any, Any =!= nil)'
		assert_equal [true, true, true, true], out.values
	end

	# `===` is documented as "mutual `=>=`" -- Any wouldn't actually be a universal supertype if `X === Any` were true while `X =>= Any` stayed false, so `=>=`/`=<=`/`=/=` get the same wildcard treatment as `==`/`===` above, not just the two operators the feature originally shipped with.
	def test_any_type_is_universal_via_superset_and_disjoint_operators
		out = Drive.interp '(String =>= Any, Any =>= String, String =<= Any, Any =<= String)'
		assert_equal [true, true, true, true], out.values

		# Any is never disjoint from anything non-nil -- the same "you're Any at the very least" rule.
		out = Drive.interp '(String =/= Any, Any =/= String)'
		assert_equal [false, false], out.values

		# nil stays the one exception here too: not a superset relationship, and disjoint (shares nothing).
		out = Drive.interp '(nil =>= Any, Any =>= nil, nil =<= Any, Any =<= nil, nil =/= Any, Any =/= nil)'
		assert_equal [false, false, false, false, true, true], out.values
	end

	def test_regex_match_operators
		# =~ behaves like Ruby's String#=~: returns the match index, or nil.
		assert_equal 5, Drive.interp("'hello123' =~ '\\d+'")
		assert_nil Drive.interp("'hello' =~ '\\d+'")

		# !~ is the boolean negation of a match.
		assert_equal false, Drive.interp("'hello123' !~ '\\d+'")
		assert_equal true, Drive.interp("'hello' !~ '\\d+'")

		# Works through variables too, not just literals.
		out = Drive.interp <<~CODE
		    x := 'foo_bar'
		    x =~ '_'
		CODE
		assert_equal 3, out

		out = Drive.interp <<~CODE
		    x := 'foobar'
		    x !~ '_'
		CODE
		assert_equal true, out
	end

	def test_function_signatures
		out = Drive.interp 'Num_To_Str := (Number -> String;)'
		assert_kind_of Disk::Func_Signature, out
		assert_equal ['Number'], out.param_types
		assert_equal 'String', out.return_type

		# Named + typed param — the name is discarded, only the type survives.
		out = Drive.interp '(a: Number -> String;)'
		assert_equal ['Number'], out.param_types
		assert_equal 'String', out.return_type

		# Zero-arg signature.
		out = Drive.interp '(-> String;)'
		assert_equal [], out.param_types
		assert_equal 'String', out.return_type

		# Bare and named+typed params can mix in the same param list.
		out = Drive.interp '(Number, a: Number -> String;)'
		assert_equal %w(Number Number), out.param_types
		assert_equal 'String', out.return_type

		# Named param with no type annotation is a malformed signature — every param slot in a signature literal must carry a type.
		assert_raises Disk::Invalid_Func_Signature do
			Drive.interp '(a -> String;)'
		end

		# Bare as a top-level expression, not just as the RHS of :=.
		out = Drive.interp '(Number -> String;)'
		assert_kind_of Disk::Func_Signature, out

		# `name: (...)` with no return type is still a signature (the colon form opts in) -- a bare
		# `foo (;)` without the colon stays a real empty function.
		out = Drive.interp 'takes_a_number: (Number;)'
		assert_kind_of Disk::Func_Signature, out
		assert_equal ['Number'], out.param_types
		assert_nil out.return_type

		assert_kind_of Disk::Func_Signature, Drive.interp('does_nothing: (;)')
		assert_kind_of Disk::Func, Drive.interp('empty (;)') # no colon -> a real function, not a signature

		# Regression: an ordinary Type declaration with a method must still parse as a real type — now unambiguous, since a signature literal never starts with a Capitalized type name anymore.
		out = Drive.interp <<~CODE
		    Person {
		    	greet (; "hi" )
		    }
		    Person().greet()
		CODE
		assert_equal 'hi', out
	end

	def test_function_return_type_enforcement
		# Declared return type matches what's actually returned.
		out = Drive.interp <<~CODE
		    identity ( a: Number -> Number; a )
		    identity(5)
		CODE
		assert_equal 5, out

		# Return types are not validated until the functino is called, so this will not raise a contra t violation
		refute_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    identity ( a: Number -> String; 'not a number' )
			CODE
		end

		# Declared return type doesn't match the actual value.
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    identity ( a: Number -> Number; 'not a number' )
			    identity(5)
			CODE
		end
		assert_equal 'Number', error.contract
		assert_equal 'String', error.actual

		# A signature has no implementation, so it can't be called.
		assert_raises Disk::Cannot_Call_Func_Signature do
			Drive.interp <<~CODE
			    double: (Number -> Number;)
			    double()
			CODE
		end

		refute_raises Disk::Cannot_Call_Func_Signature do
			Drive.interp <<~CODE
			    double: (Number -> Number;) = (a: Number -> Number; a*2)
			    double(2)
			CODE
		end

		# No declared return type — nothing is checked, any value is fine.
		out = Drive.interp <<~CODE
		    identity ( a; 'anything' )
		    identity(5)
		CODE
		assert_equal 'anything', out

		# Signature-only declarations have no body, so there's nothing to enforce against — declaring one must not raise.
		out = Drive.interp <<~CODE
		    double: (Number -> Number;)
		    'ok'
		CODE
		assert_equal 'ok', out

		# A function (anonymous or named) can declare its own return type inline, at the end of its param list, instead of via the `name: Type { }` prefix.
		out = Drive.interp <<~CODE
		    f := ( a: Number -> Number; a * 2 )
		    f(21)
		CODE
		assert_equal 42, out

		out = Drive.interp <<~CODE
		    example ( a: Number -> Number; a * 2 )
		    example(21)
		CODE
		assert_equal 42, out

		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    f := ( a: Number -> Number; 'oops' )
			    f(1)
			CODE
		end
		assert_equal 'Number', error.contract
		assert_equal 'String', error.actual
	end

	# The return-type check used to compare only the value's own primary type name, not its full composed-type set -- a value composed with (not literally named) the declared return type was wrongly rejected as a mismatch, even though returning it is exactly the safe, covariant case (every Task IS a Table).
	def test_function_return_type_enforcement_accepts_composed_types
		out = Drive.interp <<~CODE
		    Table {}
		    Task | Table {}
		    make ( -> Table; Task() )
		    make().@composed_types
		CODE
		assert_equal %w(Task Table), out.set.to_a

		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
		    Num_to_str := (Number -> String;)
		    stringify ( n: Number -> String; 'x' )
		    to_string: Num_to_str = stringify
		    another ( n: Number -> String; 'y' )
		    to_string = another
		    'ok'
		CODE
		assert_equal 'ok', out

		# First declaration with a mismatched shape raises immediately.
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    Num_to_str := (Number -> String;)
			    to_string: Num_to_str = ( x, y; x + y )
			CODE
		end
		assert_equal '(Number -> String;)', error.contract
		assert_equal '(, -> ;)', error.actual

		# Reassigning an already-valid signature-typed identifier to a mismatched shape raises too, comparing structurally rather than as a plain type name.
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    Num_to_str := (Number -> String;)
			    stringify ( n: Number -> String; 'x' )
			    to_string: Num_to_str = stringify
			    to_string = ( x, y; x + y )
			CODE
		end
		assert_equal '(Number -> String;)', error.contract
		assert_equal '(, -> ;)', error.actual

		# Ordinary nominal type annotations are unaffected by signature resolution.
		out = Drive.interp <<~CODE
		    x: Number = 4
		    x = 8
		    x
		CODE
		assert_equal 8, out

		assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    x: Number = 4
			    x = 'oops'
			CODE
		end

		# First declaration of an ordinary nominal type is now checked too, even
		# with a non-literal RHS the static checker can't see.
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    n := 4
			    x: String = n
			CODE
		end
	end

	def test_tuple_and_struct_destructuring
		# Tuple source.
		out = Drive.interp <<~CODE
		    (a, b) := (1, 2)
		    a + b
		CODE
		assert_equal 3, out

		# Struct source.
		out = Drive.interp <<~CODE
		    (a, b) := <1, 2>
		    a + b
		CODE
		assert_equal 3, out

		# Both targets are declared in the current scope, independently readable afterward.
		out = Drive.interp <<~CODE
		    (a, b) := <Number,Number>(10, 20)
		    (a, b)
		CODE
		assert_equal [10, 20], out.values

		# An explicit `: Type` per target is checked against that position's extracted value.
		out = Drive.interp <<~CODE
		    (x: Number, y) := (1, 2)
		    x
		CODE
		assert_equal 1, out

		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp '(x: String, y) := (1, 2)'
		end
		assert_equal 'String', error.contract
		assert_equal 'Number', error.actual

		# Asking for more values than the source has raises, rather than padding with nil.
		error = assert_raises Disk::Destructuring_Arity_Mismatch do
			Drive.interp '(a, b, c) := <Number, Number>(1, 2)'
		end
		assert_equal 3, error.expected
		assert_equal 2, error.actual

		# Asking for fewer is fine -- the rest are just discarded.
		out = Drive.interp '(a, b) := <1, 2, 3>
			a + b'
		assert_equal 3, out

		# Only a Tuple/Struct can be destructured.
		assert_raises Disk::Invalid_Destructuring_Source do
			Drive.interp '(a, b) := 5'
		end

		# Every target must be a plain identifier or an existing-member dot-target.
		assert_raises Disk::Invalid_Destructuring_Target do
			Drive.interp '(1, c) := (1, 2)'
		end

		out = Drive.interp 'a := 0
			(a, b) := (1, 2)
			(a,b)'
		assert_equal [1, 2], out.values
	end

	def test_member_destructuring_targets
		# `thing.member` reassigns an existing member, same as plain `thing.member = value`.
		out = Drive.interp <<~CODE
		    Thing { member, Self (; self.member = 0 ) }
		    thing := Thing()
		    (thing.member, local) := <Number, Number>(1, 1)
		    (thing.member, local)
		CODE
		assert_equal [1, 1], out.values

		# The member must already exist -- destructuring can't silently create one.
		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp <<~CODE
			    Thing { member, Self (; self.member = 0 ) }
			    thing := Thing()
			    (thing.missing, local) := <Number, Number>(1, 1)
			CODE
		end

		# A constant member can't be reassigned this way either.
		assert_raises Disk::Cannot_Reassign_Constant do
			Drive.interp <<~CODE
			    Thing { MEMBER, Self (; self.MEMBER = 0 ) }
			    thing := Thing()
			    (thing.MEMBER, local) := <Number, Number>(1, 1)
			CODE
		end

		# If the member has a previously-recorded type (via `:=`), the extracted value must match it.
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    Thing {
					Self (;
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

	# String values always display single-quoted (String#to_string), regardless of the source literal.
	def test_struct_member_display_regression
		%w(" ').each do |q|
			out = Drive.interp <<~CODE
			    @load 'disks/struct.disk'
			    quad := <1, id := 2, ix: Number, String>(4, 8, 1, #{q}five#{q})
			    quad.to_s()
			CODE
			assert_equal "<4, id: Number = 8, ix: Number = 1, 'five'>", out
		end
	end

	def test_string_equality_regression
		assert Drive.interp('String("Alice") == String("Alice")')
		out = Drive.interp <<~CODE
		    @load 'disks/struct.disk'
		    s := <name: String>("Alice")
		    s.@members.0.value == "Alice"
		CODE
		assert out
	end

	# `!=` derives from a declared `==` (see the `!=` note two entries up) -- disks/string.disk's own `==` overload used to assume its right operand was always another String and crashed reading `.value` off anything else. `!= nil` is the common case this broke (a String compared against something that turned out not to exist).
	def test_string_not_equal_to_nil_regression
		refute_raises do
			assert Drive.interp("String('hi') != nil")
			refute Drive.interp("String('hi') == nil")
			refute Drive.interp("String('hi') == 5")
		end
	end

	# Same class of bug in disks/member.disk/disks/struct.disk's own `==` overloads -- each assumed its right operand was already Member/Struct-shaped.
	def test_member_and_struct_not_equal_to_nil_regression
		refute_raises do
			out = Drive.interp <<~CODE
			    @load 'disks/struct.disk'
			    m := Member('x', String, 4)
			    s := <1, 2>
			    (m != nil, m == nil, s != nil, s == nil)
			CODE
			assert_equal [true, false, true, false], out.values
		end
	end

	def test_self_declaration_during_construction_works_but_external_dot_does_not_regression
		out = Drive.interp <<~CODE
		    Thing {
		        Self (;
		            self.member := 123
		        )
		    }
		    t := Thing()
		    t.member
		CODE
		assert_equal 123, out

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			# but actually it raises something about not being able to declare members on the type outside of Self(;) or the explicit class body declarations
			Drive.interp <<~CODE
			    Thing {
			        not_new_func (;
			            self.member := 123
			        )
			    }
			    t := Thing()
			    t.not_new_func()
			CODE
		end

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp 'Number.yolo = 123'
		end

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp 'Number.yolo := 123'
		end

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp <<~CODE
			    Thing { member, Self (; self.member = 0 ) }
			    thing := Thing()
			    thing.missing = 5
			CODE
		end
	end

	def test_declare_command_on_structs
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~CODE
			    # @declare <id: Number, name: String = "Locke">
				(it, name)
			CODE
		end

		out = Drive.interp <<~CODE
		    @declare <id: Number, name: String = "Locke">
			(id, name)
		CODE
		assert_equal [nil, "Locke"], out.values
	end

	def test_declare_name_only_self_declares_to_nil
		out = Drive.interp <<~CODE
		    @declare "foo"
		    foo
		CODE
		assert_nil out
	end

	def test_declare_name_and_value
		out = Drive.interp <<~CODE
		    @declare "foo", 42
		    foo
		CODE
		assert_equal 42, out
	end

	def test_declare_name_value_and_type
		out = Drive.interp <<~CODE
		    @declare "foo", 42, Number
		    foo
		CODE
		assert_equal 42, out
	end

	def test_declare_value_can_be_any_expression
		out = Drive.interp <<~CODE
		    @declare "foo", 1 + 2
		    foo
		CODE
		assert_equal 3, out
	end

	def test_declare_with_no_value_argument_still_registers_the_name
		# Undeclared before, so a plain (non-annotated) read would normally raise --
		# @declare "foo" alone should self-declare it, same as the nil-init idiom.
		refute_raises Disk::Undeclared_Identifier do
			Drive.interp '@declare "foo"
			foo'
		end
	end

	def test_declare_too_many_arguments_raises
		assert_raises Disk::Invalid_Context_Function_Usage do
			Drive.interp '@declare "foo", 42, Number, "extra"'
		end
	end

	def test_declare_with_type_allows_matching_reassignment
		out = Drive.interp <<~CODE
		    @declare "foo", 42, Number
		    foo = 99
		    foo
		CODE
		assert_equal 99, out
	end

	def test_declare_with_type_rejects_mismatched_reassignment
		assert_raises Disk::Type_Contract_Violation do
			Drive.interp <<~CODE
			    @declare "foo", 42, Number
			    foo = "oops"
			CODE
		end
	end

	def test_declare_without_type_allows_any_reassignment
		out = Drive.interp <<~CODE
		    @declare "foo", 42
		    foo = "now a string"
		    foo
		CODE
		assert_equal 'now a string', out
	end

	def test_declare_inside_function_scope_is_local
		out = Drive.interp <<~CODE
		    make (;
		    	@declare "local_thing", 5
		    	local_thing
		    )
		    make()
		CODE
		assert_equal 5, out
	end

	def test_declare_inside_function_scope_does_not_leak_out
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~CODE
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
		out = Drive.interp "%string(boo Hoo COOL).values"
		assert_equal %w(boo Hoo COOL), out
		assert out.all? { |it| it.is_a? ::String }

		# %str forces lowercase.
		assert_equal %w(boo hoo cool), Drive.interp("%str(Boo hOO COOL).values")

		# %Str forces Capitalcase.
		assert_equal %w(Boo Hoo Cool), Drive.interp("%Str(boo HOO cOOl).values")

		# %STR forces UPPERCASE.
		assert_equal %w(BOO HOO COOL), Drive.interp("%STR(boo Hoo cool).values")

		# Casing has no effect on numbers or symbols
		assert_equal %w(123 ^^^ + - * /), Drive.interp("%string(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Drive.interp("%str(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Drive.interp("%Str(123 ^^^ + - * /).values")
		assert_equal %w(123 ^^^ + - * /), Drive.interp("%STR(123 ^^^ + - * /).values")
	end

	def test_percent_symbol_literals
		# %symbol preserves each identifier's own casing.
		out = Drive.interp "%symbol(BOO hoo Cool).values"
		assert_equal %i(BOO hoo Cool), out
		assert out.all? { |it| it.is_a? ::Symbol }

		# %sym forces lowercase.
		assert_equal %i(boo hoo cool), Drive.interp("%sym(Boo HOO cOOl).values")

		# %Sym forces Capitalcase.
		assert_equal %i(Boo Hoo Cool), Drive.interp("%Sym(boo HOO cOOl).values")

		# %SYM forces UPPERCASE.
		assert_equal %i(BOO HOO COOL), Drive.interp("%SYM(boo Hoo cool).values")

		assert_equal %i(123 ^^^ + - * /), Drive.interp("%symbol(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Drive.interp("%sym(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Drive.interp("%Sym(123 ^^^ + - * /).values")
		assert_equal %i(123 ^^^ + - * /), Drive.interp("%SYM(123 ^^^ + - * /).values")
	end

	def test_percent_literal_is_a_real_array
		out = Drive.interp "%str(a b c)"
		assert_kind_of Disk::Array, out
		assert_equal 3, out.values.count
	end

	def test_percent_literal_interpolation
		out = Drive.interp <<~CODE
		    cool := 2342
		    %str(481516 `cool`)
		CODE
		assert_equal ['481516', '2342'], out.values
		# assert out.values.all? { _1.is_a? Disk::String } # todo; this is currently false
	end

	def test_statement_expressions
		out = Drive.interp "`1+2`"
		assert_kind_of Disk::Statement, out
		assert_kind_of Disk::Infix_Expr, out.expression
		assert_equal "Statement{Disk::Infix_Expr}", out.proxy_to_s

		out = Drive.interp "`1+2`()"
		assert_equal 3, out
	end

	def test_statement_expression_stored_in_a_variable
		# The whole point of Statement -- build it once, call it later, wherever it ends up.
		out = Drive.interp <<~CODE
		    x := `1+2`
		    x()
		CODE
		assert_equal 3, out

		# Same thing, but via a `: Statement` type annotation instead of `:=`.
		out = Drive.interp <<~CODE
		    x: Statement = `1+2`
		    x()
		CODE
		assert_equal 3, out
	end

	def test_statement_expression_re_evaluates_on_every_call
		# Not memoized -- each `()` call re-interprets the wrapped expression fresh.
		out = Drive.interp <<~CODE
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
		# Disk::Statement is a real Instance -- @puts must not crash on one, called or not.
		output          = StringIO.new
		original_stdout = $stdout
		$stdout         = output

		begin
			Drive.interp "@puts `1+2`"
			refute_empty output.string
		ensure
			$stdout = original_stdout
		end
	end

	def test_fancier_statement_example
		out = Drive.interp "x := `@load 'disks/string'`"
		assert_kind_of Disk::Statement, out
	end

	def test_nested_statements_with_mixed_memoization
		# outer wraps two inner Statements, one memoized and one not, and is itself memoized too -- calling outer() a second time shouldn't re-run any of them.
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
		    Thing {
		        value := 42
		        get_val (; self.value )
		    }
		    Thing().get_val()
		CODE
		assert_equal 42, out
	end

	def test_Self_resolves_to_nearest_type
		out = Drive.interp <<~CODE
		    Thing {
		        klass (; Self )
		    }
		    Thing().klass() === Thing
		CODE
		assert out
	end

	def test_Self_dot_access_identical_to_class_name_dot_access
		out = Drive.interp <<~CODE
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
		assert_raises Disk::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Drive.interp 'self'
		end
	end

	def test_Self_raises_outside_type_context
		assert_raises Disk::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Drive.interp 'Self'
		end
	end

	def test_self_dot_declare_self_declares_new_member_during_construction
		out = Drive.interp <<~CODE
		    Thing {
		        Self (;
		            self.member := 123
		        )
		    }
		    Thing().member
		CODE
		assert_equal 123, out

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
		    Thing {
		        Self.count := 0
		    }
		    Thing.count
		CODE
		assert_equal 0, out

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp <<~CODE
			    Thing {
			        bump_late (; Self.new_static := 1 )
			    }
			    Thing().bump_late()
			CODE
		end
	end

	def test_self_dot_func_declares_instance_method
		out = Drive.interp <<~CODE
		    Thing {
		        self.greet (; 'hi' )
		    }
		    Thing().greet()
		CODE
		assert_equal 'hi', out
	end

	def test_Self_dot_func_declares_static_method
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
		    Thing {
		        value := 42
		        make_bare (; Self() )
		    }
		    Thing().make_bare().value
		CODE
		assert_equal 42, out

		out = Drive.interp <<~CODE
		    Thing {
		        value,
		        Self ( v; self.value = v )
		        make_with_arg (; Self(99) )
		    }
		    Thing(1).make_with_arg().value
		CODE
		assert_equal 99, out
	end

	def test_block_comments_are_ignored
		out = Drive.interp <<~CODE
		    ###
		    this whole block, including this fake declaration, is discarded
		    x := 999
		    ###
		    4 + 8
		CODE
		assert_equal 12, out

		# a block comment as the very last expression shouldn't leak its text out as the return value, same as a trailing # comment
		out = Drive.interp <<~CODE
		    add ( a, b;
		        a + b
		        ### sum me ###
		    )
		    add(4, 8)
		CODE
		assert_equal 12, out
	end

	def test_function_body_arg_with_other_arguments
		out = Drive.interp <<~CODE
		    f ( callable: (;), num: Number;
		    	(callable(), num)
		    )

		    f( (; 4), 42 )
		CODE
		assert_equal [4, 42], out.values
	end

	def test_number_rand
		100.times do
			out = Drive.interp 'Number.rand(10)'
			assert_includes 0..10, out
		end
	end

	def test_number_rand_zero
		out = Drive.interp 'Number.rand(0)'
		assert_equal 0, out
	end

	def test_string_positional_dot_index
		assert_equal 'a', Drive.interp('"abc".0')
		assert_equal 'c', Drive.interp('"abc".2')
	end

	def test_string_positional_dot_index_negative
		assert_equal 'c', Drive.interp('"abc".-1')
	end

	def test_string_positional_dot_index_out_of_range_raises
		assert_raises Disk::Invalid_Array_Index do
			Drive.interp '"abc".5'
		end
	end

	def test_string_positional_dot_index_result_is_a_real_string_with_methods
		assert_equal 'A', Drive.interp('"abc".0.upcase()')
	end

	def test_stored_method_reference_keeps_calling_its_own_instances_sibling_methods
		out = Drive.interp "
		Greeter {
			greeting := 'Hello'
			greet ( name; \"`shout(greeting)`, `name`!\" )
			shout ( text; text.upcase() )
		}
		g := Greeter()
		f := g.greet
		f('World')"
		assert_equal 'HELLO, World!', out
	end
end
