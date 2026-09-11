module Backend
	class Type_Checker
		include Prog
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

		# Stdlib type aliases (`Int := Integer`, `Str := String`, ...) -- this checker has no scope to
		# resolve them at runtime, so it normalizes the handful of concrete-type ones it reasons about.
		TYPE_ALIASES = {
			'Int' => 'Integer', 'Flo' => 'Float', 'Dec' => 'Decimal', 'Num' => 'Number', 'Str' => 'String',
		}.freeze

		def types_compatible? declared, inferred
			declared = TYPE_ALIASES.fetch declared, declared
			inferred = TYPE_ALIASES.fetch inferred, inferred
			return true if declared == 'Any' || declared == inferred
			return false unless NUMERIC_FAMILY.include?(declared) && NUMERIC_FAMILY.include?(inferred)
			declared == 'Number' || inferred == 'Number'
		end

		# Maps an expression to its Backend type name. Returns nil if unknown.
		def infer_type expr
			case expr
			when Prog::String_Expr then 'String'
			when Prog::Number_Expr then expr.type == :float ? 'Float' : 'Integer'
			when Prog::Symbol_Expr then 'Symbol'
			when Prog::Identifier_Expr then type_by_identifier expr.value
			when Prog::Infix_Expr then infer_dot_type expr
			else nil
			end
		end

		# Resolves `receiver`'s own static type, then looks up `member` as a declared member on that type. Returns nil the moment any link in the chain isn't statically known (an untyped local, a plain untagged bare type, etc), same "skip rather than guess" philosophy as the rest of this checker.
		def infer_dot_type expr
			return nil unless expr.operator&.value == '.'
			return nil unless expr.right.is_a? Prog::Identifier_Expr

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
			return if expr.parameters.any?(&:variadic) # variadic arity / element typing isn't statically modeled

			param_types = expr.parameters.map { |p| p.type&.value unless p.type.is_a?(Prog::Struct_Expr) } # structural params aren't checked statically
			declare :funcs, expr.name.value, param_types
			@type_info[@type_stack.last][:methods][expr.name.value] = param_types if @type_stack.last
		end

		# `expr` is a Call_Expr's receiver: either a bare function name (`add(...)`) or a `.`-chain ending in a method name (`app.servers.push(...)`). Returns the param type array for whichever one it resolves to, or nil if neither does.
		def resolve_call_signature receiver
			if receiver.is_a? Prog::Identifier_Expr
				func_signature_by_identifier receiver.value
			elsif receiver.is_a?(Prog::Infix_Expr) && receiver.operator&.value == '.' && receiver.right.is_a?(Prog::Identifier_Expr)
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
				next nil if types_compatible? expected, inferred
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
			return nil if expr.left.type.is_a? Prog::Struct_Expr # structural annotations aren't checked statically

			declared = annotation_type_names expr.left.type # e.g. ["String"], or ["Int", "Nil"] for `x: Int | Nil`
			declare_member expr.left.value, declared.first
			inferred = infer_type expr.right # e.g. "Integer" or nil

			return nil if inferred.nil?
			return nil if declared.any? { |name| types_compatible? name, inferred }

			Type_Mismatch.new expr, declared.join(' | '), inferred
		end

		# The alternative type name(s) an annotation names -- a plain `x: Int` is just `[expr.value]`; a
		# composition chain in the annotation position (`x: Int | Nil`) parses to an anonymous_composition
		# Type_Expr (same as a func's own `-> Type` return-type annotation) -- walk its leading name plus
		# each `|`/`&`/`~`/`^` operand's name. Mirrors Interpreter#annotation_type_names (runtime side).
		def annotation_type_names type_expr
			return [] unless type_expr
			return [type_expr.value] unless type_expr.is_a?(Prog::Type_Expr) && type_expr.anonymous_composition

			names = [type_expr.name]
			type_expr.expressions.each do |composition|
				next unless composition.is_a? Prog::Composition_Expr

				operand = composition.identifier
				names << (operand.is_a?(Prog::Type_Expr) ? operand.name : operand.value)
			end
			names.compact
		end

		# `x := Type(...)` / `x := Type<Struct>(...)`.
		def check_inferred_declaration expr
			return unless expr.left.is_a? Prog::Identifier_Expr

			constructed = constructed_type_name expr.right
			return unless constructed

			declare_member expr.left.value, constructed
		end

		def declare_member name, type_name
			declare :types, name, type_name
			@type_info[@type_stack.last][:members][name] = type_name if @type_stack.last
		end

		def constructed_type_name expr
			return nil unless expr.is_a? Prog::Call_Expr
			receiver = expr.receiver

			case receiver
			when Prog::Type_Expr
				qualified_type_name receiver
			when Prog::Identifier_Expr
				receiver.value if Helpers.type_identifier? receiver.value
			end
		end

		def qualified_type_name expr
			return nil unless expr.is_a? Prog::Type_Expr
			return expr.name unless expr.tag

			# A named reference (`Abc\Task_Schema`) has no member list to render -- just use its own name.
			return "#{expr.name}#{Prog::TAG_OPERATOR}#{expr.tag.value}" unless expr.tag.is_a? Prog::Struct_Expr

			member_names = expr.tag.types.map { |t| t.value if t.is_a? Prog::Identifier_Expr }
			return nil if member_names.any?(&:nil?)

			"#{expr.name}<#{member_names.join(',')}>"
		end

		def check_param expr
			return nil unless expr.type && expr.default
			return nil if expr.variadic # `x: Args` is a variadic marker, not a real element type
			return nil if expr.type.is_a? Prog::Struct_Expr # structural annotations aren't checked statically
			declared = annotation_type_names expr.type
			inferred = infer_type expr.default
			return nil if inferred.nil?
			return nil if declared.any? { |name| types_compatible? name, inferred }

			Type_Mismatch.new expr, declared.join(' | '), inferred
		end

		# `nil` means there is no error with the expression. The pattern for most of the cases is just: recurse into child expressions and collect errors.
		# @return nil, Error, or Array of Errors.
		def check expr
			case expr
			when Prog::Infix_Expr
				check_infix expr

			when Prog::Param_Expr
				check_param expr

			when Prog::Prefix_Expr
				check expr.expression
			when Prog::Postfix_Expr
				check expr.expression
			when Prog::Route_Expr
				check expr.expression

			when Prog::Circumfix_Expr
				check expr.expressions
			when Prog::Func_Expr
				# #register_func runs before the new scope is pushed, so the function's own name is declared into the *enclosing* scope (visible to siblings, and to the function's own body too since lookups search outward so recursive calls still resolve).
				register_func expr
				with_new_scope { check expr.parameters + expr.expressions }
			when Prog::Type_Expr
				if expr.expressions
					@type_stack.push qualified_type_name(expr)
					result = with_new_scope { check expr.expressions }
					@type_stack.pop
					result
				end

			when Prog::Subscript_Expr
				[check(expr.receiver), check(expr.expression)]
			when Prog::For_Loop_Expr
				[check(expr.collection), check(expr.body)]
			when Prog::Call_Expr
				check_call expr

			when Prog::Conditional_Expr
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
