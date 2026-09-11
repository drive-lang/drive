module Backend
	# @param [::String] key
	# @param [Prog::Expression | Prog::Declaration] expr_or_decl
	# @param [Prog::Expression] expr, the original expression that must be interpreted to actually bring this declaration into being (used for lazy/forward resolution, see Interpreter#resolve_forward_declaration)
	Declaration = ::Data.define(:key, :expr_or_decl, :expr) do
		def == other
			other.key == key
		end
	end

	class Declarator
		include Prog
		extend Cached_By_Path

		# {::String resolved_path => Hash{::String => Declaration}}
		cache_by_path :cached_declarations_by_filepath

		# Filepaths currently being resolved, guarding against a load cycle (A @loads B @loads A) recursing forever. Not part of the cache-by-path mixin above. This is an in-flight guard, not a persistent cache to invalidate on file change.
		@currently_loading_filepaths = ::Set.new

		class << self
			attr_accessor :currently_loading_filepaths
		end

		# Mirrors Interpreter#load_file_into_scope's own path resolution exactly -- kept here too since Declarator has to resolve a load target itself, ahead of the real interpreter ever reaching that @load.
		def self.resolve_load_filepath filepath
			filepath = filepath.dup
			filepath << '.prog' unless filepath.end_with? '.prog'
			if filepath.start_with? 'backend/'
				::File.join Backend::ROOT_PATH, filepath
			else
				::File.expand_path filepath
			end
		end

		attr_accessor :input
		attr_reader :declarations

		# note; I'm not evaluating any of these input expressions, I'm just storing them
		# @param [Array<Prog::Expression>] input
		def initialize input = []
			@input        = input # [Prog::Expression]
			@declarations = Hash.new # {::String : Prog::Declaration}
		end

		def output
			@declarations = declare_all input
		end

		def to_decl expr
			# `.name`, where it exists, isnt always a plain ::String -- Func_Expr's is an Identifier_Expr (unwrap via .value), a bare named Struct_Expr's is a raw Lexeme too (#parse_struct's leading-identifier capture); Operator_Expr/Operator_Overload_Expr have no .name at all, so fall back to .value, which holds the operator symbol itself
			key = if expr.respond_to?(:name) && expr.name
				(expr.name.is_a?(Expression) || expr.name.is_a?(Lexeme)) ? expr.name.value : expr.name
			else
				expr.value
			end
			Declaration[key, expr, expr]
		end

		# @param [Array<Prog::Expression>] expressions
		# @return [Hash{::String => Prog::Declaration}]
		def declare_all expressions
			expressions.each_with_object(Hash.new) do |expr, declarations|
				decl = declare expr
				case decl
				when nil
					# #declare returns nil for expressions that don't need to be forward declared
				when ::Hash
					# a construct that doesn't push its own scope (Conditional_Expr, Circumfix_Expr, a bare @load) hands back its own nested declarations already-collected -- flatten them into this level rather than nesting them under a made-up key
					declarations.merge! decl
				else
					Backend.assert(decl.is_a? Declaration)
					declarations[decl.key] = decl
				end
			end
		end

		# The value bound to a `:=`/`=` key -- a literal or plain identifier RHS is stored as-is instead of wrapped in a Declaration, unlike #declare itself.
		def resolve_value expr
			case expr
			when String_Expr, Number_Expr, Symbol_Expr, Identifier_Expr
				expr
			else
				declare(expr) || expr
			end
		end

		# `@load 'file'` -- a Call_Expr on `@.load` (Parser#parse_context_call).
		def load_call? expr
			r = expr.receiver
			r.is_a?(Infix_Expr) && r.operator&.value == '.' &&
				r.left.is_a?(Identifier_Expr) && r.left.value == Prog::CONTEXT_OPERATOR &&
				r.right.is_a?(Identifier_Expr) && r.right.value == 'load'
		end

		# @return [Hash{::String => Prog::Declaration}, nil]
		def declarations_for_load expr
			path_expr = expr.arguments&.first
			return nil unless path_expr.is_a? String_Expr

			loaded = cached_declarations_for_load path_expr.value

			# Every name this @load brings in gets rebound to point at *this* @load directive
			# itself, not the isolated node #cached_declarations_for_load found it on in the other
			# file. A loaded file's own declarations aren't independent of each other (`Div | Dom
			# {}` needs `Dom` too, a method calls other things declared alongside it, ...), so
			# forcing just one of them in isolation isn't enough -- it has to bring in the whole
			# file, exactly as if the interpreter had reached this line for real. This also means
			# forcing any single name correctly marks the whole @load as forced, so #output's own
			# walk doesn't redundantly run it a second time once it reaches this line for real.
			loaded.transform_values { |decl| Declaration[decl.key, decl.expr_or_decl, expr] }
		end

		# @param [::String] filepath
		# @return [Hash{::String => Prog::Declaration}]
		def cached_declarations_for_load filepath
			filepath = self.class.resolve_load_filepath filepath
			return Hash.new if self.class.currently_loading_filepaths.include? filepath

			cached = self.class.cached_declarations_by_filepath[filepath]
			return cached if cached

			expressions = Backend::Interpreter.cached_expressions_by_filepath[filepath] ||
			              Parser.new(Lexer.new(::File.read(filepath)).output).output

			self.class.currently_loading_filepaths << filepath
			declared = Declarator.new(expressions).output
			self.class.currently_loading_filepaths.delete filepath

			self.class.cached_declarations_by_filepath[filepath] = declared
		rescue Errno::ENOENT
			Hash.new # missing/unreadable file -- not this pass's job to raise; the real @load will, once actually reached
		end

		# @param [Prog::Expression] expr to declare
		# @return [Prog::Declaration, Hash, nil]
		def declare expr
			case expr
			when Param_Expr
				Declaration[expr.name&.value, expr.default ? resolve_value(expr.default) : nil, expr]
			when Route_Expr
				route_key = "#{expr.http_method.value}:#{expr.path}" # stolen from Interpreter#interp_route
				nested    = declare_all [expr.expression]
				Declaration[route_key, nested, expr]
			when Func_Expr
				if expr.name
					nested = declare_all expr.expressions
					Declaration[expr.name.value, nested, expr]
				end
			when Func_Signature_Expr
				# a return-type-only declaration (`double: (Number -> Number;)`) has params but no real body -- same shape as Func_Expr otherwise, just declaring the params instead
				if expr.name
					Declaration[expr.name.value, declare_all(expr.params), expr]
				end
			when Struct_Expr
				if expr.name
					to_decl expr
				end
			when Type_Expr
				# nested = every declaration found in the type's own body, keyed the same way #output keys its top-level result -- the tag (if any) rides along under its own key..expressions is nil for a bare reference (`Abc\<Number>`, `Named <String, Number>`) with no `{}` body at all -- distinct from a real, even if empty, body
				nested        = expr.expressions ? declare_all(expr.expressions) : Hash.new
				nested['tag'] = declare expr.tag if expr.tag
				Declaration[expr.name, nested, expr]
			when Number_Expr, Symbol_Expr, String_Expr
				# a bare literal statement (e.g. a func body's trailing return value) doesn't declare anything on its own -- see #resolve_value for how these register as the *value* on the right of a `:=`/`=`
			when Prefix_Expr, Postfix_Expr
				# operator application on a value (`-x`, `!x`) -- never declares anything itself
			when Nil_Init_Expr
				Declaration[expr.left.value, expr.right, expr]
			when Infix_Expr
				case expr.operator.value
				when ':=', '='
					Declaration[expr.left.value, resolve_value(expr.right), expr]
				end
			when Percent_Literal_Expr
				# %string(...)/%symbol(...) is a flat list of literal items, never declarations
			when Circumfix_Expr
				# a grouping ((...), [...], {...}) doesn't push its own scope -- a `:=`/`=` among its items lands in the enclosing scope, same reasoning as Conditional_Expr below
				declare_all expr.expressions
			when Operator_Expr
				to_decl expr
			when Operator_Overload_Expr
				to_decl expr
			when Identifier_Expr
				# a bare identifier reference (e.g. a func body's trailing return value) reads a value, it doesn't declare one -- #declare_all's `if decl` already tolerates nil fine, no self-referential Declaration needed here. Registering one was actively wrong: a bare reference appearing *after* the real declaration of the same name (e.g. `x := 1` followed later by a bare `x` in a tuple/return value) would silently clobber it in #declare_all's Hash, since both share the same key.
			when Composition_Expr
				# references an already-declared type via composition (`| Other`) -- doesn't declare one
			when Conditional_Expr
				# if/unless/while/until don't push their own scope (unlike For_Loop_Expr below), so a `:=` inside a branch really does land in the enclosing scope -- flatten rather than nest under a made-up key. .when_false chains into another Conditional_Expr for elif/elwhile, instead of an Array, when there's a further branch to check
				when_false = expr.when_false.is_a?(Conditional_Expr) ? [expr.when_false] : expr.when_false
				declare_all [*expr.when_true, *when_false]
			when Call_Expr
				# `@load 'file'` parses as a call on `@.load` -- still forward-declares the loaded file.
				declarations_for_load(expr) if load_call?(expr)
				# every other call: arguments can themselves use `:=` for named-argument passing
				# (`add(a := 1)`), which looks identical to a real declaration but isn't one -- skip.
			when Subscript_Expr
				# `receiver[expression]` access is never a declaration
			when Array_Index_Expr
				# `receiver.0` positional access is never a declaration
			when For_Loop_Expr
				# pushes its own scope per iteration (#interp_for_loop) -- unlike Conditional_Expr, anything declared in .body is loop-local and re-created each pass, not forward-referenceable from outside the loop
			when Fence_Expr, Html_Fence_Expr
				# fenced blocks (```md, ```html, ...) is raw content, never declarations
			when Statement_Expr
				# `` `expr` `` defers its wrapped expression until called -- nothing is declared until then, so there's nothing to forward-declare here
			when Comment_Expr
				# plain comment text is never a declaration
			end
		end
	end
end
