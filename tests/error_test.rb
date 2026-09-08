require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Error_Test < Base_Test
	def test_undeclared_identifier
		error = assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'does_not_exist'
		end
	end

	def test_undeclared_identifier_in_file
		error = assert_raises Disk::Undeclared_Identifier do
			Drive.interp_file 'tests/fixtures/undeclared_identifier.disk'
		end
	end

	def test_receiver_is_nil_on_member_read
		error = assert_raises Disk::Receiver_Is_Nil do
			Drive.interp "task,\ntask.type"
		end
		# Ascii.bold wraps parts of the message in escape codes when stdout is a TTY -- strip them so the
		# assertion holds whether or not the test run is attached to a terminal.
		plain = error.message.gsub(/\e\[[\d;]*m/, '')
		assert_includes plain, 'task is nil -- no member .type to reach'
	end

	def test_receiver_is_nil_on_member_call
		assert_raises Disk::Receiver_Is_Nil do
			Drive.interp "x,\nx.foo()"
		end
	end

	def test_receiver_is_nil_on_member_write_and_declare
		assert_raises Disk::Receiver_Is_Nil do
			Drive.interp "x,\nx.foo = 1"
		end

		assert_raises Disk::Receiver_Is_Nil do
			Drive.interp "x,\nx.foo := 1"
		end
	end

	def test_nil_still_reaches_its_own_declared_members
		assert_equal 'nil', Drive.interp('nil.to_s()')
	end

	def test_safe_navigation_on_nil_returns_nil
		assert_nil Drive.interp("x,\nx.?foo")
	end

	def test_cannot_reassign_constant
		assert_raises Disk::Cannot_Reassign_Constant do
			Drive.interp 'CONST := 5, CONST = 10'
		end

		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp 'CONST = 123'
		end
	end

	def test_cannot_assign_incompatible_type
		error = assert_raises Disk::Cannot_Assign_Incompatible_Type do
			Drive.interp 'Person { name, }, Person = 5'
		end
	end

	def test_cannot_call_value
		assert_raises Disk::Receiver_Is_Not_Callable do
			Drive.interp 'x := 5, x()'
		end
	end

	def test_cannot_call_value_when_a_dictionary_field_shadows_a_builtin_method_name
		assert_raises Disk::Receiver_Is_Not_Callable do
			Drive.interp 'dict := {keys: 4}, dict.keys()'
		end
	end

	def test_invalid_dictionary_key
		error = assert_raises Disk::Invalid_Dictionary_Key do
			Drive.interp '{5: "value"}'
		end
	end

	def test_invalid_dictionary_infix_operator
		error = assert_raises Disk::Invalid_Dictionary_Infix_Operator do
			Drive.interp '{x + 5}'
		end
	end

	def test_missing_argument
		# todo: Doesn't display code and location
		assert_raises Disk::Missing_Argument do
			Drive.interp 'add := ( a, b; a + b ), add(5)'
		end
	end

	def test_invalid_start_directive_argument
		# todo: Doesn't display code and location
		assert_raises Disk::Invalid_Server_Argument do
			Drive.interp '@start_server 5'
		end
	end

	def test_unknown_context_word_raises
		# `@unknown` isn't a Context member anywhere -- there's no "directive" concept to reject it as.
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp '@unknown 123'
		end
	end

	def test_unterminated_string_literal
		# todo: Doesn't display code and location
		assert_raises Disk::Unterminated_String_Literal do
			Drive.interp '"unterminated'
		end
	end

	def test_too_many_subscript_expressions
		assert_raises Disk::Too_Many_Subscript_Expressions do
			Drive.interp 'arr := [1, 2, 3], arr[0, 1]'
		end
	end

	def test_arguments_given_but_not_expected
		assert_raises Disk::Arguments_Given_But_Not_Expected do
			Drive.interp 'funk (; 42 ), funk(5)'
		end
	end

	def test_invalid_composition_with_a_non_scope_type
		assert_raises Disk::Invalid_Composition_With_A_Non_Scope_type do
			Drive.interp 'Foo := :bar, Person | Foo { name, }'
		end
	end

	# The parser's pre-scan registers a custom operator file-wide, but the overload itself is a regular declaration — using the operator outside the scope that declares it finds no overload. Used to silently evaluate to nil.
	def test_undeclared_infix_operator
		assert_raises Disk::Undeclared_Infix_Operator do
			Drive.interp 'scoped (;
				@operator ~> @infix 300 ( l, r; l )
			)
			1 ~> 2'
		end
	end

	def test_route_param_expected_but_not_found
		code = <<~DISK
		    Server {
		    	port,
		    	Self ( port := 3099;
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get://users/:id ( id;
		    		"User `id`"
		    	)
		    }

		    app := Web_App()
		DISK

		interpreter = Drive::Interpreter.new
		interpreter.run code
		route = interpreter.route_functions_by_route_name.values.first

		req = interpreter.build_disk_request '/users', 'get', {}, {}, {}, {}
		res = interpreter.build_disk_response nil

		# Bypasses the normal HTTP dispatch path (which always extracts matching url_params from the URL), so it's the only way to hit this branch: an :id param declared on the route but missing from url_params.
		assert_raises Disk::Route_Param_Expected_But_Not_Found do
			interpreter.interp_route_body route, req, res, {}
		end
	end

	def test_error_location_tracking_inline
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'x := 5, y := undefined_var, z := 10'
		end
	end

	def test_error_location_tracking_file
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp_file 'tests/fixtures/undeclared_identifier.disk'
		end
	end

	def test_error_with_infix_expression_has_location
		assert_raises Disk::Cannot_Reassign_Constant do
			Drive.interp 'CONST := 5, CONST = 10'
		end
	end

	def test_error_formatting_includes_source_snippet
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp 'x := 5, y := undefined_var'
		end
	end
end
