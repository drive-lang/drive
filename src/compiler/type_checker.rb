module Tape
	class Type_Checker
		attr_accessor :input

		def initialize input
			@input  = input
			@scopes = [new_scope_frame]

			# Per-declared-type member/method registry, keyed by qualified type name ("Web_Application", "Array\Web_Server" for a tagged type
			@type_info  = Hash.new { |h, k| h[k] = { members: {}, methods: {} } }
			@type_stack = [] # qualified type names currently being walked, innermost last
		end

		def output
			errors = input.filter_map { check _1 }.flatten.compact
			raise Type_Checking_Failed.new errors if errors.any?
		end

		NUMERIC_FAMILY = %w[Number Integer Float Decimal].freeze

		# Two type names are compatible if equal, or if both are in the numeric family and at least one
		# side is the family base `Number` -- so `x: Number = 4` (Number vs Integer) passes, while
		# `x: Integer = 4.5` (Integer vs Float) is still flagged.
		def numeric_compatible? declared, inferred
			return true if declared == inferred
			return false unless NUMERIC_FAMILY.include?(declared) && NUMERIC_FAMILY.include?(inferred)
			declared == 'Number' || inferred == 'Number'
		end

		# Maps an expression to its Tape type name. Returns nil if unknown.
		def infer_type expr
			case expr
			when Tape::String_Expr then 'String'
			when Tape::Number_Expr then expr.type == :float ? 'Float' : 'Integer'
			when Tape::Symbol_Expr then 'Symbol'
			when Tape::Identifier_Expr then type_by_identifier expr.value
			when Tape::Infix_Expr then infer_dot_type expr
			else nil
			end
		end

		# Resolves `receiver`'s own static type, then looks up `member` as a declared member on that type. Returns nil the moment any link in the chain isn't statically known (an untyped local, a plain untagged bare type, etc), same "skip rather than guess" philosophy as the rest of this checker.
		def infer_dot_type expr
			return nil unless expr.operator&.value == '.'
			return nil unless expr.right.is_a? Tape::Identifier_Expr

			receiver_type = infer_type expr.left
			return nil unless receiver_type

			@type_info[receiver_type][:members][expr.right.value]
		end

		# Looks up `name`'s declared type, searching from the current scope outward.
		def type_by_identifier name
			find_in_scopes :types, name
		end

		def func_signature_by_identifier name
			find_in_scopes :funcs, name
		end

		def register_func expr
			return unless expr.name
			return unless expr.parameters.any?(&:type)

			param_types = expr.parameters.map { |p| p.type&.value unless p.type.is_a?(Tape::Struct_Expr) } # structural params aren't checked statically
			declare :funcs, expr.name.value, param_types
			@type_info[@type_stack.last][:methods][expr.name.value] = param_types if @type_stack.last
		end

		# `expr` is a Call_Expr's receiver: either a bare function name (`add(...)`) or a `.`-chain ending in a method name (`app.servers.push(...)`). Returns the param type array for whichever one it resolves to, or nil if neither does.
		def resolve_call_signature receiver
			if receiver.is_a? Tape::Identifier_Expr
				func_signature_by_identifier receiver.value
			elsif receiver.is_a?(Tape::Infix_Expr) && receiver.operator&.value == '.' && receiver.right.is_a?(Tape::Identifier_Expr)
				receiver_type = infer_type receiver.left
				receiver_type && @type_info[receiver_type][:methods][receiver.right.value]
			end
		end

		def check_call expr
			signature = resolve_call_signature expr.receiver
			return nil unless signature.is_a? ::Array

			expr.arguments.each_with_index.filter_map do |arg, i|
				expected = signature[i]
				next nil unless expected
				inferred = infer_type arg
				next nil if inferred.nil?
				next nil if numeric_compatible? expected, inferred
				Type_Mismatch.new arg, expected, inferred
			end
		end

		def check_infix expr
			case expr.operator&.value
			when '='
				check_typed_assignment expr
			when ':='
				check_inferred_declaration expr
				nil
			end
		end

		# `x: Type = value` is the only case with an explicit declared type to actually compare a literal RHS against.
		def check_typed_assignment expr
			return nil unless expr.left.respond_to?(:type) && expr.left.type
			return nil if expr.left.type.is_a? Tape::Struct_Expr # structural annotations aren't checked statically

			declared = expr.left.type.value # e.g. "String"
			declare_member expr.left.value, declared
			inferred = infer_type expr.right # e.g. "Integer" or nil

			return nil if inferred.nil?
			return nil if numeric_compatible? declared, inferred

			Type_Mismatch.new expr, declared, inferred
		end

		# `x := Type(...)` / `x := Type<Struct>(...)`.
		def check_inferred_declaration expr
			return unless expr.left.is_a? Tape::Identifier_Expr

			constructed = constructed_type_name expr.right
			return unless constructed

			declare_member expr.left.value, constructed
		end

		def declare_member name, type_name
			declare :types, name, type_name
			@type_info[@type_stack.last][:members][name] = type_name if @type_stack.last
		end

		def constructed_type_name expr
			return nil unless expr.is_a? Tape::Call_Expr
			receiver = expr.receiver

			case receiver
			when Tape::Type_Expr
				qualified_type_name receiver
			when Tape::Identifier_Expr
				receiver.value if Helpers.type_identifier? receiver.value
			end
		end

		def qualified_type_name expr
			return nil unless expr.is_a? Tape::Type_Expr
			return expr.name unless expr.tag

			# A named reference (`Abc\Task_Schema`) has no member list to render -- just use its own name.
			return "#{expr.name}#{Tape::TAG_OPERATOR}#{expr.tag.value}" unless expr.tag.is_a? Tape::Struct_Expr

			member_names = expr.tag.types.map { |t| t.value if t.is_a? Tape::Identifier_Expr }
			return nil if member_names.any?(&:nil?)

			"#{expr.name}<#{member_names.join(',')}>"
		end

		def check_param expr
			return nil unless expr.type && expr.default
			return nil if expr.type.is_a? Tape::Struct_Expr # structural annotations aren't checked statically
			declared = expr.type.value
			inferred = infer_type expr.default
			return nil if inferred.nil?
			return nil if numeric_compatible? declared, inferred

			Type_Mismatch.new expr, declared, inferred
		end

		# `nil` means there is no error with the expression. The pattern for most of the cases is just: recurse into child expressions and collect errors.
		# @return nil, Error, or Array of Errors.
		def check expr
			case expr
			when Tape::Infix_Expr
				check_infix expr

			when Tape::Param_Expr
				check_param expr

			when Tape::Directive_Expr
				check expr.expression
			when Tape::Prefix_Expr
				check expr.expression
			when Tape::Postfix_Expr
				check expr.expression
			when Tape::Route_Expr
				check expr.expression

			when Tape::Circumfix_Expr
				check expr.expressions
			when Tape::Func_Expr
				# #register_func runs before the new scope is pushed, so the function's own name is declared into the *enclosing* scope (visible to siblings, and to the function's own body too since lookups search outward so recursive calls still resolve).
				register_func expr
				with_new_scope { check expr.parameters + expr.expressions }
			when Tape::Type_Expr
				if expr.expressions
					@type_stack.push qualified_type_name(expr)
					result = with_new_scope { check expr.expressions }
					@type_stack.pop
					result
				end

			when Tape::Subscript_Expr
				[check(expr.receiver), check(expr.expression)]
			when Tape::For_Loop_Expr
				[check(expr.collection), check(expr.body)]
			when Tape::Call_Expr
				check_call expr

			when Tape::Conditional_Expr
				[
					check(expr.condition),
					check(expr.when_true),
					check(expr.when_false),
				]

			when ::Array
				expr.filter_map { check _1 }

			else
				nil
			end
		end

		private

		def new_scope_frame
			{ types: {}, funcs: {} }
		end

		def declare kind, name, value
			@scopes.last[kind][name] = value
		end

		def find_in_scopes kind, name
			@scopes.reverse_each do |scope|
				return scope[kind][name] if scope[kind].key? name
			end
			nil
		end

		def with_new_scope
			@scopes.push new_scope_frame
			yield
		ensure
			@scopes.pop
		end
	end
end
