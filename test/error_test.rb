require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class Error_Test < Base_Test
	def test_undeclared_identifier
		error = assert_raises Lost::Undeclared_Identifier do
			Lost.interp 'does_not_exist'
		end
	end

	def test_undeclared_identifier_in_file
		error = assert_raises Lost::Undeclared_Identifier do
			Lost.interp_file 'test/fixtures/undeclared_identifier.tape'
		end
	end

	def test_cannot_reassign_constant
		assert_raises Lost::Cannot_Reassign_Constant do
			Lost.interp 'CONST := 5, CONST = 10'
		end

		assert_raises Lost::Cannot_Assign_Undeclared_Identifier do
			Lost.interp 'CONST = 123'
		end
	end

	def test_cannot_assign_incompatible_type
		error = assert_raises Lost::Cannot_Assign_Incompatible_Type do
			Lost.interp 'Person { name, }, Person = 5'
		end
	end

	def test_cannot_call_value
		# Was Cannot_Initialize_Non_Type_Identifier -- misleading, since nothing here is a construction attempt, just a plain value that isn't callable.
		assert_raises Lost::Cannot_Call_Value do
			Lost.interp 'x := 5, x()'
		end
	end

	def test_cannot_call_value_when_a_dictionary_field_shadows_a_builtin_method_name
		assert_raises Lost::Cannot_Call_Value do
			Lost.interp 'dict := {keys: 4}, dict.keys()'
		end
	end

	def test_invalid_dictionary_key
		error = assert_raises Lost::Invalid_Dictionary_Key do
			Lost.interp '{5: "value"}'
		end
	end

	def test_invalid_dictionary_infix_operator
		error = assert_raises Lost::Invalid_Dictionary_Infix_Operator do
			Lost.interp '{x + 5}'
		end
	end

	def test_missing_argument
		# todo: Doesn't display code and location
		assert_raises Lost::Missing_Argument do
			Lost.interp 'add := ( a, b; a + b ), add(5)'
		end
	end

	def test_invalid_start_directive_argument
		# todo: Doesn't display code and location
		assert_raises Lost::Invalid_Start_Directive_Argument do
			Lost.interp '@start_server 5'
		end
	end

	def test_invalid_directive_usage
		# todo: Doesn't display code and location
		assert_raises Lost::Invalid_Directive_Usage do
			Lost.interp '@unknown 123'
		end
	end

	def test_unterminated_string_literal
		# todo: Doesn't display code and location
		assert_raises Lost::Unterminated_String_Literal do
			Lost.interp '"unterminated'
		end
	end

	def test_too_many_subscript_expressions
		assert_raises Lost::Too_Many_Subscript_Expressions do
			Lost.interp 'arr := [1, 2, 3], arr[0, 1]'
		end
	end

	def test_arguments_given_but_not_expected
		assert_raises Lost::Arguments_Given_But_Not_Expected do
			Lost.interp 'funk (; 42 ), funk(5)'
		end
	end

	def test_invalid_composition_with_a_non_scope_type
		assert_raises Lost::Invalid_Composition_With_A_Non_Scope_type do
			Lost.interp 'Foo := :bar, Person | Foo { name, }'
		end
	end

	# The parser's pre-scan registers a custom operator file-wide, but the overload itself is a regular declaration — using the operator outside the scope that declares it finds no overload. Used to silently evaluate to nil.
	def test_undeclared_infix_operator
		assert_raises Lost::Undeclared_Infix_Operator do
			Lost.interp 'scoped (;
				@operator ~> @infix 300 ( l, r; l )
			)
			1 ~> 2'
		end
	end

	def test_route_param_expected_but_not_found
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := 3099;
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get://users/:id ( id;
		    		"User `id`"
		    	)
		    }

		    app := Web_App()
		TAPE

		interpreter = Lost::Interpreter.new
		interpreter.run code
		route = interpreter.route_functions_by_route_name.values.first

		req = interpreter.build_lost_request '/users', 'get', {}, {}, {}, {}
		res = interpreter.build_lost_response nil

		# Bypasses the normal HTTP dispatch path (which always extracts matching url_params from the URL), so it's the only way to hit this branch: an :id param declared on the route but missing from url_params.
		assert_raises Lost::Route_Param_Expected_But_Not_Found do
			interpreter.interp_route_body route, req, res, {}
		end
	end

	def test_error_location_tracking_inline
		assert_raises Lost::Undeclared_Identifier do
			Lost.interp 'x := 5, y := undefined_var, z := 10'
		end
	end

	def test_error_location_tracking_file
		assert_raises Lost::Undeclared_Identifier do
			Lost.interp_file 'test/fixtures/undeclared_identifier.tape'
		end
	end

	def test_error_with_infix_expression_has_location
		assert_raises Lost::Cannot_Reassign_Constant do
			Lost.interp 'CONST := 5, CONST = 10'
		end
	end

	def test_error_formatting_includes_source_snippet
		assert_raises Lost::Undeclared_Identifier do
			Lost.interp 'x := 5, y := undefined_var'
		end
	end
end
