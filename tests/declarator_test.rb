require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Declarator_Test < Base_Test
	def test_top_level_func_is_declared
		decls = Drive.declare "add ( a, b; a + b )"
		assert decls.key? 'add'
	end

	def test_literal_rhs_is_preserved_not_dropped
		decls = Drive.declare "greeting := 'hi'"
		assert_instance_of Disk::String_Expr, decls['greeting'].expr_or_decl
	end

	def test_plain_identifier_rhs_is_not_double_wrapped
		decls = Drive.declare "flag := true"
		assert_instance_of Disk::Identifier_Expr, decls['flag'].expr_or_decl
	end

	def test_named_struct_gets_its_declaring_name
		decls = Drive.declare "Named <String, Number>"
		assert_equal 'Named', decls['Named'].expr.name.value
	end

	def test_conditional_branches_flatten_into_enclosing_scope
		decls = Drive.declare <<~DISK
		    check (;
		    	if true
		    		a := 1
		    	elwhile false
		    		b := 2
		    	else
		    		c := 3
		    	end
		    )
		DISK
		nested = decls['check'].expr_or_decl
		assert_equal %w(a b c), nested.keys.sort
	end

	def test_for_loop_body_does_not_leak_out
		decls = Drive.declare <<~DISK
		    run (;
		    	for [1, 2, 3]
		    		z := it
		    	end
		    )
		DISK
		assert_empty decls['run'].expr_or_decl
	end

	def test_call_site_named_arguments_are_not_declarations
		decls = Drive.declare "sub(a := 1, b := 2)"
		assert_empty decls
	end

	# A bare identifier reference (`(x)` reading the value, not declaring it) must never register itself in #declare_all's Hash -- it used to, and since it shares the real declaration's key, whichever one #declare_all happened to visit last silently won.
	def test_bare_identifier_reference_does_not_clobber_the_real_declaration
		decls = Drive.declare <<~DISK
		    x := 1
		    (x)
		DISK
		assert_instance_of Disk::Number_Expr, decls['x'].expr_or_decl
	end

	def test_calling_a_function_before_its_definition_works
		out = Drive.interp <<~DISK
		    result := main()
		    main (; helper() )
		    helper (; 42 )
		    result
		DISK
		assert_equal 42, out
	end

	def test_referencing_a_type_before_its_definition_works
		out = Drive.interp <<~DISK
		    p := make_point()

		    Point {
		    	x,
		    	y,
		    	Self ( x, y; self.x = x, self.y = y )
		    }

		    make_point (;
		    	Point(3, 4)
		    )

		    p.x
		DISK
		assert_equal 3, out
	end

	def test_mutual_recursion_forced_from_the_first_call
		out = Drive.interp <<~DISK
		    result := is_even(4)

		    is_even ( n;
		    	if n == 0
		    		true
		    	else
		    		is_odd(n - 1)
		    	end
		    )

		    is_odd ( n;
		    	if n == 0
		    		false
		    	else
		    		is_even(n - 1)
		    	end
		    )

		    result
		DISK
		assert_equal true, out
	end

	def test_genuinely_undeclared_identifier_still_raises
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "totally_missing()"
		end
	end

	# `This := That {}` self-declares a class alias (see CLAUDE.md) -- same declarative category as a bare Type_Expr, just spelled through an assignment, so it should hoist the same way.
	def test_class_alias_assignment_before_its_definition_works
		out = Drive.interp <<~DISK
		    p := This()
		    This := That {}
		    That { greet (; 'hi' ) }
		    p.greet()
		DISK
		assert_equal 'hi', out
	end

	# A bare `@load` merges the loaded file's own declarations directly into the current scope, so
	# code above it can already use whatever it brings in -- forcing one name has to bring in the
	# whole file, not just that one isolated declaration, since Div | Dom {} needs Dom too.
	def test_bare_load_directive_can_sit_below_code_that_uses_it
		out = Drive.interp <<~DISK
		    sign := Div([P('hi')])
		    result := sign.to_s()

		    @load 'disks/html.disk'

		    result
		DISK
		assert_equal '<div><p>hi</p></div>', out
	end

	# Forcing one name from a bare @load must mark the whole @load directive as forced, not just
	# that one declaration -- otherwise #output's own walk re-runs the @load a second time when it
	# reaches that line for real, and if it's the last statement, the program's own reported result
	# silently becomes whatever that file's own last declaration evaluates to instead.
	def test_bare_load_directive_is_not_run_twice_when_reached_normally
		out = Drive.interp <<~DISK
		    sign := Div([P('hi')])
		    result := sign.to_s()

		    @load 'disks/html.disk'
		DISK
		assert_equal '<div><p>hi</p></div>', out
	end

	# `Ident := @load 'file'` / `IDENT := @load 'file'` build a scope of their own, same declarative
	# category as a class alias -- but only a Capitalized/UPPERCASE left-hand name opts in.
	def test_capitalized_named_load_can_sit_below_code_that_uses_it
		out = Drive.interp <<~DISK
		    sign := Html_Lib.Div([Html_Lib.P('hi')])
		    result := sign.to_s()

		    Html_Lib := @load 'disks/html.disk'

		    result
		DISK
		assert_equal '<div><p>hi</p></div>', out
	end

	def test_lowercase_named_load_is_not_forward_referenceable
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~DISK
			    sign := html_lib.Div([html_lib.P('hi')])

			    html_lib := @load 'disks/html.disk'
			DISK
		end
	end

	# The core guardrail: functions/types are declarative (order doesn't change what they mean), so forward-referencing one is fine -- but a plain `:=` is a step in the program's own imperative order, and reading it before that step runs is a real bug in the *program*. Forward-resolving it anyway would silently paper over exactly that bug.
	def test_plain_variable_assignments_are_not_forward_referenceable
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~DISK
			    @puts "`a`"
			    a := 123
			    nil
			DISK
		end
	end

	# `ident,` (nil-init) is the same non-hoistable category as `:=`/`=` -- also a step in the program's own order, not a declaration.
	def test_nil_init_assignments_are_not_forward_referenceable
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~DISK
			    @puts "`a`"
			    a,
			    nil
			DISK
		end
	end

	# The guardrail holds even when the read happens inside a hoisted function's own body, not just a bare top-level statement -- `main` hoisting fine doesn't make `count` (read inside it) hoistable too.
	def test_variable_read_inside_a_hoisted_function_still_raises
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~DISK
			    main()
			    main (; count )
			    count := 5
			DISK
		end
	end

	def test_forced_function_is_not_run_twice_when_reached_normally
		out = Drive.interp <<~DISK
		    calls := 0

		    build_thing (;
		    	calls += 1
		    	calls
		    )

		    result := use_before_declared()

		    use_before_declared (;
		    	build_thing()
		    )

		    (result, calls)
		DISK

		assert_equal 1, out.values[0]
		assert_equal 1, out.values[1]
	end

	def test_load_into_isolated_scope_is_not_leaked_by_forward_resolution
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp "mod := @load 'tests/fixtures/test_module.disk'\nMODULE_NAME"
		end
	end

	def test_dot_access_does_not_fall_through_to_an_unrelated_global
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~DISK
			    Vec2 { x := 0 }
			    NOW_OUTSIDE := 1
			    Vec2.NOW_OUTSIDE
			DISK
		end
	end
end
