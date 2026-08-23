require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class Regression_Test < Base_Test
	def test_greater_equals_regression
		out = Lost.interp '2+1 >= 1'
		assert out
	end

	def test_precedence_operation_regression
		src = Lost.interp '1 + 2 / 3 - 4 * 5'
		ref = Lost.interp '(1 + (2 / 3)) - (4 * 5)'
		assert_equal ref, src
		assert_equal -19, src
	end

	def test_infixes_regression
		Lost::COMPOUND_OPERATORS.each do |operator|
			code = "left #{operator} right"
			out  = Lost.parse(code)
			assert_kind_of Lost::Infix_Expr, out.first
		end
	end

	def test_dot_slashes_regression
		ds  = Lost.parse './abc'
		dds = Lost.parse '../def'
		assert_kind_of Lost::Identifier_Expr, ds.first
		assert_kind_of Lost::Identifier_Expr, dds.first

		assert_kind_of Lost::Identifier_Expr, ds.last
		assert_equal './', ds.last.scope_operator.value
		assert_equal 'abc', ds.last.value
	end

	def test_dot_slash_outside_instance_raises_regression
		# Was silently shadowed by a second, unrelated method also named test_dot_slash_regression (see further down) -- Ruby just keeps the later definition, so this one never actually ran, and its assertion (`123`) was stale/wrong even before that: `./x := 123` at top level has always raised, not returned 123.
		assert_raises Lost::Cannot_Use_Instance_Scope_Operator_Outside_Instance do
			Lost.interp './x := 123'
		end
	end

	def test_look_up_tilde_slash_without_dot_slash_regression
		out = Lost.interp '~/x := 456
		x'
		assert_equal 456, out
	end

	def test_look_up_tilde_slash_with_dot_slash_regression
		out = Lost.interp '~/y := 789
		~/y'
		assert_equal 789, out
	end

	def test_dot_slash_within_infix_regression
		out = Lost.parse './x? := 123'
		assert_kind_of Lost::Infix_Expr, out.first
		assert_equal ':=', out.first.operator.value
		assert_equal 'x?', out.first.left.value
		assert_kind_of Lost::Identifier_Expr, out.first.left
		assert_equal './', out.first.left.scope_operator.value
	end

	def test_scope_operators_regression
		out = Lost.parse './this_instance'
		assert_kind_of Lost::Identifier_Expr, out.first
		assert_equal 1, out.count

		out = Lost.parse '../class_scope'
		assert_kind_of Lost::Identifier_Expr, out.first
		assert_equal 1, out.count
	end

	def test_assigning_false_value_regression
		out = Lost.interp 'how := false
		how'
		assert_equal false, out
	end

	def test_identifier_lookup_regression
		out = Lost.interp 'Lost {}, Lost'
		assert_instance_of Type, out
	end

	def test_instance_does_not_have_new_function_regression
		out = Lost.interp '
		Atom {
			new (;)
		}
		a := Atom()
		b := Atom.new()
		(a, b)'
		refute out.values.first.has? :new
		refute out.values.last.has? :new
	end

	def test_dot_new_initializer_regression
		out = Lost.interp 'Number {
			numerator := 8

			new ( num;
				self.numerator = num
			)
		}
		x := Number.new(15)
		x.numerator'
		assert_equal 15, out
	end

	def test_calling_member_functions
		out = Lost.interp '
		Number {
			numerator := -100

			new ( num;
				self.numerator = num
			)
		}
		x := Number(4)
		x.numerator'
		assert_equal 4, out
	end

	def test_dot_slash_regression
		out = Lost.interp '
		Box {
			kind := "NONE"

			new ( new_kind;
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
		assert_instance_of Lost::Instance, out.values[0]
		assert_equal "Big-box", out.values[1]
		assert_equal "Small-box", out.values[3]
	end

	def test_identifier_lookup_regression
		out = Lost.interp "x := 123
		funk (;
			~/x + 2
		)
		funk()"
		assert_equal 125, out

		out = Lost.interp "y := 0
		add ( amount_to_add := 1;
			~/y + amount_to_add
		)
		(a := add(4))

		(a, add(a * 2))"
		assert_equal [4, 8], out.values

		out = Lost.interp "y := 0
		add ( amount_to_add := 1;
			y += amount_to_add
		)
		a := add(4)

		(y, a)"
		assert_equal [4, 4], out.values

		refute_raises Lost::Undeclared_Identifier do
			out = Lost.interp "
			Thing {
				id,
				name := 'Thingy'

				new ( new_name := '', id := 123;
					self.name = new_name
					self.id = id
				)
			}

			t1 := Thing()
			t2 := Thing('Thingus', 456)

			(t1.id, t1.name, t2.id, t2.name)"
			assert_equal [123, "", 456, "Thingus"], out.values
		end

		assert_raises Lost::Missing_Argument do
			out = Lost.interp "
			Thing {
				id,
				name := 'Thingy',

				new ( new_name, id;
					self.name = new_name
					self.id = id
				)
			}

			t := Thing() # This will raise
			(t.id, t.name)"
			assert_equal [456, "Thingus"], out.values
		end

		assert_raises Lost::Missing_Argument do
			Lost.interp "
	        funk ( it;
				it == true
			)
			funk() # This will raise
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
			funk ( it;
				it == true
			)
			funk(true), funk(false)
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
			funk ( it := \"true\";
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
			funk ( it := \"false\";
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
			funk ( it := true;
				it == true
			)
			funk(true), funk()
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
			funk ( funkit := false;
				funkit == true
			)
			funk(true), funk()
			"
		end

		refute_raises Lost::Undeclared_Identifier do
			Lost.interp "
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
		out = Lost.interp '{ a=1, b="two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values

		out = Lost.interp '{ a=1, b:"two", c: :three }.values()'
		assert_equal [1, "two", :three], out.values
	end

	def test_nested_type_declaration_shadowing_regression
		# When creating an instance of an inner Type (like Title) inside an outer Type's render function (like Layout), declarations in the inner Type's body (like `title,`) were incorrectly being assigned to the outer Type's instance if it had the same identifier name. This test ensures each Type/Instance has its own namespace.
		out = Lost.interp <<~CODE
		    Outer {
		    	name,

		    	new ( name;
		    		self.name = name
		    	)

		    	make_inner (;
		    		Inner("inner_value")
		    	)
		    }

		    Inner {
		    	name,

		    	new ( name;
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

		out = Lost.interp <<~CODE
		    values := Array([1,2,3])
		    #{without_prefix}
		    values2 := []
		    values.each((it;
		    	values2.push(it)
		    ))
		    values2
		CODE
		assert_equal [1, 2, 3], out.values

		out = Lost.interp <<~CODE
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
		refute_raises Lost::Missing_Ruby_Proxy_Declaration do
			Lost.interp <<~TAPE
			    Thing {
			    	Self.abc,
			    	Self.def (;)
			    }

			    Thing.abc
			TAPE
		end

		assert_raises Lost::Database_Not_Set_For_Table_Instance do
			Lost.interp <<~TAPE
			    @load 'lost/table.tape'

			    Table.find(1)
			TAPE
		end
	end

	def test_commented_closing_brace_causing_infinite_loop
		Lost.interp <<~TAPE
		    Thing {
		    #}
		    }
		TAPE
	end

	def test_accessing_dictionary_keys_with_dot
		# todo: I plan to make the x inside {x} to set x to whatever x happens to evaluate to. When that happens, {x}.x should return 123!
		out = Lost.interp <<~TAPE
		    x := 123
		    {x}.x
		TAPE
		assert_nil out
	end

	# https://github.com/figgleforth/lost-lang/issues/80
	def test_parsing_bug_from_issue_80
		assert_instance_of Lost::String_Expr, Lost.parse("'{'").first
		assert_instance_of Lost::String_Expr, Lost.parse("'('").first
		assert_instance_of Lost::String_Expr, Lost.parse("'['").first
	end

	def test_ranges_with_expression
		assert_instance_of Lost::Range, Lost.interp("x:=1, 0...x")
		assert_instance_of Lost::Range, Lost.interp("x:=1, y:=2, 0...(x + y)")
	end

	# Regression: types loaded via `variable = @load 'file.tape'` were missing enclosing_scope in interp_type
	def test_use_with_variable_can_reference_sibling_types
		out = Lost.interp <<~TAPE
		    lib := @load 'test/fixtures/use_with_variable_sibling_types.tape'
		    m := lib.Main_Type()
		    m.get_sibling_value()
		TAPE
		assert_equal 42, out
	end

	# Regression: sibling types should also be accessible from within functions (not just type body)
	def test_use_with_variable_can_reference_sibling_types_in_function
		out = Lost.interp <<~TAPE
		    lib := @load 'test/fixtures/use_with_variable_sibling_types.tape'
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
		out = Lost.interp <<~TAPE
		    counter := 0
		    @load 'test/fixtures/increment_counter.tape'
		    @load 'test/fixtures/increment_counter.tape'
		TAPE
		# 1, not 2 -- the second @load must not re-run the file (which would increment `counter` again).
		# 1, not nil -- the second @load's own result must still be what the file produced, not nil, even
		# though it didn't actually re-run it.
		assert_equal 1, out
	end

	# Regression: subscript should bind after dot, so a.b[c] parses as (a.b)[c] not a.(b[c])
	def test_subscript_precedence_with_dot_access
		# Parser test: verify AST structure
		ast = Lost.parse('a.b[0]').first
		assert_instance_of Lost::Subscript_Expr, ast
		assert_instance_of Lost::Infix_Expr, ast.receiver
		assert_equal '.', ast.receiver.operator.value

		# Interpreter test: chained dot + subscript read
		out = Lost.interp <<~TAPE
		    Box {
		        items := [10, 20, 30]
		    }
		    b := Box()
		    b.items[1]
		TAPE
		assert_equal 20, out

		# Interpreter test: chained dot + subscript assignment
		out = Lost.interp <<~TAPE
		    Box {
		        data := {x: 1, y: 2}
		    }
		    b := Box()
		    b.data[:z] = 3
		    b.data[:z]
		TAPE
		assert_equal 3, out

		# Deeper chain: a.b.c[d]
		out = Lost.interp <<~TAPE
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
		out = Lost.interp <<~TAPE
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
		out = Lost.interp <<~TAPE
		    Counter {
		        n,

		        new ( n;
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
		out = Lost.interp "
			add ( a, b;
				a + b # sum me
			)
			add(4, 8)"
		refute_kind_of Lost::String_Expr, out
	end

	# `=` used to swallow an adjacent `[` with no space between them, lexing as a single bad operator token `=[` instead of `=` followed by a delimiter.
	def test_operator_does_not_absorb_adjacent_bracket_regression
		out = Lost.lex 'a=[1,2]'
		assert_equal %i(identifier operator delimiter number delimiter number delimiter), out.map(&:type)
		assert_equal '=', out[1].value

		out = Lost.lex 'a]=b'
		assert_equal %i(identifier delimiter operator identifier), out.map(&:type)
		assert_equal '=', out[2].value
	end

	# Operators must never absorb ' " { } ( ) [ ] at all, not just at their start/end.
	def test_operator_does_not_absorb_quotes_or_braces_regression
		out = Lost.lex "5+'hello'"
		assert_equal %i(number operator string), out.map(&:type)
		assert_equal '+', out[1].value

		out = Lost.lex 'x=={y:1}'
		assert_equal '==', out[1].value

		out = Lost.lex '!(b)'
		assert_equal '!', out[0].value
	end

	def test_operator_overload_with_omitted_precedence_falls_back_to_default_regression
		out = Lost.interp '
			@operator <+> @infix ( left, right;
				left + right
			)
			2 <+> 3 + 1
		'
		assert_equal 6, out

		# A real, explicit precedence must still work exactly as before.
		out = Lost.interp '
			@operator <-> @infix 500 ( left, right;
				left - right
			)
			10 <-> 4
		'
		assert_equal 6, out
	end

	def test_bare_return_with_no_expression_yields_nil_regression
		out = Lost.interp '
			foo (;
				return
			)
			foo()
		'
		assert_nil out
	end

	def test_safe_navigation_swallows_missing_member_on_every_receiver_kind_regression
		assert_nil Lost.interp 'Array().?missing'
		assert_nil Lost.interp '[].?missing'
		assert_nil Lost.interp '{}.?missing'
		assert_nil Lost.interp '(1...5).?missing'
		assert_nil Lost.interp 'Array.?uniq'

		# Real member access must still work, and plain `.` must still raise.
		assert_equal 3, Lost.interp('[1,2,3].?length()')
		assert_raises(Lost::Undeclared_Identifier) { Lost.interp '[].missing' }
		assert_raises(Lost::Cannot_Call_Instance_Member_On_Type) { Lost.interp 'Array.uniq' }
	end

	def test_range_dot_access_raises_for_undeclared_members_regression
		assert_raises(Lost::Undeclared_Identifier) { Lost.interp '(1...5).missing' }

		# `.each` must still work through the normal (non-fallback) path.
		out = Lost.interp '
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

		    	new ( x, y;
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
		out = Lost.interp src
		assert_equal false, out.values[0]
		assert_equal true, out.values[1]

		# Types with no `==` overload at all are unaffected -- still plain Ruby `!=` on primitives.
		refute Lost.interp '5 != 5'
		assert Lost.interp '5 != 9'
	end

	def test_calling_a_bare_struct_literal_constructs_an_instance_regression
		out = Lost.interp <<~CODE
		    @load 'lost/struct.tape'
		    s := <name: String, age: Number>('Alice', 30)
		    s.members.0.value.value
		CODE
		assert_equal 'Alice', out

		# Also works with no matching `Struct` type loaded (bare Lost::Struct fallback).
		refute_raises do
			Lost.interp '<id: Number>(5)'
		end
	end

	def test_string_interpolation_calls_declared_to_s_regression
		out = Lost.interp <<~CODE
		    Thing {
		    	x,
		    	new ( x; self.x = x )
		    	to_s (; "Thing(`x`)" )
		    }
		    t := Thing(5)
		    "value: `t`"
		CODE
		assert_equal 'value: Thing(5)', out

		# A type with no to_s still falls back to the raw dump -- no change there.
		out = Lost.interp <<~CODE
		    Bare { x, new ( x; self.x = x ) }
		    b := Bare(5)
		    "value: `b`"
		CODE
		assert_includes out, 'Lost::Instance'

		# Primitives unaffected.
		assert_equal 'n: 8', Lost.interp('x := 5+3
			"n: `x`"')
	end

	def test_stringify_for_display_finds_to_s_on_shorthand_constructed_literals_regression
		interpreter = Lost::Interpreter.new
		result      = interpreter.run '[1, 2, 3]'
		assert_equal '[1, 2, 3]', interpreter.stringify_for_display(result)

		# @puts and bin/lost's `-p` both go through this same path.
		assert_equal '[1, 2, 3]', Lost.interp('[1,2,3].to_s()')
	end

	def test_nested_array_to_s_regression
		interpreter = Lost::Interpreter.new
		result      = interpreter.run '[].push([1,2,3])'
		assert_equal '[[1, 2, 3]]', interpreter.stringify_for_display(result)

		# String had no to_s(;) at all until this fix -- an array of strings would have raised Undeclared_Identifier trying to call .to_s() on each element. Always double-quoted (not matching each literal's own quote char -- Array elements aren't wrapped with quotation_style at construction, see #interp_circumfix's `[]` case), so no longer indistinguishable from Symbols/identifiers in display.
		assert_equal '["a", "b", "c"]', Lost.interp("['a',\"b\",'c'].to_s()")
	end

	def test_array_of_symbols_to_s_regression
		out = Lost.interp <<~CODE
		    d := {x: 1, y: 2}
		    d.keys().to_s()
		CODE
		assert_equal '[x, y]', out
	end

	def test_dictionary_and_tuple_literals_find_declared_to_s_regression
		assert_equal '{x: 1, y: 2}', Lost.interp('{x: 1, y: 2}.to_s()')
		assert_equal '(1, 2, 3)', Lost.interp('(1, 2, 3).to_s()')
	end

	def test_tuple_values_are_not_the_stale_type_name_regression
		out = Lost.interp <<~CODE
		    t := (1, 2, 3)
		    t.values
		CODE
		assert_equal [1, 2, 3], out
	end

	def test_nil_and_bool_find_declared_to_s_and_truthiness_regression
		assert_equal 'nil', Lost.interp('nil.to_s()')
		assert_equal 'true', Lost.interp('true.to_s()')
		assert_equal 'false', Lost.interp('false.to_s()')
	end

	def test_composition_chain_without_a_body_does_not_hang_the_parser_regression
		refute_raises { Lost.parse 'A & B' }
		refute_raises { Lost.parse 'A | B | C' }
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
		out = Lost.interp src
		assert_equal [1, 2, 'from A', 'from A', 1, 1, 2], out.values

		# Intersection/difference correctly DON'T keep what they're supposed to drop.
		assert_raises(Lost::Undeclared_Identifier) { Lost.interp "#{src}\nintersection.x" }
		assert_raises(Lost::Undeclared_Identifier) { Lost.interp "#{src}\ndifference.shared()" }

		# Comparable with the existing Type comparison operators, same as any named composed type.
		out = Lost.interp <<~CODE
		    Flying { can_fly := true }
		    Swimming { can_swim := true }
		    Duck | Flying | Swimming { name := 'duck' }

		    (Duck =>= (Flying | Swimming), (Flying | Swimming) =>= Duck)
		CODE
		assert_equal [true, false], out.values
	end

	def test_bare_scope_operator_does_not_corrupt_parsing_regression
		%w(./ ../ ~/).each do |op|
			# Not the last thing in the program -- this used to crash.
			out = Lost.interp "x := #{op}\ny := 1\nx"
			assert_nil out

			# Bare, unassigned, not the last statement -- this used to silently vanish (harmless in
			# itself, but confirms the newline it used to eat is no longer swallowed).
			out = Lost.interp "#{op}\n5"
			assert_equal 5, out

			# Still fine as the literal last token in the file (the case that always worked).
			assert_nil Lost.interp(op)
		end
	end

	def test_labeled_call_arguments_regression
		src = <<~CODE
		    send_greeting ( to person; person )
		CODE

		# A labeled call matches the declared label at that position.
		assert_equal 42, Lost.interp("#{src}\nsend_greeting(to: 42)")

		# Labels are opt-in at the call site -- a bare positional call still works even though the
		# param declares a label.
		assert_equal 42, Lost.interp("#{src}\nsend_greeting(42)")

		# A label that doesn't match the declared one raises, whether the param has a different label...
		assert_raises(Lost::Argument_Label_Mismatch) do
			Lost.interp("#{src}\nsend_greeting(wrong: 42)")
		end

		# ...or no label at all.
		assert_raises(Lost::Argument_Label_Mismatch) do
			Lost.interp('add ( a, b; a + b )
				add(a: 1, 2)')
		end

		# Labels work through constructors too (`new(;)` params).
		out = Lost.interp <<~CODE
		    Point {
		    	x,
		    	y,
		    	new ( at x, at y;
		    		self.x = x
		    		self.y = y
		    	)
		    }
		    p := Point(at: 3, at: 4)
		    (p.x, p.y)
		CODE
		assert_equal [3, 4], out.values

		# Labels compose with defaults normally -- omitting a labeled, defaulted arg still falls back.
		out = Lost.interp <<~CODE
		    greet ( with name := "World"; "Hello, `name`" )
		    (greet(), greet(with: "Lost"))
		CODE
		assert_equal ['Hello, World', 'Hello, Lost'], out.values
	end

	def test_circumfix_elements_do_not_swallow_nil_init_regression
		# The actual bug: an undeclared non-last element used to silently become nil.
		assert_raises(Lost::Undeclared_Identifier) do
			Lost.interp 'foo ( a, b; a + b )
				foo(undeclared_var, 5)'
		end
		assert_raises(Lost::Undeclared_Identifier) do
			Lost.interp 'x := 1
				[undeclared_var, x]'
		end
		assert_raises(Lost::Undeclared_Identifier) do
			Lost.interp 'x := 1
				(undeclared_var, x)'
		end

		# Already-declared identifiers still pass through as plain references, not fresh
		# shadow-declarations, for calls, arrays, and tuples alike.
		out = Lost.interp 'foo ( a, b; a + b )
			x := 5
			y := 8
			foo(x, y)'
		assert_equal 13, out

		out = Lost.interp 'x := 1
			y := 2
			[x, y]'
		assert_equal [1, 2], out.values

		out = Lost.interp 'x := 1
			y := 2
			(x, y)'
		assert_equal [1, 2], out.values
	end

	def test_postfix_unless_and_until_regression
		assert_nil Lost.interp('5 unless true')
		assert_equal 5, Lost.interp('5 unless false')

		out = Lost.interp('x := 0
			x += 1 until x >= 3
			x')
		assert_equal 3, out
	end

	def test_string_literal_matching_a_prefix_symbol_regression
		assert_equal true, Lost.interp('"hi!".end_with?("!")')
		assert_equal 1, Lost.interp("'!'.length")
		assert_equal 1, Lost.interp("'-'.length")
		assert_equal 6, Lost.interp("'return'.length")

		# Real prefix operators are unaffected.
		assert_equal false, Lost.interp('!true')
		assert_equal(-5, Lost.interp('-5'))
	end

	def test_comparing_two_type_objects_does_not_dispatch_instance_operator_overload_regression
		out = Lost.interp <<~CODE
		    @load 'lost/struct.tape'
		    a := Member('id', nil, String)
		    b := Member('id', nil, String)
		    a == b
		CODE
		assert_equal true, out

		out = Lost.interp <<~CODE
		    @load 'lost/struct.tape'
		    sa := <name: String, age: Number>('Alice', 30)
		    sb := <name: String, age: Number>('Alice', 30)
		    sc := <name: String, age: Number>('Alice', 99)
		    (sa == sb, sa == sc)
		CODE
		assert_equal [true, false], out.values
	end

	def test_compound_assignment_on_dot_member_target_regression
		# `instance.member += value` used to silently no-op: #interp_compound_infix resolved its assignment target via #scope_for_identifier, which only understands plain Identifier_Exprs -- a dot-target fell through to `stack.last` and declared a bogus `nil`-named identifier there instead of touching the actual member. Found via examples/aoc/2015/03/part2.tape computing the wrong answer (Vec2 members mutated with `+=` inside nested if/elif never actually moved).
		out = Lost.interp <<~CODE
		    Vec2 {
		        x,
		        y,
		        new ( x, y;
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
		assert_raises Lost::Invalid_Array_Index do
			Lost.interp '((), true).0.1'
		end

		assert_raises Lost::Invalid_Array_Index do
			Lost.interp '(1, 2, 3).5'
		end

		assert_equal 2, Lost.interp('(1, 2, 3).1')
		assert_equal 3, Lost.interp('(1, 2, 3).-1')
	end

	def test_spaceship_on_custom_instance_with_no_overload_raises_regression
		# `<=>` on a custom Instance with no @operator overload used to fall through to Ruby's own Kernel#<=> (every Object gets a trivial, identity-based default), silently returning nil instead of raising -- respond_to?(:<=>) can't tell the trivial default apart from a real one.
		assert_raises Lost::Undeclared_Infix_Operator do
			Lost.interp <<~CODE
			    Point { x, new ( x; self.x = x ) }
			    Point(1) <=> Point(2)
			CODE
		end

		# Numbers/Strings still work (they decay to plain Ruby values with a real <=>).
		assert_equal 1, Lost.interp('5 <=> 3')

		out = Lost.interp <<~CODE
		    Point { x, new ( x; self.x = x )
		        @operator <=> @infix ( left, right; left.x <=> right.x )
		    }
		    Point(1) <=> Point(2)
		CODE
		assert_equal -1, out
	end

	def test_struct_include_uses_predicate_correctly_regression
		# `Struct#include?` called `Array#include?` (equality-only, `it == item`) with a predicate function instead of `Array#any?` (which actually invokes it) -- always silently returned false. No test exercised it until now.
		assert_equal true, Lost.interp("<name: String, age: Number>.include?('name')")
		assert_equal false, Lost.interp("<name: String, age: Number>.include?('missing')")
	end

	def test_for_loop_closures_capture_own_iteration_regression
		# `for` used to allocate one Scope for the whole loop and mutate it in place each iteration -- a closure built inside the body (e.g. a Statement literal capturing `it`) saw whatever the final iteration left behind, not its own value, once called later. Repro: all three Statements below used to return 3 instead of 1, 2, 3.
		out = Lost.interp <<~CODE
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
		# `Array#first`/`#last`/`#slice`/`#reverse`/`#sort`/`#uniq`, `String#split`/`#chars`, `Dictionary#keys`/`#values`/`#merge`, and `for x by n` stride chunks all returned a raw Ruby Array/Hash instead of Lost::Array/Lost::Dictionary -- dot-index access (`it.0`) worked by accident via #maybe_instance, but `==` against a literal silently failed. No test exercised any of these at the value level until now.
		out = Lost.interp <<~CODE
		    pairs := []
		    for ['red', 'blue', 'green', 'yellow'] by 2
		        pairs.push(it)
		    end
		    pairs
		CODE
		assert_equal [['red', 'blue'], ['green', 'yellow']], out.values.map(&:values)

		assert_equal [1, 2], Lost.interp("[1, 2, 3, 4].first(2)").values
		assert_equal [3, 2, 1], Lost.interp("[1, 2, 3].reverse()").values
		assert_equal ['he', '', 'o'], Lost.interp("'hello'.split('l')").values
		assert_equal [:x, :y], Lost.interp("{x: 1, y: 2}.keys()").values
		assert_equal({ x: 1, y: 2 }, Lost.interp("{x: 1}.merge({y: 2})").hash)
	end

	def test_member_to_s_on_unnamed_type_only_member_does_not_crash_regression
		# `<String, Number>` (a schema-only struct with bare, unnamed type members) has `value == type` for its String member -- the bare String Type object itself, not an actual instance. `Member#to_s` unconditionally called `.pretty_print()` on it whenever `type.?name == 'String'`, assuming `value` was a real String instance -- raised `Cannot_Call_Instance_Member_On_Type` instead, since `pretty_print` is an instance-only method. `.?pretty_print()` (nil-safe) fixes it.
		refute_raises Lost::Cannot_Call_Instance_Member_On_Type do
			Lost.interp("<String, Number>.members.0.to_s()")
		end
	end

	def test_capitalized_identifier_comparison_does_not_get_parsed_as_a_tagged_type_reference_regression
		# `X < Y` (X/Y capitalized variables, not types) looks identical up to `TYPE_IDENTIFIER '<'` to `Ident <...>` -- #begin_expression always committed to #parse_struct on sight of that shape, which then ran out of tokens hunting for a `>` that was never coming (Lost::Out_Of_Tokens) instead of falling through to an ordinary `<` comparison. #try_parse_struct now actually attempts the real parse and rewinds on any syntax error instead of guessing via lookahead.
		assert_equal true, Lost.interp(<<~CODE)
		    X := 1
		    Y := 2
		    X < Y
		CODE

		# A capitalized comparison as the last expression in a block, with no trailing newline before the closing `}`, took the same wrong path for a different reason (a naive lookahead bounded only by newline would've kept scanning past `}` too).
		assert_equal true, Lost.interp(<<~CODE)
		    compute ( x, y; x < y)
		    compute(1, 2)
		CODE

		# A real tagged-type declaration/reference on one line still works, comma-separated members included -- confirms the fix didn't just move the false negative onto legitimate `Abc\<Number>` usage.
		assert_equal true, Lost.interp(<<~CODE)
		    Dictionary_Like\\<String, Number> {}
		    z := Dictionary_Like\\<String, Number>()
		    z.tag.types.length() == 2
		CODE

		# A struct member's own default value can legitimately contain delimiters (`(`/`)`, `[`/`]`, nested `{`/`}`) before the real closing `>` -- must not be mistaken for the statement's own boundary.
		assert_equal true, Lost.interp(<<~CODE)
		    mk (; 5 )
		    Abc\\<id := mk(), items := [1,2], dict := {x: 1}> {}
		    z := Abc\\<mk(), [1,2], {x:1}>()
		    z =/= nil
		CODE
	end

	def test_capitalized_function_param_raises_a_real_error_instead_of_crashing_regression
		# A bare Capitalized/UPPERCASE param (`f ( ABC; ABC )`) parses like a signature-literal's bare type (`param.type` set, `param.name` left nil, see #parse_func -- a real function param always starts lowercase, so a bare Capitalized token there can only mean a signature literal, e.g. `{Number -> String;}`) rather than a named param. #interp_func_body assumed every param has `.name` set, raising a raw NoMethodError (`undefined method 'value' for nil`) the first time it read `param.name.value`, instead of a real Lost error.
		assert_raises Lost::Invalid_Parameter_Name do
			Lost.interp <<~CODE
			    f ( ABC; ABC )
			    x := 1
			    f(x)
			CODE
		end

		# A genuine signature literal (never called, just described/assigned) is unaffected.
		refute_raises Lost::Invalid_Parameter_Name do
			Lost.interp '(Number -> String;)'
		end
	end
end
