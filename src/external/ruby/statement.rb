module Tape
	# Tape wrapper for `*_Expr < Expression`. Built two ways:
	# 1. A backtick literal (`` `expr` ``) -- Interpreter#interp_statement builds this directly and
	#    sets captured_scope, since only interpreter-side code has a stack to read from.
	# 2. `Statement(...)` -- goes through the normal Type-construction path, so #initialize only ever
	#    sees a throwaway arg (same as every Ruby-backed Tape type, e.g. Tape::String/Tape::Array); real
	#    argument binding happens in tapes/statement.tape's `new(;)` instead.
	class Statement < Instance
		attr_reader :expression #: Expression

		# Scope on top of the stack when this was built from a backtick literal -- mirrors
		# Tape::Func#enclosing_scope's closure trick. Set only by Interpreter#interp_statement; nil
		# otherwise, and Interpreter#invoke_statement then falls back to use_caller_scope behavior.
		#
		# use_caller_scope/memoize/memoized/_memoized_value live in tapes/statement.tape as ordinary Tape
		# members instead (so plain dot-assignment works); read/written from Ruby via Scope#[]/#[]=.
		attr_accessor :captured_scope

		def initialize statement = nil
			super 'Statement'
			self.expression = statement
		end

		def expression= value
			@expression                  = value
			@declarations['_expression'] = value
		end

		# Called from `new(;)` when constructing via `Statement(other)` -- copies other's expression,
		# captured_scope, and settings, so it behaves like reusing `other`, not recapturing here.
		def proxy_from other
			return unless other.is_a? Tape::Statement

			self.expression          = other.expression
			@captured_scope          = other.captured_scope
			self['use_caller_scope'] = other['use_caller_scope']
			self['memoize']          = other['memoize']
			nil
		end

		def proxy_to_s
			"Statement{#{expression.class.name}}"
		end
	end
end
