require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Regression_Test < Base_Test
	def test_greater_equals_regression
		out = Drive.interp '2+1 >= 1'
		assert out
	end

	def test_precedence_operation_regression
		src = Drive.interp '1 + 2 / 3 - 4 * 5'
		ref = Drive.interp '(1 + (2 / 3)) - (4 * 5)'
		assert_equal ref, src
		assert_equal -19, src
	end

	def test_infixes_regression
		Tape::COMPOUND_OPERATORS.each do |operator|
			code = "left #{operator} right"
			out  = Drive.parse(code)
			assert_kind_of Tape::Infix_Expr, out.first
		end
	end

	def test_self_scope_write_outside_instance_raises_regression
		assert_raises Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Drive.interp 'self.x := 123'
		end
		assert_raises Tape::Cannot_Use_Type_Scope_Operator_Outside_Type do
			Drive.interp 'Self.x := 123'
		end
	end

	def test_global_declared_then_read_bare_regression
		out = Drive.interp 'Global.x := 456
		x'
		assert_equal 456, out
	end

	def test_global_declared_then_read_with_operator_regression
		out = Drive.interp 'Global.y := 789
		Global.y'
		assert_equal 789, out
	end

	def test_self_scope_operator_survives_infix_lhs_regression
		# `self.x,` (nil-init) desugars the identifier and tags it with the keyword; the tag must survive
		# being the left side of the synthesized `=`.
		out = Drive.parse 'self.x? ,'
		assert_kind_of Tape::Nil_Init_Expr, out.first
		assert_equal 'self', out.first.left.scope_operator.value
		assert_equal 'x?', out.first.left.value
	end

	def test_assigning_false_value_regression
		out = Drive.interp 'how := false
		how'
		assert_equal false, out
	end

	def test_identifier_lookup_regression
		out = Drive.interp 'Drive {}, Drive'
		assert_instance_of Type, out
	end

	def test_instance_does_not_have_self_function_regression
		out = Drive.interp '
		Atom {
			Self (;)
		}
		Atom()'
		refute out.has? :Self
	end

	# `Type.Self()` is deliberately not construction sugar -- it's an ordinary call to whatever `Self` resolves to (the type's own raw constructor Func), not `Type()`. No Instance is ever built, so `self.count = num` inside it has nowhere real to write.
	def test_dot_self_call_is_not_construction_sugar_regression
		assert_raises Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Drive.interp 'Widget {
				count := 8

				Self ( num;
					self.count = num
				)
			}
			Widget.Self(15)'
		end
	end

	def test_calling_member_functions
		out = Drive.interp '
		Widget {
			count := -100

			Self ( num;
				self.count = num
			)
		}
		x := Widget(4)
		x.count'
		assert_equal 4, out
	end

	def test_self_member_assignment_in_constructor_regression
		out = Drive.interp '
		Box {
			kind := "NONE"

			Self ( new_kind;
				self.kind = new_kind
			)

			to_s (;
				"`kind`-box"
			)
		}

		b1 := Box("Big")
		s1 := b1.to_s()
		b2 := Box("Small")
		s2 := b2.to_s()
		(b1, s1, b2, s2)
		'
		assert_instance_of Tape::Instance, out.values[0]
		assert_equal "Big-box", out.values[1]
		assert_equal "Small-box", out.values[3]
	end

	def test_identifier_lookup_regression
		out = Drive.interp "x := 123
		funk (;
			Global.x + 2
		)
		funk()"
		assert_equal 125, out

		out = Drive.interp "y := 0
		add ( amount_to_add := 1;
			Global.y + amount_to_add
		)
		(a := add(4))

		(a, add(a * 2))"
		assert_equal [4, 8], out.values

		out = Drive.interp "y := 0
		add ( amount_to_add := 1;
			y += amount_to_add
		)
		a := add(4)

		(y, a)"
		assert_equal [4, 4], out.values

		refute_raises Tape::Undeclared_Identifier do
			out = Drive.interp "
			Thing {
				id,
				name := 'Thingy'

				Self ( new_name := '', id := 123;
					self.name = new_name
					self.id = id
				)
			}

			t1 := Thing()
			t2 := Thing('Thingus', 456)

			(t1.id, t1.name, t2.id, t2.name)"
			assert_equal [123, "", 456, "Thingus"], out.values
		end

		assert_raises Tape::Missing_Argument do
			out = Drive.interp "
			Thing {
				id,
				name := 'Thingy',

				Self ( new_name, id;
					self.name = new_name
					self.id = id
				)
			}

			t := Thing() # This will raise
			(t.id, t.name)"
			assert_equal [456, "Thingus"], out.values
		end

		assert_raises Tape::Missing_Argument do
			Drive.interp "
	        funk ( it;
				it == true
			)
			funk() # This will raise
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( it;
				it == true
			)
			funk(true), funk(false)
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( it := \"true\";
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( it := \"false\";
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( it := true;
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( funkit := false;
				funkit == true
			)
			funk(true), funk()
			"
		end

		refute_raises Tape::Undeclared_Identifier do
			Drive.interp "
			funk ( it := nil;
				it == true
			)
			funk(true), funk()
			"
		end
	end

	def test_lexer_operator_quote_regression
		# #lex_operator was consuming quotes as symbols, creating invalid operators like ="
		# This caused { b="two" } to fail lexing when = was immediately followed by "
		out = Drive.interp '{ a=1, b="two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Drive.interp '{ a=1, b:"two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values
	end

	def test_nested_type_declaration_shadowing_regression
		# When creating an instance of an inner Type (like Title) inside an outer Type's render function (like Layout), declarations in the inner Type's body (like `title,`) were incorrectly being assigned to the outer Type's instance if it had the same identifier name. This test ensures each Type/Instance has its own namespace.
		out = Drive.interp <<~CODE
		    Outer {
		    	name,

		    	Self ( name;
		    		self.name = name
		    	)

		    	make_inner (;
		    		Inner("inner_value")
		    	)
		    }

		    Inner {
		    	name,

		    	Self ( name;
		    		self.name = name
		    	)

		    	get_name (;
		    		name
		    	)
		    }

		    outer := Outer("outer_value")
		    inner := outer.make_inner()
		    (outer.name, inner.get_name())
		CODE
		assert_equal "outer_value", out.values[0]
		assert_equal "inner_value", out.values[1]
	end

	def test_self_inside_for_loop
		# note: Composing Array with itself allows extending or overriding behavior of Array. Notice how `values` is accessible despite being declared on the original Array type.
		without_prefix = <<~CODE
		    Array | Array {
		        each ( func;
		        	for values
		        		func(it)
		        	end
		        )
		    }
		CODE

		with_prefix = <<~CODE
		    Array | Array {
		        each ( func;
		        	for self.values
		        		func(it)
		        	end
		        )
		    }
		CODE

		out = Drive.interp <<~CODE
		    values := Array([1,2,3])
		    #{without_prefix}
		    values2 := []
		    values.each((it;
		    	values2.push(it)
		    ))
		    values2
		CODE
		assert_equal [1, 2, 3], out.values

		out = Drive.interp <<~CODE
		    values := Array([1,2,3])
		    #{with_prefix}
		    values2 := []
		    values.each((it;
		    	values2.push(it)
		    ))
		    values2
		CODE
		assert_equal [1, 2, 3], out.values
	end

	def test_broken_static_declarations
		refute_raises Tape::Missing_Ruby_Proxy_Declaration do
			Drive.interp <<~TAPE
			    Thing {
			    	Self.abc,
			    	Self.def (;)
			    }

			    Thing.abc
			TAPE
		end

		assert_raises Tape::Database_Not_Set_For_Table_Instance do
			Drive.interp <<~TAPE
			    @load 'tapes/table.tape'

			    Table().find(1)
			TAPE
		end
	end

	def test_commented_closing_brace_causing_infinite_loop
		Drive.interp <<~TAPE
		    Thing {
		    #}
		    }
		TAPE
	end

	def test_accessing_dictionary_keys_with_dot
		# todo: I plan to make the x inside {x} to set x to whatever x happens to evaluate to. When that happens, {x}.x should return 123!
		out = Drive.interp <<~TAPE
		    x := 123
		    {x}.x
		TAPE
		assert_nil out
	end

	# https://github.com/drive-lang/drive/issues/80
	def test_parsing_bug_from_issue_80
		assert_instance_of Tape::String_Expr, Drive.parse("'{'").first
		assert_instance_of Tape::String_Expr, Drive.parse("'('").first
		assert_instance_of Tape::String_Expr, Drive.parse("'['").first
	end

	def test_ranges_with_expression
		assert_instance_of Tape::Range, Drive.interp("x:=1, 0...x")
		assert_instance_of Tape::Range, Drive.interp("x:=1, y:=2, 0...(x + y)")
	end

	# Regression: types loaded via `variable = @load 'file.tape'` were missing enclosing_scope in interp_type
	def test_use_with_variable_can_reference_sibling_types
		out = Drive.interp <<~TAPE
		    lib := @load 'tests/fixtures/use_with_variable_sibling_types.tape'
		    m := lib.Main_Type()
		    m.get_sibling_value()
		TAPE
		assert_equal 42, out
	end

	# Regression: sibling types should also be accessible from within functions (not just type body)
	def test_use_with_variable_can_reference_sibling_types_in_function
		out = Drive.interp <<~TAPE
		    lib := @load 'tests/fixtures/use_with_variable_sibling_types.tape'
		    m := lib.Main_Type()
		    m.create_sibling_in_func()
		TAPE
		assert_equal 42, out
	end

	# Regression: a bare `@load` of a file already loaded into the same scope used to re-run the file's
	# top level a second time (double-incrementing `counter`), and separately, that second @load's own
	# result was silently `nil` instead of what the file actually produced -- both from
	# Interpreter#load_file_into_scope not tracking loads per-scope at all.
	def test_double_load_into_same_scope_only_runs_once
		out = Drive.interp <<~TAPE
		    counter := 0
		    @load 'tests/fixtures/increment_counter.tape'
		    @load 'tests/fixtures/increment_counter.tape'
		TAPE
		# 1, not 2 -- the second @load must not re-run the file (which would increment `counter` again).
		# 1, not nil -- the second @load's own result must still be what the file produced, not nil, even
		# though it didn't actually re-run it.
		assert_equal 1, out
	end

	# Regression: subscript should bind after dot, so a.b[c] parses as (a.b)[c] not a.(b[c])
	def test_subscript_precedence_with_dot_access
		# Parser test: verify AST structure
		ast = Drive.parse('a.b[0]').first
		assert_instance_of Tape::Subscript_Expr, ast
		assert_instance_of Tape::Infix_Expr, ast.receiver
		assert_equal '.', ast.receiver.operator.value

		# Interpreter test: chained dot + subscript read
		out = Drive.interp <<~TAPE
		    Box {
		        items := [10, 20, 30]
		    }
		    b := Box()
		    b.items[1]
		TAPE
		assert_equal 20, out

		# Interpreter test: chained dot + subscript assignment
		out = Drive.interp <<~TAPE
		    Box {
		        data := {x: 1, y: 2}
		    }
		    b := Box()
		    b.data[:z] = 3
		    b.data[:z]
		TAPE
		assert_equal 3, out

		# Deeper chain: a.b.c[d]
		out = Drive.interp <<~TAPE
		    Inner {
		        values := [100, 200]
		    }
		    Outer {
		        inner := Inner()
		    }
		    o := Outer()
		    o.inner.values[0]
		TAPE
		assert_equal 100, out
	end

	# Regression: interp_func_body used to push the single, shared Func object (registered once at declaration time) as the call frame for every invocation. Two calls to the same function overlapping in time (e.g. tree recursion, where a function calls itself twice and combines the results) stomped on each other's param bindings, since they were all declaring onto the same shared scope. Each call now gets a fresh scope, so recursive calls stay isolated.
	def test_tree_recursion_does_not_share_call_frame
		out = Drive.interp <<~TAPE
		    fib ( n;
		        if n <= 1
		            n
		        else
		            fib(n - 1) + fib(n - 2)
		        end
		    )
		    [fib(0), fib(1), fib(2), fib(3), fib(4), fib(5), fib(10)]
		TAPE
		assert_equal [0, 1, 1, 2, 3, 5, 55], out.values
	end

	# Same bug, but through an instance method, which pushes an extra type/instance scope around the (previously) shared Func frame.
	def test_tree_recursion_does_not_share_call_frame_on_instance_method
		out = Drive.interp <<~TAPE
		    Counter {
		        n,

		        Self ( n;
					self.n = n
				)

		        fib (;
		            if n <= 1
		                n
		            else
		                Counter(n - 1).fib() + Counter(n - 2).fib()
		            end
		        )
		    }
		    Counter(10).fib()
		TAPE
		assert_equal 55, out
	end

	# The comment string value was being returned by the Interpreter lol.
	def test_comment_as_last_expression_bug
		out = Drive.interp "
			add ( a, b;
				a + b # sum me
			)
			add(4, 8)"
		refute_kind_of Tape::String_Expr, out
	end

	# `=` used to swallow an adjacent `[` with no space between them, lexing as a single bad operator token `=[` instead of `=` followed by a delimiter.
	def test_operator_does_not_absorb_adjacent_bracket_regression
		out = Drive.lex 'a=[1,2]'
		assert_equal %i(identifier operator delimiter number delimiter number delimiter), out.map(&:type)
		assert_equal '=', out[1].value

		out = Drive.lex 'a]=b'
		assert_equal %i(identifier delimiter operator identifier), out.map(&:type)
		assert_equal '=', out[2].value
	end

	# Operators must never absorb ' " { } ( ) [ ] at all, not just at their start/end.
	def test_operator_does_not_absorb_quotes_or_braces_regression
		out = Drive.lex "5+'hello'"
		assert_equal %i(number operator string), out.map(&:type)
		assert_equal '+', out[1].value

		out = Drive.lex 'x=={y:1}'
		assert_equal '==', out[1].value

		out = Drive.lex '!(b)'
		assert_equal '!', out[0].value
	end

	def test_operator_overload_with_omitted_precedence_falls_back_to_default_regression
		out = Drive.interp '
			@operator <+> @infix ( left, right;
				left + right
			)
			2 <+> 3 + 1
		'
		assert_equal 6, out

		# A real, explicit precedence must still work exactly as before.
		out = Drive.interp '
			@operator <-> @infix 500 ( left, right;
				left - right
			)
			10 <-> 4
		'
		assert_equal 6, out
	end

	def test_bare_return_with_no_expression_yields_nil_regression
		out = Drive.interp '
			foo (;
				return
			)
			foo()
		'
		assert_nil out
	end

	def test_safe_navigation_swallows_missing_member_on_every_receiver_kind_regression
		assert_nil Drive.interp 'Array().?missing'
		assert_nil Drive.interp '[].?missing'
		assert_nil Drive.interp '{}.?missing'
		assert_nil Drive.interp '(1...5).?missing'
		assert_nil Drive.interp 'Array.?uniq'

		# Real member access must still work, and plain `.` must still raise.
		assert_equal 3, Drive.interp('[1,2,3].?length()')
		assert_raises(Tape::Undeclared_Identifier) { Drive.interp '[].missing' }
		assert_raises(Tape::Cannot_Call_Instance_Member_On_Type) { Drive.interp 'Array.uniq' }
	end

	def test_range_dot_access_raises_for_undeclared_members_regression
		assert_raises(Tape::Undeclared_Identifier) { Drive.interp '(1...5).missing' }

		# `.each` must still work through the normal (non-fallback) path.
		out = Drive.interp '
			sum := 0
			for (1...3)
				sum += it
			end
			sum
		'
		assert_equal 6, out
	end

	def test_not_equal_derives_from_custom_equality_overload_regression
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	Self ( x, y;
		    		self.x = x
		    		self.y = y
		    	)

		    	@operator == @infix 500 ( left, right;
		    		left.x == right.x and left.y == right.y
		    	)
		    }

		    a := Point(1, 2)
		    b := Point(1, 2)
		    c := Point(9, 9)
		    (a != b, a != c)
		CODE
		out = Drive.interp src
		assert_equal false, out.values[0]
		assert_equal true, out.values[1]

		# Types with no `==` overload at all are unaffected -- still plain Ruby `!=` on primitives.
		refute Drive.interp '5 != 5'
		assert Drive.interp '5 != 9'
	end

	def test_calling_a_bare_struct_literal_constructs_an_instance_regression
		out = Drive.interp <<~CODE
		    @load 'tapes/struct.tape'
		    s := <name: String, age: Number>('Alice', 30)
		    s.@members.0.value.value
		CODE
		assert_equal 'Alice', out

		# Also works with no matching `Struct` type loaded (bare Tape::Struct fallback).
		refute_raises do
			Drive.interp '<id: Number>(5)'
		end
	end

	def test_string_interpolation_calls_declared_to_s_regression
		out = Drive.interp <<~CODE
		    Thing {
		    	x,
		    	Self ( x; self.x = x )
		    	to_s (; "Thing(`x`)" )
		    }
		    t := Thing(5)
		    "value: `t`"
		CODE
		assert_equal 'value: Thing(5)', out

		# A type with no to_s still falls back to the raw dump -- no change there.
		out = Drive.interp <<~CODE
		    Bare { x, Self ( x; self.x = x ) }
		    b := Bare(5)
		    "value: `b`"
		CODE
		assert_includes out, 'Tape::Instance'

		# Primitives unaffected.
		assert_equal 'n: 8', Drive.interp('x := 5+3
			"n: `x`"')
	end

	def test_stringify_for_display_finds_to_s_on_shorthand_constructed_literals_regression
		interpreter = Drive::Interpreter.new
		result      = interpreter.run '[1, 2, 3]'
		assert_equal '[1, 2, 3]', interpreter.stringify_for_display(result)

		# @puts and bin/drive's `-p` both go through this same path.
		assert_equal '[1, 2, 3]', Drive.interp('[1,2,3].to_s()')
	end

	def test_nested_array_to_s_regression
		interpreter = Drive::Interpreter.new
		result      = interpreter.run '[].push([1,2,3])'
		assert_equal '[[1, 2, 3]]', interpreter.stringify_for_display(result)

		# String had no to_s(;) at all until this fix -- an array of strings would have raised Undeclared_Identifier trying to call .to_s() on each element. Single-quoted (String#to_string), so no longer indistinguishable from Symbols/identifiers in display.
		assert_equal "['a', 'b', 'c']", Drive.interp("['a',\"b\",'c'].to_s()")
	end

	def test_array_of_symbols_to_s_regression
		out = Drive.interp <<~CODE
		    d := {x: 1, y: 2}
		    d.keys().to_s()
		CODE
		assert_equal '[x, y]', out
	end

	def test_dictionary_and_tuple_literals_find_declared_to_s_regression
		assert_equal '{x: 1, y: 2}', Drive.interp('{x: 1, y: 2}.to_s()')
		assert_equal '(1, 2, 3)', Drive.interp('(1, 2, 3).to_s()')
	end

	def test_tuple_values_are_not_the_stale_type_name_regression
		out = Drive.interp <<~CODE
		    t := (1, 2, 3)
		    t.values
		CODE
		assert_equal [1, 2, 3], out
	end

	def test_nil_and_bool_find_declared_to_s_and_truthiness_regression
		assert_equal 'nil', Drive.interp('nil.to_s()')
		assert_equal 'true', Drive.interp('true.to_s()')
		assert_equal 'false', Drive.interp('false.to_s()')
	end

	def test_composition_chain_without_a_body_does_not_hang_the_parser_regression
		refute_raises { Drive.parse 'A & B' }
		refute_raises { Drive.parse 'A | B | C' }
	end

	def test_anonymous_composition_regression
		src = <<~CODE
		    A { x := 1, shared (; 'from A' ) }
		    B { y := 2, shared (; 'from B' ) }

		    union        := (A | B)()
		    intersection := (A & B)()
		    difference   := (A ~ B)()
		    symmetric    := (A ^ B)()

		    (union.x, union.y, union.shared(), intersection.shared(), difference.x, symmetric.x, symmetric.y)
		CODE
		out = Drive.interp src
		assert_equal [1, 2, 'from A', 'from A', 1, 1, 2], out.values

		# Intersection/difference correctly DON'T keep what they're supposed to drop.
		assert_raises(Tape::Undeclared_Identifier) { Drive.interp "#{src}\nintersection.x" }
		assert_raises(Tape::Undeclared_Identifier) { Drive.interp "#{src}\ndifference.shared()" }

		# Comparable with the existing Type comparison operators, same as any named composed type.
		out = Drive.interp <<~CODE
		    Flying { can_fly := true }
		    Swimming { can_swim := true }
		    Duck | Flying | Swimming { name := 'duck' }

		    (Duck =>= (Flying | Swimming), (Flying | Swimming) =>= Duck)
		CODE
		assert_equal [true, false], out.values
	end

	def test_bare_global_keyword_is_the_global_scope
		# `Global` alone evaluates to the global scope object, usable as a value; the newline after it
		# is not swallowed (a bare scope keyword used to corrupt parsing here).
		assert_kind_of Tape::Scope, Drive.interp("x := Global\ny := 1\nx")
		assert_equal 5, Drive.interp("Global\n5")
		assert_kind_of Tape::Scope, Drive.interp('Global')

		# `Global.x := v` declares on the global scope, reachable bare from anywhere after.
		assert_equal 7, Drive.interp("Global.total := 7\ntotal")
	end

	def test_labeled_call_arguments_regression
		src = <<~CODE
		    send_greeting ( to person; person )
		CODE

		# A labeled call matches the declared label at that position.
		assert_equal 42, Drive.interp("#{src}\nsend_greeting(to: 42)")

		# Labels are opt-in at the call site -- a bare positional call still works even though the
		# param declares a label.
		assert_equal 42, Drive.interp("#{src}\nsend_greeting(42)")

		# A label that doesn't match the declared one raises, whether the param has a different label...
		assert_raises(Tape::Argument_Label_Mismatch) do
			Drive.interp("#{src}\nsend_greeting(wrong: 42)")
		end

		# ...or no label at all.
		assert_raises(Tape::Argument_Label_Mismatch) do
			Drive.interp('add ( a, b; a + b )
				add(a: 1, 2)')
		end

		# Labels work through constructors too (`Self(;)` params).
		out = Drive.interp <<~CODE
		    Point {
		    	x,
		    	y,
		    	Self ( at x, at y;
		    		self.x = x
		    		self.y = y
		    	)
		    }
		    p := Point(at: 3, at: 4)
		    (p.x, p.y)
		CODE
		assert_equal [3, 4], out.values

		# Labels compose with defaults normally -- omitting a labeled, defaulted arg still falls back.
		out = Drive.interp <<~CODE
		    greet ( with name := "World"; "Hello, `name`" )
		    (greet(), greet(with: "Drive"))
		CODE
		assert_equal ['Hello, World', 'Hello, Drive'], out.values
	end

	def test_circumfix_elements_do_not_swallow_nil_init_regression
		# The actual bug: an undeclared non-last element used to silently become nil.
		assert_raises(Tape::Undeclared_Identifier) do
			Drive.interp 'foo ( a, b; a + b )
				foo(undeclared_var, 5)'
		end
		assert_raises(Tape::Undeclared_Identifier) do
			Drive.interp 'x := 1
				[undeclared_var, x]'
		end
		assert_raises(Tape::Undeclared_Identifier) do
			Drive.interp 'x := 1
				(undeclared_var, x)'
		end

		# Already-declared identifiers still pass through as plain references, not fresh
		# shadow-declarations, for calls, arrays, and tuples alike.
		out = Drive.interp 'foo ( a, b; a + b )
			x := 5
			y := 8
			foo(x, y)'
		assert_equal 13, out

		out = Drive.interp 'x := 1
			y := 2
			[x, y]'
		assert_equal [1, 2], out.values

		out = Drive.interp 'x := 1
			y := 2
			(x, y)'
		assert_equal [1, 2], out.values
	end

	def test_postfix_unless_and_until_regression
		assert_nil Drive.interp('5 unless true')
		assert_equal 5, Drive.interp('5 unless false')

		out = Drive.interp('x := 0
			x += 1 until x >= 3
			x')
		assert_equal 3, out
	end

	def test_string_literal_matching_a_prefix_symbol_regression
		assert_equal true, Drive.interp('"hi!".end_with?("!")')
		assert_equal 1, Drive.interp("'!'.length")
		assert_equal 1, Drive.interp("'-'.length")
		assert_equal 6, Drive.interp("'return'.length")

		# Real prefix operators are unaffected.
		assert_equal false, Drive.interp('!true')
		assert_equal(-5, Drive.interp('-5'))
	end

	def test_comparing_two_type_objects_does_not_dispatch_instance_operator_overload_regression
		out = Drive.interp <<~CODE
		    @load 'tapes/struct.tape'
		    a := Member('id', nil, String)
		    b := Member('id', nil, String)
		    a == b
		CODE
		assert_equal true, out

		out = Drive.interp <<~CODE
		    @load 'tapes/struct.tape'
		    sa := <name: String, age: Number>('Alice', 30)
		    sb := <name: String, age: Number>('Alice', 30)
		    sc := <name: String, age: Number>('Alice', 99)
		    (sa == sb, sa == sc)
		CODE
		assert_equal [true, false], out.values
	end

	def test_compound_assignment_on_dot_member_target_regression
		# `instance.member += value` used to silently no-op: #interp_compound_infix resolved its assignment target via #scope_for_identifier, which only understands plain Identifier_Exprs -- a dot-target fell through to `stack.last` and declared a bogus `nil`-named identifier there instead of touching the actual member. Found via demos/aoc/2015/3b.tape computing the wrong answer (Vec2 members mutated with `+=` inside nested if/elif never actually moved).
		out = Drive.interp <<~CODE
		    Vec2 {
		        x,
		        y,
		        Self ( x, y;
		            self.x = x
		            self.y = y
		        )
		    }
		    v := Vec2(0, 0)
		    v.y += 1
		    v.y += 1
		    v.x -= 1
		    (v.x, v.y)
		CODE
		assert_equal [-1, 2], out.values
	end

	def test_tuple_dot_index_out_of_bounds_regression
		# `.N`/`.N.M...` dot-index access silently returned nil past the collection's length, and silently truncated a non-integer index -- e.g. `.0.1` lexes as the single float 0.1, which Ruby's own Array#[] truncates to index 0, so `((), true).0.1`/`.0.2`/`.0.3`... all silently returned the same first element (a Tuple) instead of erroring past the actual length.
		assert_raises Tape::Invalid_Array_Index do
			Drive.interp '((), true).0.1'
		end

		assert_raises Tape::Invalid_Array_Index do
			Drive.interp '(1, 2, 3).5'
		end

		assert_equal 2, Drive.interp('(1, 2, 3).1')
		assert_equal 3, Drive.interp('(1, 2, 3).-1')
	end

	def test_spaceship_on_custom_instance_with_no_overload_raises_regression
		# `<=>` on a custom Instance with no @operator overload used to fall through to Ruby's own Kernel#<=> (every Object gets a trivial, identity-based default), silently returning nil instead of raising -- respond_to?(:<=>) can't tell the trivial default apart from a real one.
		assert_raises Tape::Undeclared_Infix_Operator do
			Drive.interp <<~CODE
			    Point { x, Self ( x; self.x = x ) }
			    Point(1) <=> Point(2)
			CODE
		end

		# Numbers/Strings still work (they decay to plain Ruby values with a real <=>).
		assert_equal 1, Drive.interp('5 <=> 3')

		out = Drive.interp <<~CODE
		    Point { x, Self ( x; self.x = x )
		        @operator <=> @infix ( left, right; left.x <=> right.x )
		    }
		    Point(1) <=> Point(2)
		CODE
		assert_equal -1, out
	end

	def test_struct_include_uses_predicate_correctly_regression
		# `Struct#include?` called `Array#include?` (equality-only, `it == item`) with a predicate function instead of `Array#any?` (which actually invokes it) -- always silently returned false. No test exercised it until now.
		assert_equal true, Drive.interp("<name: String, age: Number>.include?('name')")
		assert_equal false, Drive.interp("<name: String, age: Number>.include?('missing')")
	end

	def test_for_loop_closures_capture_own_iteration_regression
		# `for` used to allocate one Scope for the whole loop and mutate it in place each iteration -- a closure built inside the body (e.g. a Statement literal capturing `it`) saw whatever the final iteration left behind, not its own value, once called later. Repro: all three Statements below used to return 3 instead of 1, 2, 3.
		out = Drive.interp <<~CODE
		    stmts := []
		    for [1, 2, 3]
		        stmts.push(`it`)
		    end
		    results := []
		    for stmts
		        results.push(it())
		    end
		    results
		CODE
		assert_equal [1, 2, 3], out.values
	end

	def test_array_string_dictionary_proxies_wrap_their_results_regression
		# `Array#first`/`#last`/`#slice`/`#reverse`/`#sort`/`#uniq`, `String#split`/`#chars`, `Dictionary#keys`/`#values`/`#merge`, and `for x by n` stride chunks all returned a raw Ruby Array/Hash instead of Tape::Array/Tape::Dictionary -- dot-index access (`it.0`) worked by accident via #maybe_instance, but `==` against a literal silently failed. No test exercised any of these at the value level until now.
		out = Drive.interp <<~CODE
		    pairs := []
		    for ['red', 'blue', 'green', 'yellow'] by 2
		        pairs.push(it)
		    end
		    pairs
		CODE
		assert_equal [['red', 'blue'], ['green', 'yellow']], out.values.map(&:values)

		assert_equal [1, 2], Drive.interp("[1, 2, 3, 4].first(2)").values
		assert_equal [3, 2, 1], Drive.interp("[1, 2, 3].reverse()").values
		assert_equal ['he', '', 'o'], Drive.interp("'hello'.split('l')").values
		assert_equal [:x, :y], Drive.interp("{x: 1, y: 2}.keys()").values
		assert_equal({ x: 1, y: 2 }, Drive.interp("{x: 1}.merge({y: 2})").hash)
	end

	def test_member_to_s_on_unnamed_type_only_member_does_not_crash_regression
		# `<String, Number>` (a schema-only struct with bare, unnamed type members) has `value == type` for its String member -- the bare String Type object itself, not an actual instance. `Member#to_s` unconditionally called `.to_string()` on it whenever `type.?name == 'String'`, assuming `value` was a real String instance -- raised `Cannot_Call_Instance_Member_On_Type` instead, since `to_string` is an instance-only method. `.?to_string()` (nil-safe) fixes it.
		refute_raises Tape::Cannot_Call_Instance_Member_On_Type do
			Drive.interp("<String, Number>.@members.0.to_s()")
		end
	end

	def test_capitalized_identifier_comparison_does_not_get_parsed_as_a_tagged_type_reference_regression
		# `X < Y` (X/Y capitalized variables, not types) looks identical up to `TYPE_IDENTIFIER '<'` to `Ident <...>` -- #begin_expression always committed to #parse_struct on sight of that shape, which then ran out of tokens hunting for a `>` that was never coming (Tape::Out_Of_Tokens) instead of falling through to an ordinary `<` comparison. #try_parse_struct now actually attempts the real parse and rewinds on any syntax error instead of guessing via lookahead.
		assert_equal true, Drive.interp(<<~CODE)
		    X := 1
		    Y := 2
		    X < Y
		CODE

		# A capitalized comparison as the last expression in a block, with no trailing newline before the closing `}`, took the same wrong path for a different reason (a naive lookahead bounded only by newline would've kept scanning past `}` too).
		assert_equal true, Drive.interp(<<~CODE)
		    compute ( x, y; x < y)
		    compute(1, 2)
		CODE

		# A real tagged-type declaration/reference on one line still works, comma-separated members included -- confirms the fix didn't just move the false negative onto legitimate `Abc\<Number>` usage.
		assert_equal true, Drive.interp(<<~CODE)
		    Dictionary_Like\\<String, Number> {}
		    z := Dictionary_Like\\<String, Number>()
		    z.tag.@types.length() == 2
		CODE

		# A struct member's own default value can legitimately contain delimiters (`(`/`)`, `[`/`]`, nested `{`/`}`) before the real closing `>` -- must not be mistaken for the statement's own boundary.
		assert_equal true, Drive.interp(<<~CODE)
		    mk (; 5 )
		    Abc\\<id := mk(), items := [1,2], dict := {x: 1}> {}
		    z := Abc\\<mk(), [1,2], {x:1}>()
		    z =/= nil
		CODE
	end

	def test_capitalized_function_param_raises_a_real_error_instead_of_crashing_regression
		# A bare Capitalized/UPPERCASE param (`f ( ABC; ABC )`) parses like a signature-literal's bare type (`param.type` set, `param.name` left nil, see #parse_func -- a real function param always starts lowercase, so a bare Capitalized token there can only mean a signature literal, e.g. `{Number -> String;}`) rather than a named param. #interp_func_body assumed every param has `.name` set, raising a raw NoMethodError (`undefined method 'value' for nil`) the first time it read `param.name.value`, instead of a real Drive error.
		assert_raises Tape::Invalid_Parameter_Name do
			Drive.interp <<~CODE
			    f ( ABC; ABC )
			    x := 1
			    f(x)
			CODE
		end

		# A genuine signature literal (never called, just described/assigned) is unaffected.
		refute_raises Tape::Invalid_Parameter_Name do
			Drive.interp '(Number -> String;)'
		end
	end

	def test_context_stringifies_as_a_struct_for_display_regression
		# `@` is the Context bare-named struct (a Tape::Instance) whose `to_s` member is synthesized to a
		# bodyless stand-in. #stringify_for_display used to run that empty body directly, so `@puts @` and
		# `` `@` `` interpolation printed blank. Now display renders it the same shape every other struct
		# prints as -- `Name <member: Type = value, ...>` over every member; an explicit `@.to_s()` call
		# still goes through the stand-in and gives `@<name>`.
		dump = Drive.interp('"`@`"')
		assert_match(/\AContext <name: String = 'Global', /, dump)
		assert_includes dump, "root_path: String = '"
		assert_includes dump, 'to_s: ( -> String;)'
		assert_includes dump, 'puts: (Args -> Args;)'

		assert_equal '@Global', Drive.interp('@.to_s()')

		# Only the members declared in tapes/context.tape show -- not the short-alias function stand-ins
		# (`add_readable`, `readable`, ...) that #fill_context also puts on the instance.
		refute_includes dump, 'readable: Any'
		refute_includes dump, 'add_readable:'

		# `@.types` is declared `Array\String`; a plain scope's composed types go in as an Array, not a
		# Set (which mismatched the member's own type).
		assert_includes dump, 'types: Array'
		refute_includes dump, 'types: Array = Set{'

		# Inside a Type body, `@` is that Type's own context.
		assert_match(/\AContext <name: String = 'Foo', /, Drive.interp(<<~CODE))
		    Foo { nm := 'f'  dump := "`@`" }
		    Foo().dump
		CODE

		# A directly constructed `Context()` (a Struct composing `Context`, not the Ruby class) renders
		# too, rather than crashing `Struct#to_s` on its func-signature members.
		assert_match(/\AContext <name: String, /, Drive.interp('"`Context()`"'))
		assert_match(/name: String = 'x'/, Drive.interp(%q("`Context(name := 'x')`")))
	end

	def test_struct_with_a_func_signature_member_stringifies_regression
		# A `name: (sig)` struct member's `type` is a raw Func_Signature, not a Scope. Member#to_s did
		# `type.?@display_name` on it -- but `.?` didn't catch Invalid_Dot_Infix_Left_Operand (raised for
		# a non-Scope receiver), so `@puts` / interpolation of any such struct crashed. Now `.?` yields
		# nil there and Member#to_s falls back to interpolating the signature itself.
		assert_equal '<fn: ( -> String;), x: Number = 5>', Drive.interp(<<~CODE)
		    S <fn: (-> String;), x: Number>
		    "`S(nil, 5)`"
		CODE

		assert_equal '<fn: ( -> String;), x: Number>', Drive.interp(<<~CODE)
		    S <fn: (-> String;), x: Number>
		    "`S`"
		CODE
	end

	def test_bare_dot_at_on_a_receiver_resolves_that_receivers_context_regression
		# `X.@` (bare `@`, no member) runs #context_for mid dot-access, when `stack` is narrowed to just
		# the receiver -- `find_in_stack 'Context'` couldn't see the stdlib `Context` declaration there,
		# so the built context had no data members and wasn't even `=== Context`. Now it falls back to
		# `global['Context']`.
		assert_equal true, Drive.interp(<<~CODE)
		    Duck { nm := 1 }
		    c := Duck.@
		    c === Context and c.name == 'Duck'
		CODE
	end

	def test_nil_satisfies_any_type_contract_regression
		# `nil` is the universal unset value every typed slot starts as (`x: String` -> nil, `T()` with
		# no args -> nil members), so re-assigning nil to a typed member/var must be allowed too -- it
		# used to raise Type_Contract_Violation ("expected String, got unknown").
		assert_nil Drive.interp(<<~CODE)
		    T <name: String>
		    t := T()
		    t.name = nil
		    t.name
		CODE

		assert_nil Drive.interp("x: String = 'hi'\nx = nil\nx")

		# A genuine mismatch still raises.
		assert_raises(Tape::Type_Contract_Violation) { Drive.interp("x: String = 'hi'\nx = 123") }
	end
end
