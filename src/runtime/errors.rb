require_relative 'error_formatter'

module Lost
	class Error < StandardError
		attr_accessor :expression

		def initialize expression = nil
			# Some tool trying to Marshal.dump one of our errors (Minitest does, to report failures raised off the main thread) can still fail if `expression` itself is a live runtime object (holding closures/Procs, etc., not just a parse-time AST node) rather than a String message -- Minitest falls back to reconstructing via `klass.new(original.message)`. That lands here with a single String: it's already the final, formatted message, not an AST node to run back through the formatter -- use it as-is instead of silently producing a blank report.
			if expression.is_a? ::String
				super expression
				return
			end

			@expression = expression
			super format_error
		end

		def format_error
			Error_Formatter.new(self).format
		end

		def detail_message
			nil
		end
	end

	class Undeclared_Identifier < Error
		# `expression` is whatever AST node was being resolved when lookup failed, usually an Lost::Identifier_Expr (a plain identifier reference), but also an Lost::Type_Expr when a bare type reference (`Abc()`) never got declared. Both expose `.value` via the shared Expression base (set from their own lexeme), so one implementation covers either raise site without caring which one it actually got.
		def detail_message
			name = expression.respond_to?(:value) ? expression.value : nil
			return nil unless name
			"#{Ascii.bold name} has not been declared"
		end
	end

	class Undeclared_Tagged_Type < Error
		# No declared variant matches this structure -- also raised for a Bare Named Struct redeclared with a different shape. `expression` is a Type_Expr or a bare Struct_Expr (`.name` a raw Lexeme then).
		# @expression: Lost::Type_Expr | Lost::Struct_Expr

		def detail_message
			if expression.is_a? Lost::Struct_Expr
				name      = expression.name.is_a?(Lost::Lexeme) ? expression.name.value : expression.name
				structure = expression.to_s
			else
				name      = expression.name
				structure = expression.tag.to_s
			end

			expected_structured_type = "#{name}#{structure} {}"
			"#{Ascii.bold name} structured with #{Ascii.bold structure} not found:\n\n\t#{Ascii.bold expected_structured_type}"
		end
	end

	# A named reference (`Abc\Task_Schema`) resolved to something other than a Struct or Type -- neither form has a valid target.
	# @expression: Lost::Type_Expr
	class Tag_Reference_Must_Be_Type_Or_Struct < Error
		def detail_message
			"`#{Ascii.bold expression.name}#{Lost::TAG_OPERATOR}#{expression.tag.value}` -- the right-hand side of `#{Lost::TAG_OPERATOR}` must resolve to a Struct or a Type, not a plain value."
		end
	end

	# A struct member (`<...>`) named identifier is immediately followed by `:` and something that isn't a valid type (a capitalized identifier, or `<...>`) -- almost always a lowercase value, as if `:` worked like a Dictionary's `key: value`. It doesn't inside `<...>`: a struct member's only two named forms are `name: Type` and `name := value`. Raised at parse time rather than silently leaving the `:` unconsumed, which would otherwise reparse it as an unrelated `:symbol` prefix literal starting a brand-new element (commas are optional between struct members, same as any other list) -- `<columns: cols>` would silently become the two elements `columns, :cols`.
	class Invalid_Struct_Member_Annotation < Error
		def detail_message
			"A struct member's type must be capitalized (or `<...>`) right after `:` -- got a lowercase value instead. Use `name := value` to give a member a real value, or add a comma if two separate members were intended."
		end
	end

	class Cannot_Reassign_Constant < Error
	end

	class Cannot_Assign_Incompatible_Type < Error
	end

	class Cannot_Assign_Undeclared_Identifier < Error
	end

	class Cannot_Initialize_Non_Type_Identifier < Error
	end

	# Distinct from Cannot_Initialize_Non_Type_Identifier -- this is calling () on an ordinary value that just isn't callable, not X.new/X() on a non-Type.
	class Cannot_Call_Value < Error
	end

	class Invalid_Dictionary_Key < Error
	end

	class Invalid_Dictionary_Infix_Operator < Error
	end

	class Invalid_Dot_Infix_Left_Operand < Error
	end

	class Invalid_Dot_Infix_Right_Operand < Error
	end

	class Invalid_Array_Index < Error
	end

	class Unhandled_Prefix < Error
	end

	class Undeclared_Infix_Operator < Error
	end

	class Unhandled_Postfix < Error
	end

	class Missing_Argument < Error
	end

	class Invalid_Parameter_Name < Error
		attr_accessor :param_type

		def initialize expression, param_type
			@param_type = param_type
			super expression
		end

		def detail_message
			"A function parameter must start with a lowercase letter -- #{Ascii.bold param_type} reads as a bare type (like a signature literal's param list, e.g. `(Number -> String;)`), not a name"
		end
	end

	class Assert_Triggered < Error
		attr_accessor :assertion_message

		def initialize expression = nil, assertion_message = nil
			@assertion_message = assertion_message
			super expression
		end

		def detail_message
			assertion_message
		end
	end

	class Refute_Triggered < Error
		attr_accessor :refutation_message

		def initialize expression = nil, refutation_message = nil
			@refutation_message = refutation_message
			super expression
		end

		def detail_message
			refutation_message
		end
	end

	class Invalid_Http_Directive_Handler < Error
	end

	class Invalid_Start_Directive_Argument < Error
	end

	class Interpret_Expr_Not_Implemented < Error
		def detail_message
			"Interpreter does not handle `#{expression.inspect}` yet."
		end
	end

	class Out_Of_Tokens < Error
	end

	class Invalid_Scope_Syntax < Error
	end

	class Cannot_Use_Instance_Scope_Operator_Outside_Instance < Error
	end

	class Cannot_Use_Type_Scope_Operator_Outside_Type < Error
	end

	class Too_Many_Subscript_Expressions < Error
	end

	class Invalid_Subscript_Receiver < Error
	end

	class Cannot_Call_Private_Instance_Member < Error
	end

	class Cannot_Call_Instance_Member_On_Type < Error
	end

	class Cannot_Call_Private_Static_Member_On_Type < Error
	end

	class Invalid_Directive_Usage < Error
		# todo: This is not printing anything to stdouts
	end

	class Invalid_Scope_Directive_Argument < Error
	end

	class Missing_Ruby_Proxy_Declaration < Error
	end

	class Invalid_Ruby_Proxy_Directive_Usage < Error
		# @ruby directive only supports function and variable declarations in the body of a Type declaration
	end

	class Invalid_Static_Directive_Declaration < Error
		# @static directive only supports function and variable declarations in the body of a Type declaration
	end

	class Unterminated_String_Literal < Error
	end

	class Lexed_Unexpected_Char < Error
		attr_accessor :expected, :got

		def initialize expected:, got:
			@expected = expected
			@got      = got
		end

		def detail_message
			"Expected `#{expected.inspect}`, got `#{got.inspect}`"
		end
	end

	class Lex_Char_Not_Implemented < Error
	end

	class Url_Not_Set_For_Database_Instance < Error
	end

	class Database_Not_Set_For_Table_Instance < Error
	end

	class Type_Checking_Failed < Error
		attr_accessor :errors

		def initialize errors
			@errors = errors
			super nil
		end

		def format_error
			errors.map(&:message).join "\n"
		end
	end

	class Type_Mismatch < Error
		attr_accessor :declared, :inferred

		def initialize expression, declared, inferred
			@declared = declared
			@inferred = inferred
			super expression
		end

		def detail_message
			"Expected #{declared}, got #{inferred}"
		end
	end

	class Reserved_Function_Delimiter < Error
		def detail_message
			"#{expression.line_col}"
		end
	end

	class Type_Contract_Violation < Error
		attr_accessor :contract, :actual

		def initialize expression, contract, actual
			@contract = contract
			@actual   = actual
			super expression
		end

		def message
			"Type contract violation: expected #{@contract}, got #{@actual || 'unknown'}"
		end
	end

	class Operator_Overload_Fixity_Must_Be_One_Of < Error
	end

	class Operator_Overload_Precedence_Must_Be_Integer < Error
	end

	class Unsupported_Feature < Error
	end

	class Invalid_Func_Signature < Error
	end

	class Cannot_Call_Func_Signature < Error
		def detail_message
			args = expression.arguments.empty? ? '' : '...'
			"Did you mean to assign a function to `#{expression.receiver.value}` before calling `#{expression.receiver.value}(#{args})`?"
		end
	end

	class Unknown_Circumfix_Grouping < Error
	end

	class Arguments_Given_But_Not_Expected < Error
	end

	class Route_Param_Expected_But_Not_Found < Error
	end

	class Invalid_Composition_With_A_Non_Scope_type < Error
	end

	class Invalid_Composition_Operator < Error
	end

	class Argument_Label_Mismatch < Error
		attr_accessor :expected, :actual

		def initialize expression, expected, actual
			@expected = expected
			@actual   = actual
			super expression
		end

		def detail_message
			expected_label = expected ? "#{expected}:" : 'no label'
			actual_label   = actual ? "#{actual}:" : 'no label'
			"Expected #{Ascii.bold expected_label}, got #{Ascii.bold actual_label}"
		end
	end

	# A named argument (`name := value`) appeared, and then a bare positional or labeled argument followed it. Named arguments must come last in a call -- once you switch to naming arguments, every argument after that has to be named too.
	class Positional_Argument_After_Named < Error
		def detail_message
			'Positional arguments must come before named arguments (`name := value`) in a call'
		end
	end

	# The same name was used as a named argument (`name := value`) more than once in the same call.
	class Duplicate_Named_Argument < Error
		attr_accessor :name

		def initialize expression, name
			@name = name
			super expression
		end

		def detail_message
			"#{Ascii.bold name} was given more than once as a named argument"
		end
	end

	# A param was supplied both positionally (or by label) and by name in the same call, e.g. `add(1, a := 2)` where `a` is the first declared param.
	class Argument_Given_By_Name_And_Position < Error
		attr_accessor :name

		def initialize expression, name
			@name = name
			super expression
		end

		def detail_message
			"#{Ascii.bold name} was given both positionally and by name"
		end
	end

	# A named argument's name (`name := value`) doesn't match any of the callee's declared params.
	class Unknown_Named_Argument < Error
		attr_accessor :name

		def initialize expression, name
			@name = name
			super expression
		end

		def detail_message
			"#{Ascii.bold name} is not a declared parameter"
		end
	end

	class Invalid_Destructuring_Source < Error
		def detail_message
			'Only a Tuple or Struct can be destructured with `(...) := ...`'
		end
	end

	class Invalid_Destructuring_Target < Error
		def detail_message
			'Each destructuring target must be a plain identifier, e.g. `(a, b) := ...`'
		end
	end

	class Invalid_Percent_Literal_Expression < Error
		def detail_message
			# :kind :grouping :expressions
			kind     = expression.kind
			exprs    = expression.expressions
			given    = exprs.map(&:class).join(', ')
			expected = exprs.map do |it|
				'Lost::Identifier_Expr or Lost::Number_Expr or Lost::Operator_Expr'
			end.join(', ')
			"%#{kind}(#{given}) expects %#{kind}(#{expected})"
		end
	end

	class Destructuring_Arity_Mismatch < Error
		attr_accessor :expected, :actual

		def initialize expression, expected, actual
			@expected = expected
			@actual   = actual
			super expression
		end

		def detail_message
			"Tried to extract #{Ascii.bold expected.to_s} value#{'s' unless expected == 1}, but the source only has #{Ascii.bold actual.to_s}"
		end
	end
end
