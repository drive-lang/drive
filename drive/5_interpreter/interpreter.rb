require 'webrick'
require 'cgi'
require 'json'
require 'securerandom' # #initialize mints @live_reload_token with this

module Drive
	class Interpreter
		include Tape
		extend Cached_By_Path

		# Source lines by filepath, keyed the same way #register_source always has -- kept class-level (not per-instance) so Error_Formatter can read a snippet without holding a live Interpreter, which used to be the only reason errors.rb needed a `runtime` reference at all.
		cache_by_path :cached_source_by_filename # {filepath: [String]}

		# Parsed ASTs by resolved filepath, kept class-level (not per-instance) for the same reason: `tapes/global.tape` (and everything it transitively @loads) is immutable source, identical for every Interpreter in the process, so re-lexing/re-parsing it fresh on every `Drive.interp` call was pure waste -- it used to be instance-level, meaning a brand-new Interpreter (which every `Drive.interp` call constructs) never saw a warm cache. Doesn't cache the *interpretation* of that AST (each Interpreter still builds its own fresh Standard_Library scope from it), only the lex+parse step, so per-instance isolation (mutating a builtin in one test can't leak into another) is unaffected.
		cache_by_path :cached_expressions_by_filepath # {filepath: [Tape::Expression]}

		# Resolved filepaths whose AST has already passed type-checking at least once, kept class-level alongside the cache above. Type-checking is a pure function of the AST (no interpreter state involved) -- a cached, never-changing file that already passed once will always pass, so re-walking it on every subsequent load is pure waste, same as re-parsing was.
		cache_by_path :type_checked_filepaths # {filepath: true}

		# Raw source of runtime assets injected into every matching response (dom.js, view_transition.css) -- not Drive source, so it never goes through the lex/parse caches above. Kept class-level for the same reason: identical for every Interpreter in the process, so re-reading from disk on every request is pure waste.
		cache_by_path :cached_asset_source_by_path # {filepath: String}

		class << self
			# Lets Ruby proxy methods (no interpreter reference otherwise) reach interpreter state, e.g. #find_table_type_for_schema. Not thread-safe across multiple interpreters; fine for one-per-process.
			attr_accessor :current

			# Drops the lex/parse/type-check/asset caches above, plus Declarator's own, for the given
			# resolved paths (all of them when `paths` is nil) so a fresh Interpreter re-reads those
			# files from disk. Used by Hot_Reloader on a file change -- everything else about a reload
			# is a brand-new Interpreter, which resets all instance state on its own; these class-level
			# Hashes are the only thing that survives. Both classes extend Cached_By_Path (see
			# drive/shared/cached_by_path.rb), so this just delegates to each one's own generic reset.
			def reset_file_caches! paths = nil
				reset_cached_by_path! paths
				Drive::Declarator.reset_cached_by_path! paths
			end
		end

		attr_accessor :input, :lexer, :parser, :load_standard_library, :stack, :route_functions_by_route_name, :servers, :dom_onclick_function_handlers, :dom_input_elements, :last_output, :current_source_file, :stdlib_scope, :declarations, :global, :serve_in_foreground, :live_reload, :live_reload_token

		def initialize
			@dom_input_elements            = {} # {element_hash: Tape::Instance} for inputs/textareas
			@dom_onclick_function_handlers = {} # {handler_hash: Tape::Func}
			@route_functions_by_route_name = {} # {route: Tape::Route}

			@load_standard_library = true
			@serve_in_foreground   = true # Hot_Reloader flips this -- see #run
			@input                 = [] # [Tape::Expression]
			@stack                 = [] # [Tape::Scope]
			@servers               = [] # [Tape::Server]

			# Live reload (browser auto-refresh on save). Only Hot_Reloader turns @live_reload on, so a
			# plain `tape interpf` / production server never streams events or injects the client script.
			# @live_reload_token is unique per Interpreter instance: a hot reload builds a fresh
			# Interpreter, so the token the /_drive/live-reload stream reports changes, which is exactly
			# the "the server rebooted, refresh now" signal the browser watches for.
			@live_reload       = false
			@live_reload_token = SecureRandom.hex(8)

			@lexer               = Lexer.new
			@parser              = Parser.new
			@declarations        = {} # {::String => Tape::Declaration}, see Declarator
			@forced_declarations = ::Set.new # identity-tracked Tape::Expression, see #resolve_forward_declaration

			Interpreter.current = self
		end

		def run source_code
			top_level_source_file = current_source_file

			if @stack.empty?
				# todo; Global should be created by interping tapes/global.tape, which is what I want to rename tapes/global.tape to
				global  = Global.new
				@global = global # kept separately from @stack -- #interp_member_access temporarily swaps @stack out for dot-access resolution, so `stack.first` isn't reliably Global the way this needs
				@stack << global
				if load_standard_library
					# Stdlib lives in its own Scope, reachable via Global's readable scope -- not Global's own declarations. Reassigning a builtin can't mutate it (readable_scopes never redirects writes), just shadows locally. Composing and deliberate @push_scope reopening still work. `global` is pushed before this load so `~/` still resolves to Global while the stdlib itself loads.
					# Also held here as a real instance var, not just the WeakMap entry above -- readable/writable scope membership deliberately never keeps anything alive on its own (see CLAUDE.md), which is correct for things a caller adds and is expected to hold their own reference to elsewhere, but @stdlib_scope has no other holder anywhere. Without this, it's one GC pass away from being collected mid-program, taking the entire standard library (String, Array, everything) down with it.
					@stdlib_scope = Tape::Scope.new('Standard_Library')
					load_file_into_scope STANDARD_LIBRARY_PATH, @stdlib_scope
					global.add_readable_scope @stdlib_scope
				end
			end
			@lexer.source_file    = top_level_source_file
			@lexer.input          = source_code
			@parser.input         = @lexer.output.reject do |lexeme|
				%I(comment).include? lexeme.type # The interpreter doesn't care about these
			end
			@input                = @parser.output # Expressions

			@last_output = output
			if servers.any? { |server| server.webrick_server&.status == :Running }
				# Hot_Reloader sets this false: it owns the wait loop itself (watching files, tearing
				# servers down and rebuilding on change), so `run` must return with the servers left
				# running on their own threads instead of blocking here forever.
				serve_in_foreground ? loop_servers : @last_output
			else
				@last_output
			end
		end

		def output skip_type_check: false, skip_forward_declarations: false
			unless skip_type_check
				checker = Type_Checker.new input
				raise checker.output if checker.output
			end

			unless skip_forward_declarations
				declarator    = Declarator.new input
				@declarations = declarator.output
			end

			input.each.inject(nil) do |result, expr|
				# already ran ahead of turn via #resolve_forward_declaration -- don't run it twice. Keeping the running `result` (not a bare `next`, which resets it to nil) matters when the skipped statement is the *last* one -- the program's own reported result would otherwise silently become nil instead of the true last value.
				if @forced_declarations.include? expr
					result
				else
					interpret expr
				end
			end
		end

		# Only these expression kinds are eligible to be forward-referenced -- kept here rather than constants.rb since it references Expression subclasses (constants.rb loads before expressions.rb does)
		FORWARD_DECLARABLE_EXPRESSIONS = [Func_Expr, Type_Expr, Route_Expr, Struct_Expr, Func_Signature_Expr, Operator_Expr, Operator_Overload_Expr].freeze

		def hoistable_declaration_expr? expr
			return true if FORWARD_DECLARABLE_EXPRESSIONS.any? { |type| expr.is_a? type }
			return false unless expr.is_a?(Infix_Expr) && %w(:= =).include?(expr.operator.value)
			return true if hoistable_declaration_expr? expr.right

			# `Ident := @load 'file'` / `IDENT := @load 'file'` -- a named load builds a scope of its own, same declarative category as `This := That {}` above. Only a Capitalized/UPPERCASE left-hand name opts in, matching Drive's own casing convention for a namespace-like binding -- a lowercase `mod := @load 'file'` stays a plain variable, not hoisted
			load_call_expr?(expr.right) &&
				%i(Identifier IDENTIFIER).include?(Drive.type_of_identifier(expr.left.value))
		end

		# A bare `@load 'file'` (no assignment) merges directly into the current scope -- always hoistable, no casing concept applies since there's no left-hand name to check. Kept separate from #hoistable_declaration_expr?'s recursive `:=`/`=` unwrap so this can't accidentally leak permissiveness into the *named* load case, which is deliberately restricted to a Capitalized/UPPERCASE left-hand name.
		def bare_load_call_expr? expr
			load_call_expr? expr
		end

		# `@load 'file'` -- parses as a Call_Expr on `@.load` (see Parser#parse_context_call).
		def load_call_expr? expr
			return false unless expr.is_a?(Tape::Call_Expr)
			r = expr.receiver
			r.is_a?(Tape::Infix_Expr) && r.operator&.value == '.' &&
				r.left.is_a?(Tape::Identifier_Expr) && r.left.value == Tape::CONTEXT_OPERATOR &&
				r.right.is_a?(Tape::Identifier_Expr) && r.right.value == 'load'
		end

		# @param [::String] name
		# @return [::Boolean] whether a declaration was found and forced
		def resolve_forward_declaration name
			decl = @declarations[name]
			return false unless decl&.expr
			return false unless hoistable_declaration_expr?(decl.expr) || bare_load_call_expr?(decl.expr)
			return false if @forced_declarations.include? decl.expr

			@forced_declarations << decl.expr
			push_then_pop global do
				interpret decl.expr
			end
			true
		end

		def loop_servers
			begin
				keep_running = true

				trap_fn = Proc.new do
					puts Tape::Ascii.dim "Shutting down..."
					keep_running = false
					puts "\n\s\s(V) (;,,;) (V)"
					Thread.main.exit
				end
				Signal.trap 'INT', trap_fn
				Signal.trap 'TERM', trap_fn

				while keep_running
					@servers.each do |server|
						puts "Drive Server `#{server.name}` started at http://localhost:#{server.port}"
						server.server_thread&.join
					end
				end
			ensure
				shutdown_all_servers
			end
		end

		# Stops every running server and empties the list. Safe with no servers. Shared by
		# #loop_servers own teardown and by Hot_Reloader between reload cycles.
		def shutdown_all_servers
			@servers.each { |server| stop_server server }
			@servers.clear
		end

		# Preserves its @input, interprets given file, then restores its @input.
		# @param [::String] filepath of the code to load
		# @param [Tape::Scope] scope to load code into
		# @return The output of the interpreted file
		def load_file_into_scope filepath, into_scope
			filepath.insert(-1, '.tape') unless filepath.end_with? '.tape' # note; I feel like this isn't the smartestest way to achieve this.

			resolved_path = if filepath.start_with? 'tapes/'
				File.join ROOT_PATH, filepath
			else
				File.expand_path filepath
			end

			# This filepath may have been loaded in the given scope already. We don't want to double load it -- return the same result it produced the first time instead of re-running it (or, without this, silently returning nil).
			return into_scope.loaded_filepaths[resolved_path] if into_scope.loaded_filepaths.key? resolved_path

			cached_expressions   = self.class.cached_expressions_by_filepath[resolved_path]
			already_type_checked = self.class.type_checked_filepaths[resolved_path]

			unless cached_expressions
				code = File.read resolved_path
				register_source resolved_path, code
				@lexer.source_file = resolved_path
				@lexer.input       = code
				@parser.input      = @lexer.output.reject do |lexeme|
					%I(comment).include? lexeme.type
				end
				cached_expressions = self.class.cached_expressions_by_filepath[resolved_path] = @parser.output
			end

			push_scope into_scope

			saved_declarations                               = @declarations
			saved                                            = @input
			@input                                           = cached_expressions
			result                                           = output skip_type_check: already_type_checked
			self.class.type_checked_filepaths[resolved_path] = true # todo; This should be done by #output probably
			@input                                           = saved
			@declarations                                    = saved_declarations

			into_scope.loaded_filepaths[resolved_path] = result
			Drive.assert pop_scope.equal? into_scope

			result
		end

		def push_scope scope
			scope ||= stack.last
			stack << scope
		end

		def pop_scope
			if stack.length == 1
				stack.last
			else
				stack.pop
			end
		end

		def push_then_pop scope
			raise "Attempting to push `nil` value as scope" if scope == nil
			push_scope scope
			yield scope if block_given?
			pop_scope
		end

		def register_source filepath, source_code
			resolved = filepath ? File.expand_path(filepath) : '<inline>'

			self.class.cached_source_by_filename[resolved] = source_code.lines.map(&:chomp)
			@current_source_file                           = resolved
		end

		def add_onclick_handler handler, render_scope, element_key = nil
			token = next_render_token(render_scope, element_key)
			# Stored with the component this render pass belongs to (`render_scope[:component]`, the nearest html_id-bearing Dom instance) so #handle_request re-renders *that* on a click. The handler's own closure is captured lexically and runs correctly wherever it was written. A `.map` callback, a plain helper, a method, so "which component to swap" no longer depends on the handler's scope chain reaching an Instance.
			dom_onclick_function_handlers[token] = { handler: handler, component: render_scope[:component] }
			token
		end

		def add_input_element instance, render_scope, element_key = nil
			token                     = next_render_token(render_scope, element_key)
			dom_input_elements[token] = instance
			token
		end

		# One stable, deterministic token per rendered element, within a component's render pass. The
		# same component rendered against the same tree shape yields the same tokens every time -- so a
		# re-render (or a fresh request for the same page) overwrites the handler/input map entries in
		# place instead of minting new random ones and growing the maps without bound. It also
		# means a handler defined in render() keeps a stable data-drive-onclick across DOM swaps, which
		# is what let handlers move out of new() and into render(). `render_scope` is `{ anchor:, slot: }`
		# seeded in #render_dom_to_html; the slot counter advances in depth-first render order.
		#
		# An `element_key` (the element's own `key := '...'`, see tapes/html.tape) pins the token by
		# name instead of position and does not touch the slot counter -- so a conditional element
		# appearing or vanishing between renders can't shift its siblings' tokens.
		def next_render_token render_scope, element_key = nil
			return "#{render_scope[:anchor]}-#{element_key}" if element_key

			slot                = render_scope[:slot]
			render_scope[:slot] = slot + 1
			"#{render_scope[:anchor]}-#{slot}"
		end

		def scope_for_identifier expr
			unless expr.is_a? Tape::Identifier_Expr
				return stack.last
			end

			case expr.scope_operator&.value
			when 'Global' # the global scope
				global
			when 'Self' # the enclosing type -- where statics live (`Self.count`)
				stack.reverse_each.find do |scope|
					scope.instance_of? Tape::Type
				end
			when 'self' # the enclosing instance
				current_instance
			else
				# If no scope operator, search through all scopes to find the identifier
				found_scope = nil
				stack.reverse_each do |scope|
					if scope.has?(expr.value) || scope.respond_to?("proxy_#{expr.value}")
						found_scope = scope
						break
					elsif scope.is_a?(Tape::Instance) && scope.enclosing_scope&.has?(expr.value)
						# Method exists on the Type - return the instance as the scope so lookups happen in instance context
						found_scope = scope
						break
					end
				end
				found_scope
			end
		end

		def maybe_instance expr
			# todo, when String and so on, because everything needs to be some type of scope to live inside the runtime. Every object in Tape::Scope.declarations{} is either a primitive like String, Integer, Float, or they're an instanced version like Tape::Number.
			case expr
			when ::Integer, ::Float, ::BigDecimal
				# Tape::Number_Expr is already handled in #interpret but this is short-circuiting that for cases like 1.something where we have to make sure the 1 is no longer a numeric literal, but instead a runtime object version of the number 1. The Ruby class of the already-evaluated value picks the matching Drive numeric type (Ruby's own Integer/Float/Rational tower, minus Rational for now). `Integer`/`Float` are bare here (not `::`) on purpose -- they mean `Tape::Integer`/`Tape::Float`.
				tape_class, type_name = case expr
				when ::Integer then [Tape::Integer, 'Integer']
				when ::Float then [Tape::Float, 'Float']
				when ::BigDecimal then [Tape::Decimal, 'Decimal']
				end

				finish_intrinsic_instance tape_class.new(expr), type_name
			when ::String
				finish_intrinsic_instance Tape::String.new(expr), 'String'
			when ::Array
				finish_intrinsic_instance Tape::Array.new(expr), 'Array'
			when ::Hash
				finish_intrinsic_instance Tape::Dictionary.new(expr), 'Dictionary'
			when Tape::Set
				finish_intrinsic_instance expr, 'Set'
			when Tape::Range
				finish_intrinsic_instance expr, 'Range'
			when true
				finish_intrinsic_instance Tape::Bool.truthy, 'Bool'
			when false
				finish_intrinsic_instance Tape::Bool.falsy, 'Bool'
			when nil
				adopt_type Tape::Nil.new, 'Nil'
			else
				expr
			end
		end

		def finish_intrinsic_instance instance, type_name
			instance.name = type_name
			adopt_type instance, type_name
		end

		def link_instance_to_type instance, type_name
			global_scope = stack.first
			if global_scope.has? type_name
				instance.enclosing_scope = global_scope[type_name]
			end
		end

		def adopt_type instance, type_name
			link_instance_to_type instance, type_name
			instance.types = instance.enclosing_scope ? instance.enclosing_scope.types : ::Set[type_name]
			instance
		end

		def prefix_type scope, name
			scope.types = ::Set[name] + scope.types
			scope
		end

		def context_for scope
			scope.context ||= begin
				instance = Tape::Context.new scope
				link_instance_to_type instance, 'Context'
				# `Context` is always a stdlib global -- fall back to it directly, since `context_for` also
				# runs mid dot-access resolution (`x.@`), when `stack` is narrowed to just the receiver and
				# `find_in_stack` can't see it. Missing it there built a context with no data members.
				decl           = find_in_stack('Context') || (global.has?('Context') ? global['Context'] : nil)
				instance.types = decl.types if decl.respond_to?(:types) && decl.types
				fill_context instance, scope, decl
				instance
			end
		end

		def fill_context instance, scope, decl
			data_members = (decl.respond_to?(:names) && decl.names&.compact || []) - Tape::Context::FUNCTIONS

			set_of = ->(list) { finish_intrinsic_instance(Tape::Set.new.tap { |s| s.set.merge(list) }, 'Set') }
			name   = scope.name.is_a?(Tape::Lexeme) ? scope.name.value : scope.name

			# todo; This is a mess. Pick a better way to organize this.
			# todo; Add these values to the Context
			# - arguments  when function scope (given by user)
			# - parameters when function scope (declared at function)

			values = {
				'name'                => name,
				'display_name'        => (scope.display_name if scope.respond_to?(:display_name)) || name,
				'composed_types'      => set_of.call(scope.respond_to?(:types) && scope.types ? scope.types.to_a : []),
				'types'               => context_types_for(scope),
				'type'                => context_type_for(scope),
				'object_id'           => scope.object_id,
				'size_in_bytes'       => ObjectSpace.memsize_of(scope),
				'root_path'           => Drive::ROOT_PATH,
				'static_declarations' => set_of.call(scope.respond_to?(:static_declarations) && scope.static_declarations ? scope.static_declarations.to_a : []),
				'names'               => (wrap_tape_array(scope.names) if scope.is_a?(Tape::Struct)),
				'type_names'          => (wrap_tape_array(scope.type_names) if scope.is_a?(Tape::Struct)),
				'values'              => context_values_for(scope),
				'members'             => (scope.members if scope.is_a?(Tape::Struct)),
				'keys'                => (wrap_tape_array(scope.enum_keys) if scope.is_a?(Tape::Enum)),
				'count'               => (scope.enum_keys.length if scope.is_a?(Tape::Enum)),
				'parameters'          => (wrap_tape_array(scope.parameters) if scope.is_a?(Tape::Func)),
				'arguments'           => (wrap_tape_array(scope.arguments) if scope.is_a?(Tape::Func)),
				'func_signature'      => (scope.func_signature if scope.is_a?(Tape::Func)),
			}

			data_members.each { |member| instance.declare member, values[member] }
			Tape::Context::FUNCTIONS.each do |fn|
				result = synthesized_context_func(fn, instance)
				instance.declare fn, result
			end
		end

		def context_types_for scope
			return wrap_tape_array(scope.type_objects) if scope.is_a?(Tape::Struct)
			return wrap_tape_array(scope.enum_types) if scope.is_a?(Tape::Enum)
			wrap_tape_array(scope.respond_to?(:types) && scope.types ? scope.types.to_a : [])
		end

		def context_type_for scope
			return scope.type_objects&.first if scope.is_a?(Tape::Struct)
			return scope.enum_type if scope.is_a?(Tape::Enum)
			(scope.types&.first if scope.respond_to?(:types)) || scope.class.name.split('::').last
		end

		def context_values_for scope
			return wrap_tape_array(scope.enum_values) if scope.is_a?(Tape::Enum)
			wrap_tape_array(scope.values) if scope.is_a?(Tape::Struct)
		end

		# A callable stand-in for a Context function member (`@puts`, `@push_scope`, ...)
		def synthesized_context_func member, enclosing
			func                       = Tape::Func.new Tape::Lexeme.new(:identifier, member)
			func.name                  = Tape::Lexeme.new :identifier, member
			func.context_function_name = member
			func.parameters            = []
			func.expressions           = []
			func.enclosing_scope       = enclosing
			func.func_signature        = Tape::Func_Signature.new [], nil
			func
		end

		def track_static_declaration scope, ident_expr
			return unless ident_expr.is_a?(Tape::Identifier_Expr) && ident_expr.scope_operator&.value == 'Self'
			scope.static_declarations ||= ::Set.new
			scope.static_declarations.add ident_expr.value.to_s
		end

		def current_instance
			stack.reverse_each.find { |scope| scope.is_a? Tape::Instance }
		end

		def check_dot_access_permissions! scope, ident, expr
			binding = Drive.binding_of_ident scope, ident
			privacy = Drive.privacy_of_ident ident

			case scope
			when Tape::Instance
				if privacy == :private && !current_instance.equal?(scope)
					raise Tape::Cannot_Call_Private_Instance_Member.new(expr)
				end
			when Tape::Type
				if binding == :instance
					# todo: This does not print the correct code location, here is a paste of the output:
					#       Cannot_Call_Instance_Member_On_Type
					#       :1:1
					raise Tape::Cannot_Call_Instance_Member_On_Type.new(expr)
				elsif privacy == :private
					raise Tape::Cannot_Call_Private_Static_Member_On_Type.new(expr)
				end
			end
		end

		def find_ruby_class_for_type type
			candidates = type.types.filter_map do |type_name|
				tape_name = "Tape::#{type_name}"
				next unless Object.const_defined? tape_name
				k = Object.const_get tape_name
				k if k.is_a?(Class) && k < Tape::Instance && k != Tape::Instance
			end

			# Most-derived wins: `Integer | Number {}` matches both Tape::Integer and Tape::Number, and
			# we want Tape::Integer (its `value=` coerces via `to_i`). Longest ancestor chain = deepest
			# subclass. Unrelated candidates (no shared lineage) just pick one deterministically.
			candidates.max_by { |k| k.ancestors.size }
		end

		def truthy? value
			!!value
			# note; I originally thought a model mixing Ruby and systems languages would be neat but that's tabled for later when I port this to a systems language. I'm just gonna let Ruby dictate truthiness for now. My idea was to make 0 falsy but that means a function that returns an index 0, may be considered false as a conditional.
			# case value
			# when nil, false
			# 	false
			# when Numeric
			# 	!value.zero?
			# else
			# 	true
			# end
		end

		def type_name_to_string value
			case value
			when Tape::Integer then 'Integer'
			when Tape::Float then 'Float'
			when Tape::Decimal then 'Decimal'
			when Tape::Number then 'Number'
			when ::Integer then 'Integer'
			when ::Float then 'Float'
			when ::BigDecimal then 'Decimal'
			when Tape::String then 'String'
			when Tape::Array then 'Array'
			when Tape::Range then 'Range'
			when Tape::Dictionary then 'Dictionary'
			when Tape::Bool then 'Bool'
			when Tape::Instance then value.types.first
			when Tape::Type then value.name
			# todo: Why are these here? Excluding the else clause
			when true, false then 'Bool'
			when ::String then 'String'
			when ::Array then 'Array'
			when ::Hash then 'Dictionary'
			else nil
			end
		end

		NUMERIC_TYPE_NAMES = %w[Number Integer Float Decimal].freeze

		# The type name to *record* for an identifier on `:=` (and self-declaring `.member :=`). Numeric
		# values collapse to the family name `Number` rather than the leaf (`Integer`/`Float`/...), so an
		# inferred lock stays lenient the way it always has -- `sum := 0` then `sum = 1.5` still works.
		# An explicit `: Integer` annotation is recorded verbatim elsewhere and stays strict.
		def inferred_type_name value
			name = type_name_to_string value
			NUMERIC_TYPE_NAMES.include?(name) ? 'Number' : name
		end

		# Does `value` satisfy a `: Type` contract named `expected`? Compositional (`=>=`-style): an
		# `Integer` satisfies `: Number`, a `Fence` satisfies `: String`. `Any` matches anything, and
		# `nil` -- the universal unset value every typed slot starts as -- satisfies any contract.
		def type_contract_satisfied? value, expected
			return true if expected.nil? || expected == 'Any'
			return true if value.nil? || value.is_a?(Tape::Nil)
			return true if type_name_to_string(value) == expected

			value_types = composed_types_for value
			return true if value_types.include? expected

			# `expected` may be an alias (`Int := Integer`, `Dec := Decimal`) -- its own name isn't in
			# the real type's composed set, so resolve it and accept when the value composes everything
			# that type does (same `=>=` check the `===` operators use).
			expected_types = composed_types_by_name expected
			expected_types.any? && expected_types.subset?(value_types)
		end

		def composed_types_for value
			case value
			when Tape::Type
				value.types
			else
				# Covers backings (Number/String/Array/Dictionary/Bool) and anything else -- neither needs special handling, both resolve by name.
				composed_types_by_name type_name_to_string(value)
			end
		end

		def composed_types_by_name name
			return ::Set.new unless name
			global = stack.first
			global.has?(name) ? global[name].types : ::Set[name]
		end

		# Does `a` (composed types + struct members) carry at least everything `b` does? Shared by `=>=`/`=<=`/`===`/`=!=` -- see #interp_comparison_infix.
		def superset_of_types_and_tag? a_types, a_tag, b_types, b_tag
			types_superset   = b_types.all? { |type| a_types.include? type }
			members_superset = (b_tag || []).all? { |member| (a_tag || []).include? member }
			types_superset && members_superset
		end

		# If `name` is already an Tape::Func_Signature, return it as-is (an inline signature has no name to look up). Otherwise, if it's bound to one anywhere on the stack, return that. Otherwise nil — meaning `name` is an ordinary nominal type name (e.g. 'Number').
		def resolve_func_signature name
			return name if name.is_a? Tape::Func_Signature
			return nil unless name
			value = find_in_stack name
			value.is_a?(Tape::Func_Signature) ? value : nil
		end

		# @param expr [Tape::Func_Signature_Expr]
		def build_func_signature expr
			param_types = expr.params.map { |param| param.type&.value }
			Tape::Func_Signature.new param_types, expr.type&.value
		end

		# Readable description of a value's shape for Type_Contract_Violation messages — a func-like value's param/return types if it has them, otherwise its plain type name.
		def describe_value_shape value
			if value.respond_to? :func_signature
				value.func_signature.to_s
			else
				type_name_to_string(value) || 'unknown'
			end
		end

		def start_server server
			ready = Queue.new

			webrick = WEBrick::HTTPServer.new Port:          server.port,
			                                  Logger:        WEBrick::Log.new("/dev/null"),
			                                  AccessLog:     [],
			                                  StartCallback: -> { ready << true }

			webrick.mount_proc '/onclick/' do |req, res|
				puts Tape::Ascii.dim "#{'DOM'.rjust(7, ' ')} #{req.path}"
				handle_request server, req, res
			end

			# Live reload event stream (see drive/5_interpreter/live_reload.js). Mounted only under Hot_Reloader,
			# and separately from the Drive routing path -- a Drive route handler resolves to a finished
			# String body, but this needs to hold the connection open and stream, which means raw WEBrick
			# response access.
			if live_reload
				webrick.mount_proc '/_drive/live-reload' do |_req, res|
					res.status           = 200
					res['Content-Type']  = 'text/event-stream'
					res['Cache-Control'] = 'no-cache'
					res.chunked          = true # no Content-Length possible; emit one chunk per write
					token                = live_reload_token

					res.body = proc do |out|
						out.write "retry: 300\n\n" # how long EventSource waits before reconnecting
						out.write "data: #{token}\n\n" # the only line the client actually keys on

						# Heartbeat. Its real jobs: (1) a write eventually raises once the browser tab
						# closes, freeing this thread; (2) the status check ends the thread promptly when
						# Hot_Reloader shuts this server down -- WEBrick doesn't track or join per-request
						# worker threads, so without this poll the thread would leak on every reload.
						while webrick.status == :Running
							sleep 0.5
							out.write ": ping\n\n" # SSE comment line -- ignored by the client
						end
					rescue Errno::EPIPE, IOError
						# browser tab went away mid-stream -- expected, nothing to clean up
					end
				end
			end

			webrick.mount_proc '' do |req, res|
				handle_request server, req, res
			end

			server.webrick_server = webrick
			server.server_thread  = Thread.new do
				webrick.start
			rescue => e
				ready << e
			end

			# Thread.new returns before the new thread has run at all, so reading .status right after this would race WEBrick's own startup and almost always see :Stop. Block until StartCallback actually fires (or the thread dies trying) instead.
			result = ready.pop
			raise result if result.is_a? Exception

			server.server_thread
		end

		def stop_server server
			server.webrick_server&.shutdown
			# Let WEBrick's accept loop actually return (and release the listening socket) before
			# forcing the thread down -- otherwise a quick restart on the same port can hit EADDRINUSE.
			server.server_thread&.join(3)
			server.server_thread&.kill
		end

		def handle_request server, request, response
			path_string  = request.path
			query_string = request.query_string
			http_method  = request.request_method.downcase
			path_parts   = request.path.split('/').reject { _1.empty? }

			# CGI.parse only understands application/x-www-form-urlencoded bodies (key1=value1&key2=...).
			# A JSON body has no top-level `=` for it to split on, so it used to fall back to treating the
			# *entire* raw JSON string as one keyless entry with zero values -- `{ "<the whole json>" => nil
			# }`, both in this debug log line and in `request.body` as seen by every Drive route/onclick
			# handler. Real JSON bodies now get real JSON parsing instead.
			body_hash = if request.content_type&.start_with?('application/json')
				JSON.parse(request.body || '{}') rescue {}
			else
				CGI.parse(request.body || "").transform_values(&:first)
			end

			# Dictionary subscripts always normalize to a Symbol key, but these sources are String-keyed -- double-key both, like query_params/url_params below already do.
			body_hash    = double_key_with_symbols body_hash
			headers_hash = double_key_with_symbols request.header.to_h

			req_info = Ascii.dim ""
			unless body_hash.empty?
				req_info = req_info.prepend Ascii.green
			end
			req_info << Ascii.dim(http_method.upcase.rjust(7, " "))
			req_info << " "
			req_info << Ascii.reset(path_string.gsub("/", "#{Ascii.dim('/')}#{Ascii.reset}"))
			unless body_hash.empty?
				req_info << " #{Ascii.dim body_hash}"
			end
			puts req_info

			if path_string.start_with?("/onclick/")
				# object_id/element_id are string tokens (`"<anchor>-<slot>"`, see #next_render_token), not
				# integers -- no `.to_i` (that silently truncated a token down to its leading digits, so
				# every real click 404'd: the truncated id never matched anything actually registered).
				object_id = path_parts.last
				entry     = dom_onclick_function_handlers[object_id]
				if entry
					begin
						if request.body && !request.body.empty?
							json_body = JSON.parse request.body rescue {}
							inputs = json_body['inputs'] || {}
							inputs.each do |element_id, value|
								input_instance = dom_input_elements[element_id]
								input_instance.declare 'value', value if input_instance
							end
						end

						route             = Tape::Route.new
						route.handler     = entry[:handler]
						route.param_names = []

						req = build_tape_request path_string, http_method, body_hash, parse_query_string(query_string), {}, headers_hash
						res = build_tape_response response

						interp_route_body route, req, res

						# The component to re-render was recorded when the handler's token was minted, during
						# the render walk (#add_onclick_handler) -- no scope-chain reconstruction needed, so a
						# handler defined in a `.map` callback or a plain helper works the same as one in a
						# method.
						component = entry[:component]
						if component.is_a?(Tape::Instance) && component.declarations['render']
							new_html = render_dom_to_html component
							html_id  = component.declarations['html_id']

							response.status              = 200
							response['Content-Type']     = 'text/html'
							response['X-Drive-Target-Id'] = html_id if html_id
							response.body                = new_html
							return
						end
					rescue => e
						warn "\n[Drive Onclick Error] #{e.class}: #{e.message}"
						warn e.backtrace.first(10).map { |line| "  #{line}" }.join("\n")
						warn ""

						plain_message   = e.message.gsub(/\e\[\d+(?:;\d+)*m/, '')
						response.status = 500
						response.body   = "Internal Server Error\n#{plain_message}"
						return
					end
				end
			end

			if cookie = request.cookies.find { _1.name == BROWSER_VIEW_SIZE }
				parts = cookie.value.split 'x'
				size  = { width: parts[0].to_i, height: parts[1].to_i }
				stack.last.declare BROWSER_VIEW_SIZE, size
			end

			route_function = match_route http_method, path_parts, server.routes

			if route_function
				url_params   = extract_url_params path_parts, route_function
				query_params = parse_query_string query_string

				req = build_tape_request path_string, http_method, body_hash, query_params, url_params, headers_hash

				begin
					res    = build_tape_response response
					result = interp_route_body route_function, req, res, url_params, server_instance: server

					response.status = res.declarations['status']
					response.body   = res.declarations['body']
					res.declarations['headers'].each { |k, v| response.header[k] = v }

					if response.body.to_s =~ /<html|<body|<head/i
						response.body.prepend "<!DOCTYPE html>"

						dom_js              = self.class.cached_asset_source_by_path['drive/5_interpreter/dom.js'] ||= File.read('drive/5_interpreter/dom.js')
						script_tag          = "<script>#{dom_js}</script>"
						view_transition_css = self.class.cached_asset_source_by_path['drive/5_interpreter/view_transition.css'] ||= File.read('drive/5_interpreter/view_transition.css')
						view_transition_tag = "<style>#{view_transition_css}</style>"

						# Only present under Hot_Reloader -- pairs with the /_drive/live-reload endpoint.
						live_reload_tag = if live_reload
							lr_js = self.class.cached_asset_source_by_path['drive/5_interpreter/live_reload.js'] ||= File.read('drive/5_interpreter/live_reload.js')
							"<script>#{lr_js}</script>"
						else
							''
						end

						injected = script_tag + view_transition_tag + live_reload_tag
						body_str = response.body.to_s

						if body_str.include?('<head>')
							response.body = body_str.sub('<head>', '<head>' + injected)
						elsif body_str.include?('<body>')
							response.body = body_str.sub('<body>', '<body>' + injected)
						else
							response.body = injected + body_str
						end
					end

					result

				rescue WEBrick::HTTPStatus::Status => e
					raise e

				rescue => e
					warn "\n[Drive Server Error] #{e.class}: #{e.message}"
					warn e.backtrace.first(10).map { |line| "  #{line}" }.join("\n")
					warn ""

					plain_message   = e.message.gsub(/\e\[\d+(?:;\d+)*m/, '')
					plain_backtrace = e.backtrace.map { |line| line.gsub(/\e\[\d+(?:;\d+)*m/, '') }

					response.status = 500
					response.body   = <<~HTML
					    <h1>500 Internal Server Error</h1>
					    <h2>#{e.class}</h2>
					    <pre>#{plain_message}</pre>
					    <h3>Backtrace</h3>
					    <pre>#{plain_backtrace.join("\n")}</pre>
					HTML
					response.header['Content-Type'] = 'text/html; charset=utf-8'
				end
			else
				response.status = 404
				response.body   = <<~HTML
				    <h1>404 Not Found</h1>
				    <p>No route matches #{http_method.upcase} #{path_string}</p>
				    <hr>
				    <h3>Available Routes:</h3>
				    <ul>
				    	#{server.routes.values.map { |r| "<li>#{r.http_method.value.upcase} /#{r.path}</li>" }.join("\n")}
				    </ul>
				HTML
				response.header['Content-Type'] = 'text/html; charset=utf-8'
			end
		end

		def match_route http_method, path_parts, routes
			candidates = routes.values.select do |route|
				next false unless route.http_method.value == http_method
				next false unless route.parts.count == path_parts.count

				path_parts.zip(route.parts).all? do |req_part, route_part|
					(req_part == route_part) || (route_part.start_with?(':'))
				end
			end

			# A route that matches every segment literally beats one that leaned on a `:param` placeholder,
			# regardless of declaration order -- so `get://favicon.ico` wins over `get://:id` for
			# `/favicon.ico`. Fewest `:param` segments wins; #min_by keeps the first on a tie.
			candidates.min_by { |route| route.parts.count { |part| part.start_with?(':') } }
		end

		# Stores each entry under both its String and Symbol form, like #extract_url_params/#parse_query_string already do by hand.
		def double_key_with_symbols hash
			hash.each_with_object({}) do |(key, value), result|
				result[key]        = value
				result[key.to_sym] = value if key.respond_to? :to_sym
			end
		end

		def extract_url_params path_parts, route
			url_params = {}
			path_parts.zip(route.parts).each do |req_part, route_part|
				if route_part.start_with? ':'
					param_name                    = route_part[1..-1]
					url_params[param_name]        = req_part
					url_params[param_name.to_sym] = req_part
				end
			end
			url_params
		end

		def parse_query_string query_string
			query_params = {}
			if query_string
				query_string.split('&').each do |pair|
					key, value               = pair.split '=', 2
					query_params[key]        = CGI.unescape(value || '')
					query_params[key.to_sym] = CGI.unescape(value || '')
				end
			end
			query_params
		end

		def build_tape_request path_string, http_method, body_hash, query_params, url_params, headers_hash
			req          = Tape::Request.new
			body_dict    = Tape::Dictionary.new body_hash
			query_dict   = Tape::Dictionary.new query_params
			params_dict  = Tape::Dictionary.new url_params
			headers_dict = Tape::Dictionary.new headers_hash
			link_instance_to_type req, 'Request'
			link_instance_to_type body_dict, 'Dictionary'
			link_instance_to_type query_dict, 'Dictionary'
			link_instance_to_type params_dict, 'Dictionary'
			link_instance_to_type headers_dict, 'Dictionary'
			req.declarations['path']              = path_string
			req.declarations['method']            = http_method
			req.declarations['query']             = query_dict
			req.declarations['params']            = params_dict
			req.declarations['headers']           = headers_dict
			req.declarations['body']              = body_dict
			req.declarations['body'].declarations = body_hash
			req
		end

		def build_tape_response webrick_response
			res                                  = Tape::Response.new
			res.webrick_response                 = webrick_response
			res.declarations['webrick_response'] = webrick_response
			res.declarations['status']           = 200
			res.declarations['headers']          = {}
			res.declarations['body']             = ''
			link_instance_to_type res, 'Response'
			res
		end

		def collect_routes_from_instance instance
			collected_routes = {}

			# This iterates composed types to find any
			instance.types.each do |type_name|
				composed_type = stack.first.get type_name
				next unless composed_type && composed_type.respond_to?(:routes) && composed_type.routes

				# Merge routes from this type
				composed_type.routes.each do |key, route|
					collected_routes[key] ||= route
				end
			end

			collected_routes
		end

		def render_dom_to_html dom_instance, render_scope: nil
			# A component with its own html_id (a page-level component) anchors a fresh token namespace
			# for its whole subtree, keyed by that stable id. A top-level component with no html_id
			# falls back to its object_id. Nested id-less elements just keep counting within the
			# enclosing component's namespace -- see #next_render_token.
			own_html_id = dom_instance.declarations['html_id']
			if render_scope.nil?
				render_scope = { anchor: own_html_id || "auto#{dom_instance.object_id}", slot: 0, component: dom_instance }
			elsif own_html_id
				render_scope = { anchor: own_html_id, slot: 0, component: dom_instance }
			end

			render = dom_instance.declarations['render']

			inner_html = if render
				call_expr           = Tape::Call_Expr.new
				call_expr.receiver  = render
				call_expr.arguments = []

				render_result = interp_func_body render, call_expr
				html          = +'' # unfrozen -- append_dom_child_html mutates it in place
				append_dom_child_html render_result, html, render_scope
				html
			end

			renderer = Drive::Dom_Renderer.new dom_instance, inner_html

			# Registration (here) and rendering (renderer.to_html_string) must print the *same* token --
			# add_onclick_handler/add_input_element return the real key they stored, so hand it to the
			# renderer instead of letting it mint its own.
			element_key = dom_instance.declarations['key']

			if renderer.onclick_expr
				renderer.onclick_token = add_onclick_handler renderer.onclick_expr, render_scope, element_key
			end

			if renderer.is_input_element?
				renderer.input_id_token = add_input_element dom_instance, render_scope, element_key
			end

			renderer.to_html_string
		end

		# A render() result can be a String, a single Dom-composing Instance, or an Tape::Array of
		# either (or of further-nested Arrays -- e.g. `things.map((it; A(...)))` embedded inline among
		# other children, same as `Form([input, button, list])` in demos/*.tape's Dom examples).
		# Recurses into a nested Array rather than requiring exactly one flat level, so a mapped
		# collection of elements renders each element individually instead of being silently dropped
		# (neither a String nor a Dom Instance on its own) or, if handled some other way, rendered as
		# one opaque `[<a>...</a>, <a>...</a>]`-style Array#to_s string instead of real nested HTML.
		# `html` is mutated in place (`<<`), so callers pass an unfrozen accumulator and read it back
		# after -- `+=` here would rebind this local and lose everything.
		def append_dom_child_html value, html, render_scope
			case value
			when ::String
				html << value
			when Tape::Array
				value.values.each { |child| append_dom_child_html child, html, render_scope }
			else
				html << render_dom_to_html(value, render_scope: render_scope) if value.is_a?(Tape::Instance) && value.types.include?('Dom')
			end
		end

		# Raises when a `self.`/`Self.` accessor resolved to no scope -- shared by #interp_identifier, #interp_infix_assignment, #interp_infix_declaration.
		def raise_missing_scope_operator_target! expr, scope_operator_value
			case scope_operator_value
			when 'self'
				raise Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance.new(expr)
			when 'Self'
				raise Tape::Cannot_Use_Type_Scope_Operator_Outside_Type.new(expr)
			end
		end

		# A *method* found via #interp_identifier is duplicated and rebound to the resolving scope before
		# use, so composed types (e.g. `Thing | Record`) call it against the right receiver instead of
		# whatever type it was declared on. A method is identified by its `enclosing_scope` being a
		# Type/Instance. A function that already carries a real lexical scope -- a `( ...; ... )` literal
		# passed around as a closure, or a top-level function -- keeps it untouched; rebinding it would
		# silently drop its closure the moment it's passed to a Drive-implemented HOF (map/filter/find,
		# which look their `func` param up and would otherwise rebind it to the HOF's own call frame).
		# Non-Func values pass through unchanged.
		# Rebinds a just-found method to the Instance it was found on, so its siblings stay reachable --
		# only while still unbound (`instance_of?`, not `is_a?`: Instance < Type, so `is_a?` would also
		# match an already-bound method and re-rebind it to whatever unrelated scope it's later read from).
		def rebind_func_to_scope value, scope
			return value unless value.is_a?(Tape::Func) && value.enclosing_scope.instance_of?(Tape::Type)
			func                 = value.dup
			func.enclosing_scope = scope
			func
		end

		# `@word` / `x.@word` -- resolve `word` as a member of the scope's Context. A user-declared
		# `@word` lives on the declaring Type's Context, so an instance falls through to its type's.
		def interp_at_word_on scope, ident_expr
			# `@.values` / `@.members` on a struct read straight off the (write-synced) struct rather
			# than the Context, which snapshots its data members once on first `@` access.
			if scope.is_a?(Tape::Struct) && %w(values members).include?(ident_expr.value)
				live = ident_expr.value == 'members' ? scope.members : scope.values
				return live.is_a?(::Array) ? maybe_instance(live) : live
			end

			plain                  = ident_expr.dup
			plain.prefixed_with_at = false
			result                 = begin
				interp_member_access context_for(scope), plain, exclude_global_scope: true
			rescue Tape::Undeclared_Identifier
				raise unless scope.is_a?(Tape::Instance) && scope.enclosing_scope.is_a?(Tape::Type)
				interp_member_access context_for(scope.enclosing_scope), plain, exclude_global_scope: true
			end
			# Reflective collection proxies (`@.names`, `@.types`, ...) hand back a raw Ruby Array --
			# link it so it behaves like any other Drive Array (its own `==`, method dispatch).
			result.is_a?(::Array) ? maybe_instance(result) : result
		end

		# `@name: T` / `@name := v` / `@name: T = v` -- declares `name` onto the current Type's own
		# Context (`@name` / `x.@name`), never as a plain `.` member. Type scope only; `expr` is the
		# whole Infix_Expr, or the bare annotated Identifier_Expr for the no-value form.
		def interp_context_declaration expr
			left = expr.is_a?(Tape::Infix_Expr) ? expr.left : expr
			name = left.value

			raise Tape::Context_Declaration_Outside_Type.new(expr) unless stack.last.instance_of?(Tape::Type)

			raise Tape::Cannot_Override_Context_Member.new(expr) if context_builtin_member? name

			id    = context_for stack.last
			value = expr.is_a?(Tape::Infix_Expr) ? interpret(expr.right) : nil
			id.declare name, value
			value
		end

		# A member the Context struct already provides -- a reflective vital (its own declared members)
		# or a function (Context::FUNCTIONS). User `@x` declarations can't shadow these.
		def context_builtin_member? name
			return true if Tape::Context::FUNCTIONS.include? name
			decl = find_in_stack 'Context'
			decl.respond_to?(:names) && decl.names&.compact&.include?(name) || false
		end

		# `x.@word = v` / `x.@word := v` -- writes to x's Type's Context. The member must already be
		# declared in the type body; a built-in accessor can't be shadowed.
		def assign_context_member dot_expr, word_ident, value
			receiver = maybe_instance interpret dot_expr.left
			type     = receiver.is_a?(Tape::Instance) ? receiver.enclosing_scope : receiver
			name     = word_ident.value

			raise Tape::Cannot_Override_Context_Member.new(dot_expr) if context_builtin_member? name

			id = context_for type
			raise Tape::Cannot_Assign_Undeclared_Identifier.new(dot_expr) unless id.has?(name)

			id.declare name, value
			value
		end

		# Either `@x := v` / `@x = v` / `@x: T` -- a declaration onto a Type's Context, which runs once
		# in the type body (like a static), not per instance.
		def context_declaration_expr? expr
			return true if expr.is_a?(Tape::Identifier_Expr) && expr.prefixed_with_at && expr.type
			expr.is_a?(Tape::Infix_Expr) && %w(:= =).include?(expr.operator&.value) &&
				expr.left.is_a?(Tape::Identifier_Expr) && expr.left.prefixed_with_at
		end

		# The directive-flagged `@word` on the RHS of a `.` write target, if any.
		def dot_target_at_word dot_expr
			right = dot_expr.right
			right if right.is_a?(Tape::Identifier_Expr) && right.prefixed_with_at
		end

		def interp_identifier expr
			if expr.prefixed_with_at
				return interp_context_declaration expr if expr.type # `@x: T` -- annotation-only declaration
				return interp_ruby_proxy expr if expr.value == 'ruby' # `@ruby` inside a func body

				# A bare `@word` reference (no call): a built-in / user-declared Context member. Resolve
				# it against the current scope's Context, then any Type up the stack, then Global's.
				candidates = [stack.last, *stack.select { |s| s.is_a?(Tape::Type) }.reverse, global]
				seen       = []
				candidates.each do |scope|
					next if seen.any? { |s| s.equal?(scope) }
					seen << scope
					begin
						return interp_at_word_on(scope, expr)
					rescue Tape::Undeclared_Identifier
						next
					end
				end
				raise Tape::Undeclared_Identifier.new(expr)
			end

			scope = case expr.value
			when 'nil'
				return nil
			when 'true'
				# todo; return Tape::Bool.truthy
				return true
			when 'false'
				# todo; return Tape::Bool.falsy
				return false
			when 'Self'
				found = stack.reverse_each.find { |scope| scope.instance_of? Tape::Type }
				return found if found
				raise Tape::Cannot_Use_Type_Scope_Operator_Outside_Type.new(expr)
			when 'self'
				return current_instance if current_instance
				raise Tape::Cannot_Use_Instance_Scope_Operator_Outside_Instance.new(expr)
			when 'Global'
				return global
			when Tape::CONTEXT_OPERATOR
				return context_for(stack.last) # bare `@` -- the current scope's own Context
			else
				scope_for_identifier expr
			end

			value = if scope.is_a? ::Array
				found = scope.reverse_each.find do |scope|
					scope.has? expr.value
				end

				if found && found.has?(expr.value)
					found[expr.value]
				else
					raise Tape::Undeclared_Identifier.new(expr)
				end
			elsif scope
				# note: Delegate ruby calls automatically
				proxy_method = "proxy_#{expr.value}"
				if scope.has?(expr.value) && !scope.respond_to?(proxy_method)
					result = scope.get expr.value
					# If the result is a function, duplicate it and set its enclosing_scope to the current scope. This ensures composed types (like `Thing | Record`) have functions that reference the correct type
					return rebind_func_to_scope(result, scope) if result.is_a? Tape::Func
					result
				elsif scope.respond_to? proxy_method
					# Prefer the instance's own owning Type first -- for a tagged variant (e.g. `Array\Web_Server`) this is a distinct Type from the plain global one, and holds the actual override. Only fall back to a blind by-name search of the stack (which only ever finds the plain global type, e.g. plain "Array") when the instance isn't linked to a Type that declares this method itself.
					type_def       = if scope.enclosing_scope.is_a?(Tape::Type) && scope.enclosing_scope.has?(expr.value)
						scope.enclosing_scope
					else
						type_name  = scope.class.name.split('::').last
						type_scope = stack.reverse_each.find { |s| s.has?(type_name) }
						type_scope && type_scope[type_name]
					end
					declared_value = type_def[expr.value] if type_def

					if declared_value.is_a? Tape::Func
						# Use the actual function from the Type, not an empty wrapper
						return rebind_func_to_scope(declared_value, scope)
					else
						# It's a variable/property
						return scope.send(proxy_method)
					end
				elsif scope.is_a?(Tape::Instance) && scope.enclosing_scope&.is_a?(Tape::Type) && scope.enclosing_scope&.has?(expr.value)
					if expr.type || expr.tag
						self_declare_annotated_identifier expr
					else
						# todo: This seems like a hack. This currently prevents instances from shadowing it's type's declarations.
						# Method/property exists on the Type, not the instance
						return rebind_func_to_scope(scope.enclosing_scope.get(expr.value), scope)
					end
				elsif expr.type || expr.tag
					self_declare_annotated_identifier expr
				else
					raise Tape::Undeclared_Identifier.new(expr)
				end
			else
				# When scope is nil, errors must be raised
				if %w(self Self).include? expr.scope_operator&.value
					raise_missing_scope_operator_target! expr, expr.scope_operator.value
				elsif expr.type || expr.tag
					self_declare_annotated_identifier expr
				elsif stack.any? { |s| s.equal? global } && resolve_forward_declaration(expr.value) && global.has?(expr.value)
					# not reached yet in file order, but declared somewhere later on -- forced early. Context check (not #include?, which is `==` and can hit an Drive type's own overload -- e.g. Tape::Array#== assumes its operand also has .values). Global being absent from the stack means we're deliberately excluding it (a plain `x.y` dot access, #interp_dot_scope's exclude_global_scope: true) -- a member missing on x should stay missing, not quietly resolve to an unrelated global
					global[expr.value]
				elsif (variants = tagged_variants_for(expr.value)).length == 1
					# A tagged declaration (`Task\Schema {}`) never binds its bare name like a plain `Type {}` does -- unambiguous with one variant, so allow it (mirrors Bare Named Structs). 2+ variants stay unreachable except via `Name\Tag`.
					variants.first
				else
					raise Tape::Undeclared_Identifier.new(expr)
				end
			end

			if value.is_a?(Tape::Type)
				if expr.respond_to?(:add_to_readable) && expr.add_to_readable
					stack.last.add_readable_scope value
				elsif expr.respond_to?(:add_to_writable) && expr.add_to_writable
					stack.last.add_writable_scope value
				end
			end

			value
		end

		def interp_string expr
			return expr.value unless expr.interpolated

			interpolation_char_count = expr.value.count INTERPOLATE_CHAR
			if interpolation_char_count == 1
				return expr.value # For now... I think this is still not the correct approach.
			elsif interpolation_char_count > 1
				# todo: Proprely learn regex. For now, here's a description of what the regex below does:
				#
				# String: "Hi, `name`!"
				# Matches: ["name"]
				# Result: Interpolates the `name` variable

				# String: "Hi, \`name\`!"
				# Matches: []
				# Result: No interpolation, backslashes protect the backticks

				# String: "Hi, `first` and \`second\`"
				# Matches: ["first"]
				# Result: Only interpolates `first`, not `second`
				#

				result = expr.value
				# /m so a sub-expression containing a real newline (e.g. `` `arr.join("\n")` ``) still matches.
				sub_exprs = result.scan(/(?<!\\)`(.*?)(?<!\\)`/m).flatten

				sub_exprs.each do |sub|
					# Reuses the interpreter's own @parser (not a fresh Drive.parse) so it still knows about @operator declarations registered elsewhere in the program -- #input= resets the cursor but not @custom_infix/etc.
					parser.input = Lexer.new(sub).output
					value        = interpret parser.output.first
					result       = result.gsub "`#{sub}`", "#{stringify_for_display(value)}"
				end
				# Only the `\`` sequences still left over from escaping a backtick (deliberately never matched/substituted above) get un-escaped here -- a blanket `result.gsub('\\', '')` used to also strip any literal backslash that arrived as part of a substituted value's own content (e.g. `Array\<String>`), which was never the intent.
				result.gsub('\\`', '`')
			end
		end

		def interp_prefix expr
			# note: See constants.rb PREFIX for exhaustive list of language-defined prefixes
			case expr.operator.value
			when '-'
				-interpret(expr.expression)
			when '+'
				+interpret(expr.expression)
			when '~'
				~interpret(expr.expression)
			when '!', 'not'
				!interpret(expr.expression)
			when 'return'
				returned = expr.expression ? interpret(expr.expression) : nil
				Tape::Return.new returned
			else
				overload_func = find_in_stack expr.operator.value
				if overload_func.is_a? Tape::Func
					call           = Tape::Call_Expr.new
					call.arguments = [expr.expression]
					interp_func_body overload_func, call
				else
					raise Tape::Unhandled_Prefix.new(expr)
				end
			end
		end

		# `d[key] = value` on a Dictionary or Array -- `:=` on a subscript raises instead (Cannot_Declare_Subscript_Target below), it doesn't come through here.
		def assign_subscript target, value
			if target.expression.expressions.count > 1
				raise Tape::Too_Many_Subscript_Expressions.new(target)
			end
			receiver = interpret target.receiver
			key      = interpret target.expression.expressions.first # Circumfix_Expr stores subscript args as an array; only the first is the key

			if receiver.is_a? Tape::Dictionary
				receiver.proxy_set key, value
				receiver.proxy_get key
			elsif receiver.is_a? Tape::Array
				# Array has no `[]=` of its own -- without this it'd fall through to Instance#[]=, declaring a bogus member instead of writing `.values`.
				index                  = key.is_a?(Tape::Number) ? key.value : key
				unless index.is_a?(::Integer) && index.between?(-receiver.values.length, receiver.values.length - 1)
					raise Tape::Invalid_Array_Index.new(target)
				end
				receiver.values[index] = value
				receiver.values[index]
			else
				receiver[key] = value
				receiver[key]
			end
		end

		# @param expr [Tape::Infix_Expr]
		def interp_infix_assignment expr
			assignment_scope = scope_for_identifier expr.left # Reminder; this returns a scope whether or not the identifier exists

			# A type annotation (`x: Number = value`) is itself a declaration, so it's allowed to introduce a brand-new identifier just like `:=`, even though plain `=` otherwise requires the identifier to already exist. An inline signature (`x: Type(Param;) = value`) is the same idea — expr.left is a Func_Signature_Expr instead of a plain annotated Identifier_Expr, but it's just as self-declaring. A bare struct annotation (`thing: <String, Number> = value`) is self-declaring the same way, even with no `expr.left.type`.
			has_type_annotation = (expr.left.is_a?(Tape::Identifier_Expr) && (expr.left.type || expr.left.tag)) ||
			                      expr.left.is_a?(Tape::Func_Signature_Expr)
			assignment_scope    ||= stack.last if has_type_annotation

			# If using a scope operator but the scope doesn't exist, raise an error
			if expr.left.is_a?(Tape::Identifier_Expr) && expr.left.scope_operator && assignment_scope.nil?
				raise_missing_scope_operator_target! expr, expr.left.scope_operator.value
			end

			# For plain identifiers (no scope operator) inside an Instance/Type body, new declarations should go to that Instance/Type, not to an enclosing scope that happens to have the same identifier. This fixes a bug that prevented HTML Layout's `title` from capturing Title's `title` declaration in demos/basic_html_page.tape.
			if expr.left.is_a?(Tape::Identifier_Expr) && !expr.left.scope_operator
				current_scope = stack.last

				if (current_scope.is_a?(Tape::Instance) || current_scope.is_a?(Tape::Type)) &&
				   assignment_scope != current_scope && !current_scope.has?(expr.left.value)
					# The identifier exists in some enclosing scope but not in the current Instance/Type. Treat this as a new declaration on the current scope.
					assignment_scope = current_scope
				end
			end

			#
			# Special handling for load directive assignment, subscript, and maybe more later.
			#

			if expr.left.is_a? Tape::Subscript_Expr
				return assign_subscript expr.left, interpret(expr.right)
			end

			# Handle dot assignment
			if expr.left.is_a?(Tape::Infix_Expr) && expr.left.operator.value == '.'
				if (at_word = dot_target_at_word(expr.left))
					return assign_context_member expr.left, at_word, interpret(expr.right)
				end
				return assign_dot_member expr, expr.left, interpret(expr.right)
			end

			if load_call_expr?(expr.right)
				filepath  = interpret expr.right.arguments.first
				new_scope = Tape::Scope.new expr.left.value
				load_file_into_scope filepath, new_scope
				right_value = new_scope
			else
				right_value = interpret expr.right
			end

			# A Class-styled identifier (`My_Type = Other {}`) assigning a Scope value is itself a declaration, same reasoning as has_type_annotation above: `=` onto a fresh Class-styled name is how types get named/aliased, so it's allowed to introduce the identifier rather than requiring `:=` first.
			is_class_declaration = Drive.type_of_identifier(expr.left.value) == :Identifier && right_value.is_a?(Tape::Scope)
			assignment_scope     ||= stack.last if is_class_declaration

			# Before the actual assignment, the identifier is checked for specific behavior errors based on its expression type (class, constant, variable/function)
			case Drive.type_of_identifier expr.left.value
			when :IDENTIFIER
				# It can only be assigned once, so if the declaration exists, fail. An undeclared constant falls through to the Cannot_Reassign_Undeclared_Identifier check below.
				if assignment_scope&.has? expr.left.value
					raise Tape::Cannot_Reassign_Constant.new(expr.left)
				end
			when :Identifier
				# It can only be assigned `value` of Tape::Scope, which includes Tape::Type
				if !right_value.is_a?(Tape::Scope)
					raise Tape::Cannot_Assign_Incompatible_Type.new(expr)
				end
			when :identifier
				if assignment_scope
					# If the left side of the expression was declared with a type annotation, the type of `right_value` is enforced here.
					# `expr.left.type` covers the first, self-declaring assignment (the annotation is right here on this expression); the recorded type_by_identifier value covers every reassignment after that, once the annotation itself is gone. An inline signature (Func_Signature_Expr) supplies its own type directly, since it has no name to look up.
					type      = if expr.left.is_a? Tape::Func_Signature_Expr
						build_func_signature expr.left
					elsif expr.left.type.is_a? Tape::Struct_Expr
						# A bare struct annotation (`x: <String, Number>`) is structural, not nominal -- not enforced here.
						assignment_scope.type_by_identifier[expr.left.value]
					else
						expr.left.type&.value || assignment_scope.type_by_identifier[expr.left.value]
					end
					type      = type.name if type.is_a?(Tape::Type)
					signature = resolve_func_signature type

					if signature
						unless signature.matches? right_value
							raise Tape::Type_Contract_Violation.new(expr, signature.to_s, describe_value_shape(right_value))
						end
					else
						if type && !type_contract_satisfied?(right_value, type)
							raise Tape::Type_Contract_Violation.new(expr, type, inferred_type_name(right_value))
						end
					end
				end
			end

			unless assignment_scope && (assignment_scope.has?(expr.left.value) || has_type_annotation || is_class_declaration)
				# it may not be declared using =
				raise Tape::Cannot_Assign_Undeclared_Identifier.new(expr)
			end

			if expr.left.is_a?(Tape::Identifier_Expr) && expr.left.type && !expr.left.type.is_a?(Tape::Struct_Expr)
				assignment_scope.type_by_identifier[expr.left.value] = expr.left.type.value
			elsif expr.left.is_a? Tape::Func_Signature_Expr
				# Recorded so future reassignments (which are plain Identifier_Exprs with no annotation of their own) still resolve back to this signature to check against.
				assignment_scope.type_by_identifier[expr.left.value] = build_func_signature expr.left
			end

			assignment_scope.declare expr.left.value, right_value
			track_static_declaration assignment_scope, expr.left

			return right_value
		end

		# todo; Types may be composed of multiple types, what happens in that case?
		# @param expr [Tape::Infix_Expr]
		def interp_infix_declaration expr
			# `(a, b) := <tuple-or-struct-valued expr>` -- destructuring, handled entirely separately from the single-identifier case below (no scope operators, no type-by-identifier locking against a bare `.value`, none of it applies to a target list).
			if expr.left.is_a?(Tape::Circumfix_Expr) && expr.left.grouping == '()'
				return interp_destructuring_declaration expr
			end

			if expr.left.is_a?(Tape::Infix_Expr) && expr.left.operator&.value == '.'
				if (at_word = dot_target_at_word(expr.left))
					return assign_context_member expr.left, at_word, interpret(expr.right)
				end
				return assign_dot_member expr, expr.left, interpret(expr.right), declare: true
			end

			# `:=` declares an identifier; a subscript target isn't one -- raise rather than silently declaring a bogus identifier below.
			if expr.left.is_a? Tape::Subscript_Expr
				raise Tape::Cannot_Declare_Subscript_Target.new(expr)
			end

			# A `~/x` scope-operator form targets a specific scope. A plain `:=` always declares on the current scope, shadowing any identically-named identifier in an enclosing scope rather than re-declaring on it.
			has_scope_operator = expr.left.is_a?(Tape::Identifier_Expr) && expr.left.scope_operator
			assignment_scope   = scope_for_identifier expr.left if has_scope_operator

			# If using a scope operator but the scope doesn't exist, raise an error (mirrors interp_infix_assignment).
			if has_scope_operator && assignment_scope.nil?
				raise_missing_scope_operator_target! expr, expr.left.scope_operator.value
			end

			assignment_scope ||= stack.last

			# note; `self.`/`Self.` self-declaring a member that doesn't exist yet is valid but only while the type/instance is still under construction (see #still_under_construction?) -- calling a static method later and self-declaring a brand-new static from inside it isn't allowed.
			if has_scope_operator && assignment_scope.is_a?(Tape::Type) && !assignment_scope.has?(expr.left.value)
				raise Tape::Cannot_Assign_Undeclared_Identifier.new(expr) unless still_under_construction? assignment_scope
			end

			right_value = if load_call_expr?(expr.right)
				filepath  = interpret expr.right.arguments.first
				new_scope = Tape::Scope.new expr.left.value
				load_file_into_scope filepath, new_scope
				new_scope
			else
				interpret expr.right
			end

			assignment_scope.declare expr.left.value, right_value

			assignment_scope.type_by_identifier[expr.left.value] = inferred_type_name right_value
			track_static_declaration assignment_scope, expr.left
			right_value
		end

		# `(a, b) := (1, 2)` / `(a, b) := <a: Number, b: Number>(1, 2)` -- declares each target identifier in the current scope from the source's own values, positionally. Asking for fewer values than the source has is fine (the rest are just discarded); asking for more raises Destructuring_Arity_Mismatch. Each target is one of two kinds, each mirroring an existing single-value form exactly:
		#
		#   - A plain local (`a`, or `x: Number` with an annotation) -- declares fresh on the current
		#     scope, same as the single-identifier `:=` case. An explicit `: Type` is checked against
		#     that position's extracted value.
		#
		#   - An existing member (`thing.member`) -- reassigns rather than declares, same as plain
		#     `thing.member = value`: the member must already exist, must not be a constant, and (if it
		#     has a previously-recorded type) the extracted value must match it.
		#
		def interp_destructuring_declaration expr
			targets = expr.left.expressions

			unless targets.all? { |target| destructuring_target? target }
				raise Tape::Invalid_Destructuring_Target.new(expr)
			end

			right_value = interpret expr.right
			values      = destructurable_values right_value

			unless values
				raise Tape::Invalid_Destructuring_Source.new(expr)
			end

			if targets.length > values.length
				raise Tape::Destructuring_Arity_Mismatch.new(expr, targets.length, values.length)
			end

			targets.each_with_index do |target, i|
				value = values[i]

				if target.is_a? Tape::Identifier_Expr
					declare_destructuring_local expr, target, value
				else
					assign_dot_member expr, target, value
				end
			end

			right_value
		end

		def destructuring_target? target
			target.is_a?(Tape::Identifier_Expr) ||
				(target.is_a?(Tape::Infix_Expr) && target.operator&.value == '.' && target.right.is_a?(Tape::Identifier_Expr))
		end

		def declare_destructuring_local expr, target, value
			if target.type && !target.type.is_a?(Tape::Struct_Expr)
				expected = target.type.value
				unless type_contract_satisfied? value, expected
					raise Tape::Type_Contract_Violation.new(expr, expected, inferred_type_name(value))
				end
			end

			assignment_scope = stack.last
			assignment_scope.declare target.value, value, inferred_type_name(value)
			track_static_declaration assignment_scope, target
		end

		# True for a top-level `Self.x := value` static declaration -- it runs once during the type's own body walk, not per constructed instance (see #run_type_body_on_instance). `Self.x := value` parses as a `.` dot-target with a bare `Self` identifier on the left.
		def static_var_declaration_expr? expr
			return false unless expr.is_a?(Tape::Infix_Expr) && expr.operator&.value == ':='

			left = expr.left
			left.is_a?(Tape::Infix_Expr) && left.operator&.value == '.' &&
				left.left.is_a?(Tape::Identifier_Expr) && !left.left.scope_operator && left.left.value == 'Self'
		end

		# A scope that is "under construction" is still allowed to self-declare a brand-new member via `self` or `Self`
		def still_under_construction? scope
			if scope.is_a? Tape::Instance
				scope.has? 'Self'
			else
				scope.respond_to?(:declaration_in_progress) && scope.declaration_in_progress
			end
		end

		# Shared by every way of writing through `.` onto an already-interpreted receiver.
		def assign_dot_member expr, target, value, declare: false
			receiver = interpret target.left
			property = target.right.value

			# `interpret` here isn't run through #maybe_instance, so a nil receiver is still Ruby nil; a
			# self-declared-but-unset member (`x,`) comes back as Tape::Nil. Either way `x.foo = 1` has no
			# receiver to write to -- name that directly instead of a generic "undeclared identifier". A
			# member `nil` itself declares is left alone, matching the read path in #interp_dot_scope.
			if receiver.nil? || (receiver.is_a?(Tape::Nil) && !receiver.has?(property))
				raise Tape::Receiver_Is_Nil.new(target)
			end

			# `.tag =` re-tags a value declared with a tag. The new tag must keep the declared
			# signature: compose at least everything the current tag does, at every chain link
			# (`=>=`). A value with no tag has no `.tag` to write -- Member Creation Is Strict
			# handles that below.
			if property == 'tag' && receiver.is_a?(Tape::Scope) && receiver.has?('tag')
				new_tag               = tag_struct_for_reassignment value, target
				unless tag_chains_satisfy? receiver.tag_instance, new_tag
					raise Tape::Tag_Signature_Violation.new(expr, tag_display_name(receiver), stringify_for_display(new_tag))
				end
				receiver.tag_instance = new_tag
				declare_tag receiver
				return value
			end

			# Bare `self`/`Self` on the left of a `.` write target. The scope-operator write paths (#interp_infix_declaration's `scope_operator` branch, #interp_infix_assignment's general flow) never run Cannot_Reassign_Constant or check_dot_access_permissions! -- only the external-`.`-write rules below do (see "Member Creation Is Strict") -- so `self`/`Self` route around both entirely here too, for both `=` and `:=`, rather than only the not-yet-declared case.
			self_keyword = target.left.is_a?(Tape::Identifier_Expr) && !target.left.scope_operator &&
			               Tape::SCOPE_KEYWORDS.include?(target.left.value)

			if self_keyword && receiver.is_a?(Tape::Scope)
				# `Global.x := v` always declares -- the global scope has no "construction finished" moment
				# the way an instance does. Plain `Global.x = v` still needs a prior declaration.
				unless receiver.has?(property) || still_under_construction?(receiver) || (declare && receiver.is_a?(Tape::Global))
					raise Tape::Cannot_Assign_Undeclared_Identifier.new(expr)
				end

				if declare
					receiver.static_declarations.add property if target.left.value == 'Self'
					return receiver.declare property, value, inferred_type_name(value)
				end

				expected = receiver.type_by_identifier[property]
				if expected && !type_contract_satisfied?(value, expected)
					raise Tape::Type_Contract_Violation.new(expr, expected, inferred_type_name(value))
				end

				receiver[property] = value
				return value
			end

			unless receiver.is_a?(Tape::Scope) && receiver.has?(property)
				raise Tape::Cannot_Assign_Undeclared_Identifier.new(expr)
			end

			if Drive.type_of_identifier(property) == :IDENTIFIER
				raise Tape::Cannot_Reassign_Constant.new(expr)
			end

			check_dot_access_permissions! receiver, property, expr

			if declare
				receiver.type_by_identifier[property] = inferred_type_name value
			else
				expected = receiver.type_by_identifier[property]
				if expected && !type_contract_satisfied?(value, expected)
					raise Tape::Type_Contract_Violation.new(expr, expected, inferred_type_name(value))
				end
			end

			receiver[property] = value
			value
		end

		# Tape::Tuple/Tape::Struct both carry a plain Ruby-level `.values` reader holding the raw backing array (distinct from their Drive-level `.values` dot-access, which wraps the same data in an Tape::Array for Drive code to read).
		def destructurable_values value
			case value
			when Tape::Tuple, Tape::Struct
				value.values
			end
		end

		# @param expr [Tape::Infix_Expr]
		def interp_dot_infix expr
			receiver = maybe_instance interpret expr.left

			unless receiver.kind_of?(Tape::Scope)
				raise Tape::Invalid_Dot_Infix_Left_Operand.new(expr)
			end

			# `x.@word` -- a member of x's Context, not of x (RHS is a directive-flagged Identifier_Expr)
			at_word  = expr.right if expr.right.is_a?(Tape::Identifier_Expr) && expr.right.prefixed_with_at
			return interp_at_word_on(receiver, at_word) if at_word

			case receiver
			when Tape::Array, Tape::Tuple, Tape::Struct
				# A Struct's own `.values` makes `.0`-style positional access work for it too, same as Array/Tuple.
				interp_dot_array_or_tuple receiver, expr
			when Tape::String
				# Separate dispatch, not shared with Array/Tuple/Struct's -- that one's `.each` shorthand would misfire, since String has no #each.
				interp_dot_string receiver, expr
			when Tape::Range
				interp_dot_range receiver, expr
			when Tape::Dictionary
				interp_dot_dictionary receiver, expr
			else
				# A tagged type reference on the right (`ns.Abc\<Number>`) isn't an Identifier_Expr, so it bypasses #interp_dot_scope's right-operand validation.
				if expr.right.instance_of? Tape::Type_Expr
					return interp_member_access receiver, expr.right
				end

				interp_dot_scope receiver, expr
			end
		rescue Tape::Undeclared_Identifier, Tape::Cannot_Call_Instance_Member_On_Type, Tape::Receiver_Is_Nil, Tape::Invalid_Dot_Infix_Left_Operand
			# `.?` is lenient access -- a receiver that isn't even a Scope (a raw Func_Signature reached as
			# a struct member's `type`, say) yields nil rather than raising, same as a nil receiver does.
			raise unless expr.operator.value == '.?'
			nil
		end

		def stringify_for_display value, show_quotes: false, pretty_print: false
			value = maybe_instance value
			# A bare Type's `to_s` (copied from its own body) assumes real instance context and crashes if called directly on the Type itself, so only attempt it on a genuine Instance.
			return value unless value.is_a? Tape::Instance

			# `@` (a Context) synthesizes its own `to_s` to the terse `@<name>` form -- but for display
			# (`@puts @`, `` `@` `` interpolation) show the whole filled struct instead. An explicit
			# `@.to_s()` call still goes through the synthesized stand-in. Also covers a directly
			# constructed `Context()` / bare `Context` reference (a `Struct` composing `Context`, not the
			# `Tape::Context` Ruby class) -- its func-signature members would otherwise crash `Struct#to_s`.
			return stringify_context(value, pretty_print: pretty_print) if value.is_a?(Tape::Context) || (value.is_a?(Tape::Struct) && value.types&.include?('Context'))

			method_name       = show_quotes && value.is_a?(Tape::String) ? 'to_string' : 'to_s'
			to_s_ident        = Tape::Identifier_Expr.new
			to_s_ident.lexeme = Tape::Lexeme.new(:identifier, method_name)
			func              = begin
				interp_member_access value, to_s_ident
			rescue Tape::Undeclared_Identifier
				nil
			end
			return value unless func.is_a? Tape::Func

			call           = Tape::Call_Expr.new
			call.arguments = []
			# A synthesized Context function stand-in (`@`'s own `to_s`) has no body -- route it the same way #interp_call does, or the empty body just yields nil and `@` prints blank.
			return interp_context_function(func, call) if func.context_function_name

			interp_func_body func, call
		end

		# Renders a Context (`@`) the same shape every other struct prints as -- `Context <name: Type =
		# value, ...>`. Walks the `Context` struct declaration's own member list (tapes/context.tape), so
		# only real declared members show -- not the extra short-alias function stand-ins `#fill_context`
		# also puts on the instance (`add_readable`, `readable`, ...). Data members print their filled
		# value (or `name: Type` when nil); function members print their `( -> ...;)` signature.
		def stringify_context context, pretty_print: false
			decl  = (global.has?('Context') ? global['Context'] : nil)
			names = decl.respond_to?(:names) && decl.names ? decl.names : context.declarations.keys

			pairs = names.each_with_index.map do |name, i|
				type = (decl.type_names[i] if decl.respond_to?(:type_names)) ||
				       (decl.type_objects[i]&.to_s if decl.respond_to?(:type_objects))
				val  = context.declarations[name]

				# A function member -- either the synthesized `@`-dispatch stand-in, or (on a directly
				# constructed `Context()`) the real `Struct#to_s` copied onto it. Neither has a
				# displayable value; show just `name: signature`.
				if val.is_a?(Tape::Func) || val.nil?
					type ? "#{name}: #{type}" : "#{name}: Any"
				else
					shown = stringify_for_display(val, show_quotes: true)
					type ? "#{name}: #{type} = #{shown}" : "#{name} := #{shown}"
				end
			end

			"#{context.name} <#{pairs.join(', ')}>"
		end

		# Interprets `expr` (the right side of `x.y`) scoped only to `receiver` and global scope, so a missing member can't fall through to an unrelated identically-named one still active further down the caller's stack (this caused a real infinite recursion before the fix).
		def interp_member_access receiver, expr, exclude_global_scope: false
			# `X.Self`/`x.self` is an ordinary member lookup, not the bare `Self`/`self` keyword #interp_identifier special-cases -- bypass that branch so a declared `Self` resolves like any other name.
			if expr.is_a?(Tape::Identifier_Expr) && !expr.scope_operator && Tape::SCOPE_KEYWORDS.include?(expr.value)
				return receiver[expr.value] if receiver.is_a?(Tape::Scope) && receiver.has?(expr.value)
				raise Tape::Undeclared_Identifier.new(expr)
			end

			begin
				saved_stack = stack
				self.stack  = if exclude_global_scope
					[receiver]
				else
					[stack.first, receiver]
				end

				interpret expr
			ensure
				self.stack = saved_stack
			end
		end

		# The dot sub-handlers below all take the receiver #interp_dot_infix already interpreted rather than re-interpreting expr.left themselves — re-interpreting ran the receiver expression's side effects (calls, constructions) a second or third time.
		# Bounds/type-checked element access for `.N`/`.N.M...` dot-index syntax on an Array/Tuple -- plain `values[index]` (Ruby's own Array#[]) silently returns nil past the end, and silently truncates a non-integer index (e.g. `.0.1` lexes as the single float 0.1, which Ruby's [] truncates to index 0) -- both looked like a legitimate result instead of a mistake.
		def array_index_value collection, index, expr
			if collection.is_a? Tape::String
				chars = collection.value.chars
				unless index.is_a?(::Integer) && index.between?(-chars.length, chars.length - 1)
					raise Tape::Invalid_Array_Index.new(expr)
				end
				return maybe_instance chars[index]
			end

			unless index.is_a?(::Integer) && index.between?(-collection.values.length, collection.values.length - 1)
				raise Tape::Invalid_Array_Index.new(expr)
			end
			collection.values[index]
		end

		# `.N`/`.N.M...` positional access on a String, indexing by character.
		def interp_dot_string str, expr
			case
			when expr.right.is(Tape::Number_Expr)
				array_index_value str, expr.right.value, expr
			when expr.right.is(Tape::Array_Index_Expr)
				expr.right.indices_in_order.reduce(str) do |current, index|
					raise Tape::Invalid_Dot_Infix_Left_Operand.new(expr) unless current.is_a?(Tape::Array)
					array_index_value current, index, expr
				end
			else
				interp_dot_scope str, expr
			end
		end

		def interp_dot_array_or_tuple scope, expr
			case
			when expr.right.is(Tape::Func_Expr) && expr.right.name.value == 'each'
				interp_each_loop scope, expr.right
				scope

			when expr.right.is(Tape::Number_Expr)
				array_index_value scope, expr.right.value, expr

			when expr.right.is(Tape::Array_Index_Expr)
				expr.right.indices_in_order.reduce(scope) do |current, index|
					raise Tape::Invalid_Dot_Infix_Left_Operand.new(expr) unless current.is_a?(Tape::Array)
					array_index_value current, index, expr
				end

			else
				interp_dot_scope scope, expr
			end
		end

		def interp_dot_range range, expr
			return interp_each_loop range, expr.right if expr.right.is(Tape::Func_Expr) && expr.right.name.value == 'each'
			interp_dot_scope range, expr
		end

		def interp_dot_dictionary dict, expr
			if expr.right.is_a? Tape::Identifier_Expr
				key_sym = expr.right.value.to_sym
				if dict.hash.has_key?(key_sym)
					return dict.hash[key_sym]
				end
			end

			interp_member_access dict, expr.right
		end

		def interp_dot_scope scope, expr
			raise Tape::Invalid_Dot_Infix_Left_Operand.new(expr) if scope.nil?
			raise Tape::Invalid_Dot_Infix_Right_Operand.new(expr.right) unless expr.right.instance_of? Tape::Identifier_Expr

			check_dot_access_permissions! scope, expr.right.value, expr

			interp_member_access scope, expr.right, exclude_global_scope: true
		rescue Tape::Undeclared_Identifier
			# `nil` is a real scope with its own declared members (`to_s`, ...), so a lookup that actually
			# reaches one still works. Only a genuinely missing member on a nil receiver becomes this --
			# far clearer than "<member> has not been declared", which reads as a missing type.
			raise Tape::Receiver_Is_Nil.new(expr) if scope.is_a?(Tape::Nil)
			raise
		end

		def interp_each_loop collection, func_expr
			collection.each do |it|
				each_scope                 = Tape::Scope.new 'each(;)'
				each_scope.enclosing_scope = stack.last
				push_scope each_scope
				each_scope.declare 'it', it
				func_expr.parameters.each { |e| interpret e }
				func_expr.expressions.each { |e| interpret e }
				pop_scope
			end
		end

		# The values for expr.operator, expr.left, and expr.right should all exist by this point
		# @param expr [Tape::Nil_Init_Expr]
		def interp_nil_init expr
			# attr_accessor :operator, :left, :right
			current_scope = stack.last

			# Same shadowing fix as interp_infix_assignment: inside an Instance/Type body, a plain identifier's nil-init must declare on the current Instance/Type even if an enclosing scope (e.g. the Type, whose body already ran once at definition time) already has an identically-named identifier. Otherwise re-running `thing,` per-instance in interp_type_call finds the Type's stale copy and never declares it on the instance.
			if (current_scope.is_a?(Tape::Instance) || current_scope.is_a?(Tape::Type)) && !current_scope.has?(expr.left.value)
				current_scope.declare expr.left.value, interpret(expr.right)
				track_static_declaration current_scope, expr.left
				return current_scope.get expr.left.value
			end

			begin
				return interpret expr.left
			rescue # Tape::Undeclared_Identifier and ArgumentError # todo: Why `ArgumentError: empty string`. Once this is resolved, then the rescue here should explicitly catch Undeclared_Identifier, probably.
				scope = scope_for_identifier(expr.left) || stack.last
				scope.declare expr.left.value, interpret(expr.right)

				track_static_declaration scope, expr.left
			end
		end

		# A bare annotated identifier (`x: Number`, `thing: <String, Number>`) that's never been declared behaves like the nil-init idiom (`ident,`) rather than raising Undeclared_Identifier
		def self_declare_annotated_identifier expr
			scope = stack.last
			scope.declare expr.value, nil
			track_static_declaration scope, expr
			nil
		end

		# A type's own @operator overload takes precedence over a same-named global one. Checks the operand's own declarations first, then its enclosing Type (for shorthand-constructed instances that never got the type's declarations copied onto themselves, see #interp_type_call), and only falls back to a global operator (excluding Type/Instance scopes, see the comment at the call site in #interp_infix) if neither applies.

		def find_operator_overload operator, operand = nil
			if operand.is_a?(Tape::Instance) && operand.has?(operator)
				return operand.get operator
			end

			if operand.is_a?(Tape::Scope) && operand.enclosing_scope.is_a?(Tape::Type) && operand.enclosing_scope.has?(operator)
				return operand.enclosing_scope.get operator
			end

			stack.reverse_each do |scope|
				next if scope.is_a?(Tape::Type)
				return scope.declarations[operator] if scope.declarations.key?(operator)
			end
			nil
		end

		# Second-level dispatcher for infix operators, mirroring #interpret's own shape: each branch hands off to one interp_*_infix handler. The first group dispatches before operand evaluation — the assignment family treats the left side as a target rather than a value, `@` (the unpack marker) isn't a value at all, and logical operators must stay lazy to short-circuit. Every remaining operator evaluates each operand exactly once, here, and passes the values down so no handler re-interprets an operand (side effects run once).
		# @param expr [Tape::Infix_Expr]
		def interp_infix expr
			operator = expr.operator.value

			if (operator == '=' || operator == ':=') && expr.left.is_a?(Tape::Identifier_Expr) && expr.left.prefixed_with_at
				return interp_context_declaration expr
			end

			return interp_infix_assignment expr if operator == '='
			return interp_infix_declaration expr if operator == ':='
			return interp_dot_infix expr if operator == '.' || operator == '.?'
			return interp_logical_infix expr if LOGICAL_OPERATORS.include? operator

			left  = interpret expr.left
			right = interpret expr.right

			case
			when INFIX_ARITHMETIC_OPERATORS.include?(operator)
				interp_arithmetic_infix expr, left, right
			when COMPARISON_OPERATORS.include?(operator)
				interp_comparison_infix expr, left, right
			when COMPOUND_OPERATORS.include?(operator)
				interp_compound_infix expr, left, right
			when RANGE_OPERATORS.include?(operator)
				interp_range_infix expr, left, right
			else
				interp_custom_infix expr, left, right
			end
		end

		# Calls an @operator overload as a regular two-argument function. `values` carries the operands when the caller already evaluated them; nil lets #interp_func_body evaluate the raw expressions once itself (only the lazy logical path needs that).
		def call_operator_overload overload, expr, values
			call           = Tape::Call_Expr.new
			call.arguments = [expr.left, expr.right]
			interp_func_body overload, call, arg_values: values
		end

		# Interprets its own operands (the one infix handler that does) because `&&`/`||` must short-circuit. A scope-level @operator overload still wins first, called with the raw expressions so the operands evaluate once, eagerly, inside the call.
		def interp_logical_infix expr
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, nil) if overload.is_a? Tape::Func

			case expr.operator.value
			when '&&', 'and'
				interpret(expr.left) && interpret(expr.right)
			when '||', 'or'
				interpret(expr.left) || interpret(expr.right)
			when '&'
				interpret(expr.left) & interpret(expr.right)
			when '|'
				interpret(expr.left) | interpret(expr.right)
			end
		end

		# If left (or left's type) declares this operator via @operator, call it like a regular function with (left, right) as arguments. Falls back to left.enclosing_scope (the Type) because shorthand-constructed instances (array/string/dict literals, e.g. `[1, 2, 3]`) never get the type's own declarations copied down onto themselves the way `Array(...)`-style construction does (see #interp_type_call) -- this mirrors the same fallback #interp_identifier already does for regular method calls like `arr.push(...)`. Falls back further to a same-named global operator if the operand itself doesn't declare one.
		def interp_arithmetic_infix expr, left, right
			overload = find_operator_overload expr.operator.value, maybe_instance(left)

			if overload.is_a? Tape::Func
				call_operator_overload overload, expr, [left, right]
			else
				maybe_instance(left).send expr.operator.value, maybe_instance(right)
			end
		end

		# note; I'm special casing these because they don't behave like the traditional == and != in Ruby.
		# For `#interp_comparison_infix`'s "a String equals a bare Type by name" rule: returns
		# `[string_value, the_type]` when exactly one operand is a String and the other a bare Type
		# (a real Type, not an Instance or Struct), else `[nil, nil]`.
		def string_value_and_bare_type a, b
			str_of    = ->(v) { v.is_a?(Tape::String) ? v.value : (v.is_a?(::String) ? v : nil) }
			bare_type = ->(v) { v.is_a?(Tape::Type) && !v.is_a?(Tape::Instance) }

			if !str_of.(a).nil? && bare_type.(b) then
				[str_of.(a), b]
			elsif !str_of.(b).nil? && bare_type.(a) then
				[str_of.(b), a]
			else
				[nil, nil]
			end
		end

		# The literal `Any` type (tapes/global.tape), a universal wildcard -- see #interp_comparison_infix.
		def any_type? value
			value.is_a?(Tape::Type) && value.name == 'Any'
		end

		def interp_comparison_infix expr, left, right
			# `Any` is a supertype of everything except nil, no composition needed. True for every "equal-ish" op, false for "different-ish" ones.
			if ANY_WILDCARD_COMPARISON_OPERATORS.include?(expr.operator.value) && (any_type?(left) || any_type?(right))
				other = any_type?(left) ? right : left
				equal = !other.nil?
				return %w(== === =>= =<=).include?(expr.operator.value) ? equal : !equal
			end

			# `"Flying" == Flying` -- a String equals a bare Type (either operand order) when it spells
			# the type's own name. `==`/`!=` only. Lets `set.include?(SomeType)` match against a Set of
			# type-name strings (`@.composed_types`), without the Set having to store anything but strings.
			if %w(== !=).include?(expr.operator.value)
				str_val, a_type = string_value_and_bare_type(left, right)
				unless str_val.nil?
					matches = str_val == a_type.name
					return expr.operator.value == '==' ? matches : !matches
				end
			end

			case expr.operator.value
			when '===', '=!=', '=>=', '=<=', '=/='
				# `.type_objects`, not `.types` -- `Tape::Struct < Instance < Type` inherits Type's own
				# `.types` (the composed-type-name Set, e.g. `Set['Struct']` for every struct alike),
				# which shadows/collides with what's actually wanted here: the struct's own per-member
				# type objects (`.type_objects`, a plain `Struct#@type_objects` ivar).
				left_tag  = left.is_a?(Tape::Type) ? left.tag_instance&.type_objects : nil
				right_tag = right.is_a?(Tape::Type) ? right.tag_instance&.type_objects : nil

				# note; `left`/`right` are whatever #interpret returned (a raw Ruby Integer/String/etc for literals, not necessarily an Tape::Type/Instance), so `.types` can't be called on them directly. Using #composed_types_for here which resolves the correct composed-type set.
				left_types  = composed_types_for left
				right_types = composed_types_for right

				# note; `=>=`/`=<=` are the only operators here that carry genuinely new information (see CLAUDE.md) -- `=<=` is just `=>=` with operands swapped, and `===` is mutual `=>=` in both directions; `=!=` is `!(===)`. Deriving them instead of duplicating the field-superset check keeps all four in sync by construction.
				case expr.operator.value
				when '=>='
					superset_of_types_and_tag? left_types, left_tag, right_types, right_tag
				when '=<='
					superset_of_types_and_tag? right_types, right_tag, left_types, left_tag
				when '==='
					superset_of_types_and_tag?(left_types, left_tag, right_types, right_tag) &&
						superset_of_types_and_tag?(right_types, right_tag, left_types, left_tag)
				when '=!='
					!(superset_of_types_and_tag?(left_types, left_tag, right_types, right_tag) &&
						superset_of_types_and_tag?(right_types, right_tag, left_types, left_tag))
				when '=/='
					shared_types   = left_types.any? do |type|
						right_types.include? type
					end
					shared_members = (left_tag || []).any? do |member|
						(right_tag || []).include? member
					end

					!shared_types && !shared_members
				end

			when '=~', '!~'
				# These behave just like Ruby's =~/!~: =~ returns the match index (or nil), !~ returns the boolean negation of a match.
				subject     = maybe_instance(left).value
				pattern     = maybe_instance(right).value
				match_index = subject =~ Regexp.new(pattern)

				expr.operator.value == '!~' ? match_index.nil? : match_index

			else
				# note; ==, !=, <, >, <=, >=, <=> aren't given fixed set-comparison semantics above, so — same as arithmetic — check for a user-declared @operator overload (on left itself, or falling back to left.enclosing_scope for shorthand-constructed instances, or a same-named global operator) before falling back to Ruby's own #==/#<=>/etc.
				overload = find_operator_overload expr.operator.value, left

				# note; A type declaring `@operator ==` but no `@operator !=` of its own (the common case tapes/struct.tape's Member/Struct are exactly this) used to fall straight through to Ruby's own #!= for `!=`, which is identity-based and ignores the custom == entirely, two structurally-equal Members compared unequal with `!=` even though `==` correctly said they were equal. `!=` now derives from a declared `==` overload (negated) when it has no overload of its own, matching how most languages auto-derive != from ==.
				if !overload.is_a?(Tape::Func) && expr.operator.value == '!='
					overload      = find_operator_overload '==', left
					negate_result = true
				end

				if overload.is_a? Tape::Func
					result = call_operator_overload overload, expr, [left, right]
					negate_result ? !truthy?(result) : result
				elsif left.respond_to?(expr.operator.value) && !(expr.operator.value == '<=>' && left.method(:<=>).owner == ::Kernel)
					left.send expr.operator.value, right
				else
					# note; Numbers/Strings reach here fine (they decay to plain Ruby values with a native <=>/</>/etc.), but a plain Tape::Instance has none of these implemented -- except <=>, which Ruby's own Kernel/Object gives every object a trivial, identity-based default for. `respond_to?` alone can't tell that apart from a real one, so the method's actual owner is checked too. There's no sensible fallback to invent here, equality doesn't imply order.
					raise Tape::Undeclared_Infix_Operator.new expr
				end
			end
		end

		# (a += b)  ==>  (a = (a + b)). Compound operators only ever consult a scope-level @operator overload (never the operand's own), since their built-in meaning is assignment, not a property of the operand's type.
		def interp_compound_infix expr, left, right
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, [left, right]) if overload.is_a? Tape::Func

			base_op = expr.operator.value[..-2] # Trim the = from +=, -=, etc.
			result  = maybe_instance(left).send base_op, maybe_instance(right)

			# Assign back to left side -- a dot-target (`instance.member += ...`) goes through the same
			# #assign_dot_member path plain `.`-assignment uses; #scope_for_identifier only understands
			# plain Identifier_Exprs, so a dot-target used to silently fall through to `stack.last` and
			# declare a bogus `nil`-named identifier there instead of touching the actual member.
			if expr.left.is_a?(Tape::Infix_Expr) && expr.left.operator&.value == '.'
				assign_dot_member expr, expr.left, result
			else
				assignment_scope = scope_for_identifier expr.left
				assignment_scope.declare expr.left.value, result
			end
		end

		def interp_range_infix expr, start, finish
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, [start, finish]) if overload.is_a? Tape::Func

			# `xs[2...]` (endless, nil `.right`) / `xs[...3]` (beginless, nil `.left`) -- see the parser.
			# The Ruby `::Range` gets a nil end/start; `.to_a`/`for` over an endless one loops forever,
			# but slicing is fine, and a beginless/endless range's `start`/`finish` methods read nil.
			finish = nil if expr.right.nil?
			start  = nil if expr.left.nil?

			from, to, exclude_end = case expr.operator.value
			when '...' then [start, finish, false]
			when '..<' then [start, finish, true]
			when '>..' then [start + 1, finish, false]
			when '>.<' then [start + 1, finish, true]
			end

			finish_intrinsic_instance Tape::Range.new(::Range.new(from, to, exclude_end)), 'Range'
		end

		# A user-declared @operator with no built-in category of its own. The operand's own overload wins over a global one (#find_operator_overload). Reachable with no overload in scope when the operator is declared inside some other scope (the parser's pre-scan registers it file-wide) — that used to silently evaluate to nil; now it raises.
		def interp_custom_infix expr, left, right
			overload = find_operator_overload expr.operator.value, maybe_instance(left)
			unless overload.is_a? Tape::Func
				raise Tape::Undeclared_Infix_Operator.new(expr)
			end

			call_operator_overload overload, expr, [left, right]
		end

		# @param expr [Tape::Postfix_Expr]
		def interp_postfix expr
			# note: See constants.rb POSTFIX for exhaustive list of language-defined postfixes. Currently there are no built-in postfix operators.
			# 1) look up the opreator (expr.operator.value) as it should be a normal func in the scope.
			# 2) call it with expr.expression as its argument. It should only take one argument.
			postfix_overloaded_func = find_in_stack expr.operator.value

			if !postfix_overloaded_func
				raise "Could not find #{expr.operator.value} declared anywhere man!"
			end

			call           = Tape::Call_Expr.new
			call.arguments = [expr.expression]
			interp_func_body postfix_overloaded_func, call
		end

		# @param expr [Tape::Percent_Literal_Expr < Tape::Circumfix_Expr]
		def interp_percent_literal expr
			literal_expr_class = case expr.kind
			when 'string', 'str', 'Str', 'STR' then Tape::String_Expr
			when 'symbol', 'sym', 'Sym', 'SYM' then Tape::Symbol_Expr
			end

			# %string/%symbol preserve the identifier's own casing; the rest force one.
			casing = case expr.kind
			when 'string', 'symbol' then :itself
			when 'str', 'sym' then :downcase
			when 'Str', 'Sym' then :capitalize
			when 'STR', 'SYM' then :upcase
			end

			array_expr             = Tape::Circumfix_Expr.new
			array_expr.grouping    = '[]'
			array_expr.expressions = expr.expressions.map do |it|
				# A backtick item is evaluated immediately, like string interpolation, then folded through the same to_s + casing treatment as every other item. No Tape::Statement gets built here (unlike #invoke_statement's callers), so use_caller_scope/memoize never come into play -- it's always immediate, in whatever scope this literal is written in.
				if it.is_a? Tape::Statement_Expr
					value = interpret(it.expression).to_s.send casing
					literal_expr_class.new value
				else
					lexeme       = it.lexeme.dup
					lexeme.value = it.value.to_s.send casing
					literal_expr_class.new lexeme
				end
			end

			interp_circumfix array_expr
		end

		def interp_circumfix expr
			case expr.grouping
			when '[]'
				array             = Tape::Array.new
				array.expressions = expr.expressions

				values = []
				expr.expressions.each do |e|
					# Same as #interp_percent_literal above: `` `expr` `` inside an array literal evaluates immediately, no Tape::Statement built.
					e = e.expression if e.is_a? Tape::Statement_Expr
					values << interpret(e)
				end
				link_instance_to_type array, 'Array'

				# Make values accessible as an Drive identifier (`for values`, `arr.values`), sharing the same list object as the real backing store so mutations (push/pop/etc) stay in sync.
				array.values                 = values
				array.declarations['values'] = values

				array
			when '()'
				if expr.expressions.count == 1
					# note: Single expressions should be treated as though they were not inside parentheses so that algebraic expressions can be grouped using parentheses. If I wrap single expressions in a Tuple then I have to also unwrap them later for arithmetic operations.
					interpret expr.expressions.first
				else
					values = expr.expressions.map { |e| interpret(e) }
					tuple  = Tape::Tuple.new values
					link_instance_to_type tuple, 'Tuple'
					tuple.declarations['values'] = tuple.values
					tuple
				end
			when '{}'
				dict = expr.expressions.reduce(Tape::Dictionary.new) do |dict, it|
					if it.is_a? Tape::Identifier_Expr
						dict.proxy_set it.value.to_sym, nil
					elsif it.is_a? Tape::Infix_Expr
						case it.operator.value
						when ':', '='
							if it.left.is_a?(Tape::Identifier_Expr) || it.left.is_a?(Tape::Symbol_Expr) || it.left.is_a?(Tape::String_Expr)
								# note; Deliberately NOT wrap_string_literal_value here, unlike Array/Tuple literals -- Dictionary#hash is handed straight to Ruby-level consumers as a raw Hash (Sequel queries in table.rb chief among them), so wrapping a value into Tape::String here broke every DB call passing string attributes. #to_s below just always double-quotes String values instead of matching the original literal's quote char.
								dict.proxy_set it.left.value.to_sym, interpret(it.right)
							else
								# The left operand should be allowed to be any hashable object. It's too early in the project to consider hashing but this'll be a good reminder.
								raise Tape::Invalid_Dictionary_Key.new(it)
							end
						else
							raise Tape::Invalid_Dictionary_Infix_Operator.new(it)
						end
					end
					# In case I forget, #reduce requires that the injected value be returned to be passed to the next iteration.
					dict
				end
				link_instance_to_type dict, 'Dictionary'
				dict
			else
				raise Tape::Unknown_Circumfix_Grouping.new(expr)
			end
		end

		# @param expr [Tape::Call_Expr]
		def interp_call expr
			# A bare `` `expr`() `` written and called in the same place -- always immediate, in whatever scope it's written in. No Tape::Statement is ever built here, so #invoke_statement (used below, once one *has* been built and stored) doesn't apply.
			if expr.receiver.is_a? Tape::Statement_Expr
				return interpret expr.receiver.expression
			end

			receiver = interpret expr.receiver

			# A nil-safe dot chain (`x.?method`) that found nothing evaluates to nil deliberately -- a trailing call (`x.?method()`) should short-circuit to nil too, not try to invoke nil.
			if receiver.nil? && expr.receiver.is_a?(Tape::Infix_Expr) && expr.receiver.operator&.value == '.?'
				return nil
			end

			case receiver
			when Tape::Route
				interp_func_body receiver.handler, expr

			when Tape::Func
				# A synthesized Context function stand-in (`@puts`, `@push_scope`, ...) -- route to the
				# intrinsic, never run a body. Stack functions run in *this* frame (the caller's).
				return interp_context_function(receiver, expr) if receiver.context_function_name
				interp_func_body receiver, expr

			when Tape::Struct
				interp_struct_call receiver, expr

			when Tape::Statement
				# Reached once a Statement has been stored in a variable (or field, etc.) and is being called from somewhere else -- Tape::Statement < Instance, so this has to come before the generic Instance branch below or it'd be mistaken for "construct a new Statement".
				invoke_statement receiver

			when Tape::Instance, Tape::Type
				interp_type_call receiver, expr

			when Tape::Func_Signature
				raise Tape::Cannot_Call_Func_Signature.new expr

			else
				raise Tape::Receiver_Is_Not_Callable.new expr.receiver
			end
		end

		# @param expr [Tape::Type_Expr]
		def interp_type expr
			return interp_anonymous_composition expr if expr.anonymous_composition

			# No body was parsed (`x: Abc\<Number>`, `y := Abc\<Number>`, `Abc\<Number>()`, `Abc\<4815>()`) so this references an existing type rather than declaring one. Dup it so tagging this reference doesn't mutate the shared declaration every other reference sees.
			if expr.expressions.nil?
				if expr.tag
					supplied = resolve_tag_reference expr, allow_spread: false

					# note; `expr.name` is normally a real type name ("String"), but if it's instead a local alias bound to an earlier tagged reference (`X := String\<Flying>`), re-tag against *that value's own* family name rather than treating "X" itself as a type name. So `X\<duck>` should behave exactly like `String\<duck>`, since `.name` on any Type object (dup'd or not) always reflects its true declared family.
					aliased     = find_in_stack expr.name
					lookup_name = aliased.is_a?(Tape::Type) ? aliased.name : expr.name

					existing = find_tagged_type_variant lookup_name, supplied

					# Declaring spreads a lone unnamed Struct-valued member (#interp_struct); unify by retrying a failed unspread match with spreading applied, rather than statically committing to one or the other.
					if !existing.is_a?(Tape::Type) && expr.tag.is_a?(Tape::Struct_Expr) && expr.tag.types.length == 1 && expr.tag.names[0].nil?
						spread_supplied = interp_struct expr.tag, allow_spread: true
						spread_existing = find_tagged_type_variant lookup_name, spread_supplied
						if spread_existing.is_a? Tape::Type
							supplied = spread_supplied
							existing = spread_existing
						end
					end
					unless existing.is_a? Tape::Type
						# Nothing declared under this name -> bare named struct (see Bare Named Structs, CLAUDE.md). Also allows re-declaring the same struct with an identical shape as a no-op.
						redeclaring_same_struct = aliased.is_a?(Tape::Struct) && aliased.name == expr.name && aliased.structure_declaration_equal?(supplied)
						if (aliased.nil? || redeclaring_same_struct) && tagged_variants_for(lookup_name).empty?
							supplied.name = expr.name # `@`-only (`@.name`)
							prefix_type supplied, expr.name
							stack.last.declare expr.name, supplied if supplied.names.all?
							return supplied
						end

						# Base name is a real Type but nothing matches this shape yet -- a bare reference auto-declares it (empty body), same as writing `Array\String {}` explicitly first.
						unless aliased.is_a? Tape::Type
							raise Tape::Undeclared_Tagged_Type.new(expr)
						end
						existing                = declare_tagged_type_variant lookup_name, supplied, []
					end
				else
					existing = find_in_stack expr.name
					unless existing.is_a? Tape::Type
						raise Tape::Undeclared_Identifier.new(expr)
					end
				end

				# Object#dup is shallow so  @declarations/@static_declarations would still be the exact same Hash/Set every reference and the matched variant share, so tagging one would silently mutate all the others (and the variant itself). Fork them explicitly.
				referenced                     = existing.dup
				referenced.declarations        = existing.declarations.dup
				referenced.static_declarations = (existing.static_declarations || ::Set.new).dup
				if expr.tag
					# Call-site member values are usually positional (`Woof<'hello', 4815>`), but a member can be named at the reference site too (`Woof<key := 'hello'>`) to disambiguate an otherwise-ambiguous match. Either way, re-associate them with the names — and pick up any defaults — from the matched variant's own struct declaration (`Woof<String, key: Dictionary> {}`) so `.tag.key` still works on the resulting instance.
					declaration            = existing.tag_declaration
					declaration_names      = declaration.is_a?(Tape::Struct) ? declaration.names : []
					declaration_types      = declaration.is_a?(Tape::Struct) ? declaration.type_objects : [] # declared type objects, used below only to detect an unfilled default via identity
					declaration_type_names = declaration.is_a?(Tape::Struct) ? declaration.type_names : []
					declaration_values     = declaration.is_a?(Tape::Struct) ? declaration.values : []

					# A default only fills in for a member that just re-asserts the declaration's own declared type for that member (`Abc<Dictionary>()`, re-stating `dict`'s own type rather than giving it a value) — never when a real value was actually supplied there (`Abc<{x=1}>()` must keep {x=1}, not fall back to the default). That check has to run against `supplied.type_objects` (identity against the declared type), since that's what "just restated the type" even means -- but the *result*, when it's a real value, has to be `supplied.values`, not `type_objects`. A bare `name := value` reference member (see #interp_struct) resolves its own `type_objects` entry down to the value's *inferred type*, not the value itself, so using `type_objects` here for both the check and the result silently substituted the wrong thing for exactly that case.
					resolved_values = supplied.values.each_with_index.map do |real_value, i|
						name     = declaration_names[i]
						type_obj = supplied.type_objects[i]
						if name && !declaration_values[i].nil? && type_obj.equal?(declaration_types[i])
							declaration_values[i]
						else
							real_value
						end
					end

					# `supplied.type_objects`, not `resolved_values`, for the types argument -- a schema-only unnamed member's own value is nil (see #interp_struct), no longer interchangeable with its type object the way `resolved_values` (built for the *values* result, see the comment above) used to assume.
					referenced.tag_instance                     = build_struct declaration_names, declaration_type_names, supplied.type_objects, resolved_values
					referenced.tag_instance.bare_reference_name = supplied.bare_reference_name

					# Carry a chained tag (`Ab\Cd\Ef`) across the rebuild above, which only re-associates the top level's own members.
					if supplied.tag_instance
						referenced.tag_instance.tag_instance = supplied.tag_instance
						declare_tag referenced.tag_instance
					end
				end
				declare_tag referenced
				return referenced
			end

			return interp_struct_composition expr if expr.struct_body

			if expr.tag
				interp_tagged_type_declaration expr
			else
				interp_bare_type_declaration expr
			end
		end

		# A composition chain with no `{}` body (`Abc|Def`, `A & B`, ...) is a value, not a declaration, built by applying the chain to a fresh, unnamed Type exactly as if `X | Abc | Def { }` had been written for some unnamed X.
		def interp_anonymous_composition expr
			anonymous             = Tape::Type.new nil
			anonymous.types       = ::Set.new # Type#initialize seeds `@types = ::Set[name]` -- ::Set[nil] here, which would leave a stray nil in .types (breaking #find_ruby_class_for_type's `"Tape::#{type_name}"` lookup) since the union step below only ever adds, never resets.
			anonymous.expressions = [] # A real declaration always ends up with this set (even to []) via #interp_bare_type_declaration's own body-merge -- there's no body here, but #run_type_body_on_instance still expects an Array to iterate when constructing an instance.

			push_then_pop anonymous do
				# A bare prefix chain (`x := |Compo`) has no base name to seed with -- only the two-name form (`Base | Compo`) needs Base unioned in first.
				if expr.name
					seed            = Tape::Composition_Expr.new
					seed.operator   = Tape::Lexeme.new(:operator, '|')
					seed.identifier = Tape::Identifier_Expr.new.tap { |it| it.lexeme = Tape::Lexeme.new(:Identifier, expr.name) }
					interp_composition seed
				end

				expr.expressions.each { |composition| interp_composition composition }
			end

			anonymous
		end

		# Shared tail of both declaration paths below: parent the type to the declaring scope, link it to its Tape:: Ruby class when one exists, record its own name in @types, and run `body_expressions` in the type's scope.
		def finish_type_declaration type, body_expressions
			type.enclosing_scope = stack.last

			tape_name = "Tape::#{type.name}"
			defined   = type.name[0] != '_' && Object.const_defined?(tape_name) # note; #const_defined? does not allow underscore as the first character, hence the underscore check.
			link_instance_to_type type, type.name if defined

			type.types ||= ::Set.new
			type.types.add type.name

			type.declaration_in_progress = true
			begin
				push_then_pop type do
					body_expressions.each do |sub_expr|
						# A bare composition (`| Compo`) only means anything as a direct top-level item of a type's own body -- dispatch it explicitly rather than through #interpret's generic case (which raises).
						sub_expr.is_a?(Tape::Composition_Expr) ? interp_composition(sub_expr) : interpret(sub_expr)
					end
				end
			ensure
				type.declaration_in_progress = false
			end

			type
		end

		# A plain, untagged declaration (`String { ... }`) -- reopens/extends the same shared Type object across multiple declarations of the same bare name, e.g. how global.tape's files each contribute to the same base String/Array/etc.
		def interp_bare_type_declaration expr
			existing = stack.last.has?(expr.name) && stack.last[expr.name]
			# Tape::Struct < Instance < Type, so a plain `existing.is_a?(Tape::Type)` check also matches a Bare
			# Named Struct value sharing this name (`User <...>` then later `User | Table {}`) -- that's a value,
			# not a reopenable declared Type, so it must be excluded here or the struct itself gets mistakenly
			# reused/mutated as the new composed Type's own scope.
			type = (existing.is_a?(Tape::Type) && !existing.is_a?(Tape::Instance)) ? existing : Tape::Type.new(expr.name)

			type.expressions = (type.expressions || []) + expr.expressions
			finish_type_declaration type, expr.expressions

			stack.last.declare type.name, type
			type
		end

		# Resolves one `\` RHS node to a real Tape::Struct. An inline literal (`Abc\<Number>`) interprets to one directly; a named reference (`Abc\Task_Schema`) is used as-is if it's already a Struct, or wrapped into the single-unnamed-member equivalent if it's a Type (`Abc\String` behaves like `Abc\<String>`); anything else raises. A named reference also records its own identifier text as `bare_reference_name` (see Struct#bare_reference_name) -- the *only* signal that later tells #tag_display_name to print `Array\String` back out bare instead of falling back to the struct's own `<...>` rendering. A nested `.tag` on the node (`Ab\Cd\Ef`) is resolved recursively and hung off this struct's own `.tag`, so `x.tag.tag` walks the chain; `\<...>` is always terminal.
		def resolve_tag_node tag_node, allow_spread: true
			struct = if tag_node.is_a? Tape::Struct_Expr
				interp_struct tag_node, allow_spread: allow_spread
			else
				value = interpret tag_node
				case value
				when Tape::Struct
					value.bare_reference_name ||= tag_node.value
					value
				when Tape::Type
					# The single member's own value stays nil, same as any other schema-only member (see #interp_struct) -- `value` here is always a bare Type, not real data.
					wrapped                     = build_struct [nil], [type_name_to_string(value)], [value], [nil]
					wrapped.bare_reference_name = tag_node.value
					wrapped
				else
					raise Tape::Tag_Reference_Must_Be_Type_Or_Struct.new(tag_node)
				end
			end

			if tag_node.respond_to?(:tag) && tag_node.tag
				struct.tag_instance = resolve_tag_node tag_node.tag, allow_spread: allow_spread
				declare_tag struct
			end

			struct
		end

		def resolve_tag_reference expr, allow_spread: true
			resolve_tag_node expr.tag, allow_spread: allow_spread
		end

		# Normalizes the RHS of a `.tag =` to its tag Struct: a Struct is itself; a Type/Instance contributes its own `.tag_instance`, or is wrapped as a single-member struct when it has none (mirrors #resolve_tag_node's bare-Type case).
		def tag_struct_for_reassignment value, node
			return value if value.is_a? Tape::Struct
			return value.tag_instance if value.respond_to?(:tag_instance) && value.tag_instance
			return build_struct [nil], [type_name_to_string(value)], [value], [nil] if value.is_a? Tape::Type
			raise Tape::Tag_Reference_Must_Be_Type_Or_Struct.new(node)
		end

		# A tagged declaration (`String\<dict: Dictionary> { ... }`) is its own type, separate from the bare `String` and every other tag under the same name -- this stops one variant's `new`/methods from clobbering another's (a real bug this fixed).
		def interp_tagged_type_declaration expr
			struct = resolve_tag_reference expr
			declare_tagged_type_variant expr.name, struct, expr.expressions
		end

		# Shared by a real declaration and an auto-declared reference (interp_type) -- both just extend-or-create a Type variant under `name` tagged with `struct`.
		def declare_tagged_type_variant name, struct, body_expressions
			existing = tagged_variants_for(name, current_scope_only: true).find do |variant|
				variant.tag_declaration.structure_declaration_equal?(struct) &&
					tag_chains_equal?(variant.tag_declaration.tag_instance, struct.tag_instance)
			end

			if existing
				variant = existing
			else
				variant             = Tape::Type.new(name)
				blueprint           = stack.last.has?(name) && stack.last[name]
				variant.expressions = blueprint.is_a?(Tape::Type) ? (blueprint.expressions || []).dup : []
			end

			variant.expressions     = (variant.expressions || []) + body_expressions
			variant.tag_declaration = struct

			# A reopened variant already ran its earlier body when it was declared, so only the new expressions run now (matching the bare path). A fresh variant runs everything, including the bare blueprint's copied body.
			finish_type_declaration variant, (existing ? body_expressions : variant.expressions)

			stack.last.tagged_type_variants[name] << variant unless existing
			variant
		end

		# A struct-typed param (`right: <name: String, ...>`) is structural, not nominal -- any argument with those declarations, compatibly typed, satisfies it. Raises Type_Contract_Violation on mismatch. `Any` is a wildcard.
		def check_struct_type_contract param, value, expr
			# Interpreted fresh per call, not cached -- a Param_Expr can be shared across Interpreter instances.
			struct = interp_struct param.type, allow_spread: false

			struct.names.each_with_index do |name, i|
				next unless name # unnamed members have nothing to check by name

				declared_type = struct.type_names[i]
				next if declared_type == 'Any'

				unless value.is_a?(Tape::Scope) && value.has?(name)
					raise Tape::Type_Contract_Violation.new(expr, "<#{struct.names.compact.join(', ')}>", describe_value_shape(value))
				end

				member_value = value.get name
				candidates   = member_value.nil? ? [] : member_candidate_type_names(member_value)
				unless candidates.include? declared_type
					raise Tape::Type_Contract_Violation.new(expr, declared_type, inferred_type_name(member_value))
				end
			end
		end

		# A `@splat`/`@splatr` param's nominal `: Type` annotation is load-bearing -- it names the
		# members the body reaches unprefixed -- so enforce it (unlike a plain param annotation, which
		# stays runtime-unchecked). Otherwise the wrong shape only surfaces as an `Undeclared_Identifier`
		# deep in the body, once an expected member turns up missing.
		def check_splat_param_type_contract param, value, expr
			return unless param.respond_to?(:add_to_readable) && (param.add_to_readable || param.add_to_writable)
			return unless param.type.is_a?(Tape::Identifier_Expr) && param.type.value != 'Any'
			return if type_contract_satisfied?(maybe_instance(value), param.type.value)

			raise Tape::Type_Contract_Violation.new(expr, param.type.value, describe_value_shape(value))
		end

		# All type names a supplied member value could match a declared struct's member under -- its own primary name first, then everything it composes, so e.g. a `Div` satisfies a member declared `Dom` without being named Dom itself. See #find_tagged_type_variant.
		def member_candidate_type_names value
			case value
			when ::Integer then ['Integer', 'Number']
			when ::Float then ['Float', 'Number']
			when ::BigDecimal then ['Decimal', 'Number']
			when ::String
				['String']
			when ::Symbol
				['Symbol']
			when ::TrueClass, ::FalseClass
				['Bool']
			else
				if value.is_a?(Tape::Type) && value.types && !value.types.empty?
					value.types.to_a
				else
					[value.name]
				end
			end
		end

		# Finds the declared variant a reference's supplied tag matches. A reference member can optionally be named (`String\<other := {x=1}>()`, reusing the same bare-`:=` idiom declarations use) to disambiguate when more than one declared variant would otherwise match by type alone. Narrows to variants agreeing on every explicitly-named member first, then prefers an exact type match before falling back to anything a value merely composes.
		def find_tagged_type_variant base_name, supplied
			values = supplied.type_objects
			return nil if values.nil?

			variants = tagged_variants_for base_name
			return nil if variants.empty?

			candidate_lists = values.map { |value| member_candidate_type_names value }
			return nil if candidate_lists.any?(&:empty?)

			names      = supplied.names || []
			candidates = variants.select do |variant|
				declared_names = variant.tag_declaration.names
				names.each_with_index.all? { |name, i| name.nil? || declared_names[i] == name }
			end

			# A chained tag (`Ab\Cd\Ef`) only matches a variant whose own declared chain matches in lockstep.
			candidates = candidates.select { |variant| tag_chains_satisfy? variant.tag_declaration.tag_instance, supplied.tag_instance }

			exact_types = candidate_lists.map(&:first)
			candidates.find { |variant| variant.tag_declaration.type_names == exact_types } ||
				candidates.find { |variant| variant.tag_declaration.satisfied_by_candidates? candidate_lists }
		end

		# Exact structural equality of two tag-chain links, recursively down `.tag_instance`. Both-nil is equal, so an unchained tag is unaffected. Used for declaration-time collision (does `Ab\Cd\Ef {}` reopen an existing variant, or start a new one?).
		def tag_chains_equal? a, b
			return true if a.nil? && b.nil?
			return false if a.nil? || b.nil?
			a.structure_declaration_equal?(b) && tag_chains_equal?(a.tag_instance, b.tag_instance)
		end

		# Compositional (`=>=`-style) match of a declared tag chain against a supplied one, in lockstep down `.tag_instance`. Used for reference resolution.
		def tag_chains_satisfy? declared, supplied
			return true if declared.nil? && supplied.nil?
			return false if declared.nil? || supplied.nil?

			lists = (supplied.type_objects || []).map { |value| member_candidate_type_names value }
			return false if lists.length != declared.type_names.length
			return false unless declared.type_names == lists.map(&:first) || declared.satisfied_by_candidates?(lists)

			tag_chains_satisfy? declared.tag_instance, supplied.tag_instance
		end

		# Tagged variants declared under `base_name`, searched the same way #find_in_stack resolves a plain identifier -- innermost to outermost, stopping at the first scope that has any (lexical shadowing, not merging). `current_scope_only` restricts the search to `stack.last` alone, for declaration-time collision checks -- a nested tagged declaration should only ever collide with another declared in that exact scope, never one from an enclosing one.
		def tagged_variants_for base_name, current_scope_only: false
			scopes = current_scope_only ? [stack.last] : stack.reverse_each
			scopes.each do |scope|
				# `stack` can briefly hold non-Scope receivers during dot-access (e.g. Tape::Range).
				next unless scope.respond_to? :tagged_type_variants
				list = scope.tagged_type_variants.fetch(base_name, [])
				return list unless list.empty?
			end
			[]
		end

		# Every declared tagged-type variant under Global (Table-composed models are always top-level).
		def all_tagged_type_variants
			global.tagged_type_variants.values.flatten
		end

		# For Tape::Database#proxy_create_table: finds the Table-composed type declared with this exact schema, if any, so the created table can be tagged with the model's real identity. Nil if none matches.
		def find_table_type_for_schema schema
			all_tagged_type_variants.find do |variant|
				variant.types.include?('Table') && variant.tag_declaration&.structure_declaration_equal?(schema)
			end
		end

		# Searches the full scope stack (innermost to outermost) for `key`, the same way a bare identifier resolves via #scope_for_identifier -- checking only `stack.last` would miss a type declared in an outer/global scope while evaluating from inside a nested context (e.g. a type's own declaration body during composition). This returns an Drive type. `excluding:` skips scopes of that class -- used by #find_operator_overload to keep looking past a currently-executing Type/Instance body, since merely being on the stack doesn't mean the *current* operands belong to it (Instance < Type, so excluding: Tape::Type skips both).
		def find_in_stack key, excluding: nil
			stack.reverse_each do |scope|
				next if excluding && scope.is_a?(excluding)
				return scope[key] if scope.has? key
			end
			nil
		end

		# Mirrors how this tag was actually written, not a guess from its resulting shape -- `Array\<String>` and `Array\String` produce an identically-shaped single-unnamed-member struct, so shape alone can't tell them apart (confirmed the hard way: an earlier version of this method used exactly that heuristic). `bare_reference_name` (see Struct#bare_reference_name/#resolve_tag_reference) is the one place that signal survives past parsing, so a bare identifier RHS (`\Type`, `\Named_Struct`) always redisplays bare, and everything else (`\<...>`, however many members) always falls back to the struct's own `<...>` rendering.
		def tag_display_name scope
			tag       = scope.tag_instance
			qualifier = tag.bare_reference_name || stringify_for_display(tag)
			"#{scope.name}#{Tape::TAG_OPERATOR}#{qualifier}"
		end

		# Makes `.tag` readable via Drive dot-access on a Type, Instance, or type reference, and marks it static so it's also readable straight off a bare Type (not just an instance). Only adds the declaration when this particular one actually has a tag, so plain untagged types don't pick up a stray `tag` member. Also refreshes `.display_name` (see Type#initialize) to fold the tag into the type's own displayable name, so a consumer like tapes/member.tape's `to_s` never needs to know `.tag` exists at all.
		def declare_tag scope
			return unless scope.tag_instance

			scope.declarations['tag'] = scope.tag_instance
			scope.display_name        = tag_display_name(scope)
			scope.static_declarations = (scope.static_declarations || ::Set.new) + %w(tag)
		end

		#
		# Tape::Type_Expr is converted to Tape::Type in #interp_type.
		# Tape::Instance inherits Tape::Type's @name and @types.
		#
		#     (See types.rb for Tape::Type and Tape::Instance declarations)
		#     (See expressions.rb for Tape::Type_Expr declaration)
		#
		# - Push instance onto stack
		# - Interpret type.expressions so the declarations are made on the instance
		# - Keep instance on the stack
		# - For each Tape::Func declared on instance, set `func.enclosing_scope = instance`
		# - Interpret type[:Self], the initializer
		# - Delete :Self from instance, inheritd from type, not needed on the instance
		#
		# note: There was a bug here where I wasn't popping the instance after interpreting the type's expressions. That caused the #new function below (func_new) to not properly interpret arguments passed to it.
		# note: We push type.enclosing_scope first (when present) so sibling types declared in the same scope can be found during instantiation.
		def run_type_body_on_instance type, instance
			interpret_instance_body = -> do
				push_then_pop type do
					push_then_pop instance do |scope|
						type.expressions.each do |expr|
							# Skip static declarations - they were already executed during type definition and shouldn't be re-executed for each instance
							next if static_var_declaration_expr? expr

							# `@x := ...` on the Context runs once in the type body, not per instance.
							next if context_declaration_expr? expr

							if expr.is_a?(Tape::Func_Expr) && expr.name.is_a?(Tape::Identifier_Expr) &&
							   expr.name.scope_operator&.value == 'Self'
								next
							end

							# Same bypass as #finish_type_declaration's body walk, re-run per instance here.
							expr.is_a?(Tape::Composition_Expr) ? interp_composition(expr) : interpret(expr)
						end
					end
				end
			end

			if type.enclosing_scope
				push_then_pop type.enclosing_scope do
					interpret_instance_body.call
				end
			else
				interpret_instance_body.call
			end

			instance.declarations.each do |key, decl|
				next unless decl.is_a? Tape::Func

				cloned                     = decl.dup
				cloned.enclosing_scope     = instance
				instance.declarations[key] = cloned
			end
		end

		# Builds the raw instance for #interp_type_call: backed by its Tape:: Ruby class when one exists, linked to its type, struct bound, and the type's body run on it. `Self(;)` is invoked afterward by #interp_type_call itself.
		def build_instance_of_type type, expr
			ruby_class = find_ruby_class_for_type type
			instance   = ruby_class ? ruby_class.new : Tape::Instance.new(type.name)

			# `.name` / `.types` are both `@`-only now (`@.name` / `@.types`) -- the Ruby-level attrs are
			# the store. Setting `.name` here matters for a composed type sharing a built-in's Ruby class
			# (`Tasks | Table {}` -> Tape::Table baked in "Table"); `@.name` must report "Tasks".
			instance.name            = type.name
			instance.types           = type.types
			instance.enclosing_scope = type
			instance.expressions     = type.expressions

			# note; Bind structs onto the instance before the type's expressions (and therefore `new`) are interpreted below, so `Self(;)`'s own body can reference `.tag`. This is a completely separate binding path from the call's own arguments — member values never get forwarded into `new`'s params.
			effective_tag = type.tag_instance || type.tag_declaration
			if effective_tag
				instance.tag_instance = effective_tag
				declare_tag instance
			end

			run_type_body_on_instance type, instance
			instance
		end

		def interp_type_call type, expr
			instance = build_instance_of_type type, expr

			func_new = instance[:Self]

			# A Dom element accepts whitelisted named arguments (`Button("x", onclick := `...`, html_id
			# := 'y')`) that aren't `new`'s own params -- they're pulled out here and set on the instance
			# after construction, so an element (and its handler) can be described in one expression
			# instead of a member declaration plus later assignment. Non-Dom types, and any name outside
			# the whitelist, are untouched -- interp_func_body still raises Unknown_Named_Argument.
			dom_props = dom_type?(type) ? split_dom_prop_arguments(expr, func_new) : {}
			call_expr = dom_props.empty? ? expr : expr.dup.tap { |e| e.arguments = e.arguments - dom_props.values }

			if func_new
				interp_func_body func_new, call_expr
			elsif call_expr.arguments.count > 0
				# No initializer was declared so we have nowhere to pass the arguments
				raise Tape::Arguments_Given_But_Not_Expected.new(expr)
			end

			instance.delete :Self

			dom_props.each { |name, arg| instance.declare name, interpret(classify_argument(arg).last) }

			instance
		end

		def dom_type? type
			type.is_a?(Tape::Type) && type.types.include?('Dom')
		end

		def dom_constructor_prop_name? name
			Tape::DOM_CONSTRUCTOR_PROP_NAMES.include?(name) ||
				Tape::DOM_CONSTRUCTOR_PROP_PREFIXES.any? { |prefix| name.start_with? prefix }
		end

		# @return [Hash{::String => Tape::Expression}] whitelisted `name := value` arguments keyed by
		#   name, mapped to their original argument node. A name that IS one of `new`'s declared params
		#   is left alone (bound normally), so an explicit param always wins over the prop shortcut.
		def split_dom_prop_arguments call_expr, func_new
			declared = func_new ? func_new.parameters.map { |param| param.name&.value } : []
			call_expr.arguments.each_with_object({}) do |arg, props|
				kind, name, = classify_argument arg
				next unless kind == :named && dom_constructor_prop_name?(name) && !declared.include?(name)
				props[name] = arg
			end
		end

		def interp_func_signature expr
			signature = build_func_signature expr

			if expr.name&.value
				stack.last.declare expr.name.value, signature
				# Recorded so a later plain reassignment (`double = ...`, a bare Identifier_Expr with
				# no annotation of its own) still resolves back to this signature to check against --
				# mirrors what #interp_infix_assignment records for the `name: {...} = value` form.
				# Without this, a bare declaration (`double: (Number -> Number;)`, no `=`) left nothing
				# for #resolve_func_signature to find, so `double = (String -> String;)` right after
				# went unchecked.
				stack.last.type_by_identifier[expr.name.value] = signature
			end

			signature
		end

		def interp_func expr
			func                 = Tape::Func.new expr.lexeme
			func.name            = expr.lexeme
			func.enclosing_scope = stack.last
			func.expressions     = expr.expressions
			func.parameters      = expr.parameters
			func.func_expr       = expr
			param_types          = expr.parameters.map do |p|
				p.type&.value
			end
			func.func_signature  = Tape::Func_Signature.new(param_types, expr.type&.value)

			if func.name&.value
				stack.last.declare func.name.value, func

				track_static_declaration stack.last, expr.name
			end

			func
		end

		def interp_func_body func, expr, arg_values: nil
			# A bare Capitalized/UPPERCASE param (`f ( ABC; ABC )`) parses as a signature-literal-style bare type (`param.type` set, `param.name` left nil, see #parse_func) rather than a named param -- real function params always start lowercase. Every other param-binding path below assumes `.name` is always present, so this is checked once, up front, with a real error instead of a raw NoMethodError the first time something reads `param.name.value`.
			nameless_param = func.parameters.find { |param| param.name.nil? }
			raise Tape::Invalid_Parameter_Name.new(expr, nameless_param.type.value) if nameless_param

			# note; Evaluate arguments in caller's scope (before pushing function scopes). A labeled argument (`to: someone`) parses as a plain `:` Infix_Expr, and a named argument (`to := someone`) as a plain `:=` Infix_Expr (same production named struct members use) -- #classify_argument unwraps either rather than letting #interpret try to resolve `to` as an identifier and raise Undeclared_Identifier.
			# A caller that already evaluated the operands (operator-overload dispatch in #interp_infix) passes them via arg_values so their side effects don't run a second time; labels/named args only exist in real call syntax, so neither applies there.
			arg_labels = []
			named_args = {}
			arg_values ||= begin
				seen_named = false
				positional = []

				expr.arguments.each do |arg|
					kind, name_or_label, value_expr = classify_argument arg

					# Named arguments must come last -- once you switch to naming arguments, every argument after that has to be named too. A positional argument (bare or labeled) can never follow one.
					if seen_named && kind != :named
						raise Tape::Positional_Argument_After_Named.new(expr)
					end

					if kind == :named
						seen_named = true
						raise Tape::Duplicate_Named_Argument.new(expr, name_or_label) if named_args.key? name_or_label
						named_args[name_or_label] = interpret value_expr
					else
						arg_labels << (kind == :labeled ? name_or_label : nil)
						positional << interpret(value_expr)
					end
				end

				positional
			end

			# note: `func` is the single, shared Func object registered when the function was declared. Pushing it directly as the call frame (as this used to do) meant every invocation declared its params onto that same shared object, so recursive/repeated calls stomped on each other's param values. Each call gets its own fresh scope instead.
			call_scope                 = Tape::Func.new func.name
			call_scope.expressions     = func.expressions
			call_scope.parameters      = func.parameters
			call_scope.enclosing_scope = func.enclosing_scope
			call_scope.arguments       = arg_values
			call_scope.func_expr       = func

			# Push type scope if calling an instance method (instance methods need access to type-level declarations)
			# Also push the type's enclosing_scope so sibling types can be found
			if func.enclosing_scope.is_a?(Tape::Instance) && func.enclosing_scope.enclosing_scope
				type = func.enclosing_scope.enclosing_scope
				push_scope type.enclosing_scope if type.enclosing_scope # Push the Type's enclosing scope
				push_scope type # Push the Type
			end
			push_scope func.enclosing_scope
			push_scope call_scope

			has_variadic = func.parameters.any?(&:variadic)

			# Validated up front, before binding, so a typo'd name reports as "not a declared parameter" rather than getting masked by whatever other param that typo incidentally starved of a value (a confusing Missing_Argument with no mention of the real mistake).
			# A variadic func skips this -- an unknown named arg binds by its own name instead (see below).
			unless named_args.empty? || has_variadic
				declared_names = func.parameters.map { |param| param.name.value }
				unknown_name   = named_args.keys.find { |name| !declared_names.include? name }
				raise Tape::Unknown_Named_Argument.new(expr, unknown_name) if unknown_name
			end

			if func.parameters.empty? && arg_values.any?
				raise Tape::Arguments_Given_But_Not_Expected.new(expr)
			end

			consumed_variadic = false
			func.parameters.each_with_index do |param, i|
				name_key = param.name.value

				if param.variadic
					tail = arg_values[i..] || []
					if named_args.key? name_key # `rest := <value>` at the call site
						nv = named_args.delete name_key
						raise Tape::Type_Contract_Violation.new(expr, 'Arguments', inferred_type_name(nv)) unless nv.is_a? Tape::Array
						tail = nv.values # `rest := [99]` -> tail [99]  (`rest := 99` errored above)
					end
					stack.last.declare name_key, wrap_arguments_array(tail)
					consumed_variadic = true
					next
				end

				has_positional = !consumed_variadic && i < arg_values.length
				has_named      = named_args.key? name_key

				if has_positional && has_named
					raise Tape::Argument_Given_By_Name_And_Position.new(expr, name_key)
				end

				value = if has_named
					named_args.delete name_key
				elsif has_positional
					arg_values[i]
				elsif param.default
					interpret param.default
				else
					raise Tape::Missing_Argument.new(expr)
				end

				# Labels are positional, not a lookup key -- a labeled argument at position `i` must match that position's declared label (Swift/ObjC-style), never used to reorder arguments. A bare, unlabeled argument is always accepted regardless of whether the param declares a label -- labels are opt-in at the call site, not mandatory. Named arguments bypass label-checking entirely -- they're matched by declared name, not position, so there's no positional label to compare against.
				supplied_label = arg_labels[i]
				if !has_named && supplied_label && supplied_label != param.label&.value
					raise Tape::Argument_Label_Mismatch.new(expr, param.label&.value, supplied_label)
				end

				check_struct_type_contract param, value, expr if param.type.is_a?(Tape::Struct_Expr)
				check_splat_param_type_contract param, value, expr

				stack.last.declare param.name.value, value

				if value.is_a? Tape::Type
					if param.respond_to?(:add_to_readable) && param.add_to_readable
						call_scope.add_readable_scope value
					elsif param.respond_to?(:add_to_readable) && param.add_to_writable
						call_scope.add_writable_scope value
					end
				end

			end

			# The nicety: with a variadic param, named args that matched no param bind by their own name.
			if has_variadic
				declared = func.parameters.map { |p| p.name.value }
				named_args.each { |k, v| stack.last.declare(k, v) unless declared.include?(k) }
			end

			body = call_scope.expressions
			if call_scope.name == 'assert'
				raise Tape::Assert_Triggered.new(expr) unless interpret(body.first) == true # Just to be explicit.
			end

			result = nil
			body.compact.each do |e|
				result = interpret e
				break if result.is_a? Tape::Return
			end

			Drive.assert pop_scope == call_scope
			Drive.assert pop_scope == func.enclosing_scope

			if func.enclosing_scope.is_a?(Tape::Instance) && func.enclosing_scope.enclosing_scope
				type = func.enclosing_scope.enclosing_scope
				Drive.assert pop_scope == type
				pop_scope if type.enclosing_scope # Pop the Type's enclosing scope
			end

			return_value = result.is_a?(Tape::Return) ? result.value : result

			if func.func_signature.return_type
				# Compositional, not exact-name -- a `-> Table` returning a `Task`-composed value is a safe
				# covariant return. `#type_contract_satisfied?` also short-circuits `-> Any` (the universal
				# wildcard) and an exact name match before this compositional check.
				actual_type = type_name_to_string return_value
				unless type_contract_satisfied?(return_value, func.func_signature.return_type)
					raise Tape::Type_Contract_Violation.new(expr, func.func_signature.return_type, actual_type)
				end
			end

			return_value
		end

		# Classifies a call argument's syntactic form:
		#   - `name := value` (named)   -- parses as a plain `:=` Infix_Expr, same production a struct
		#     member's bare default uses. Matched by the callee's declared param *name*, not position.
		#   - `label: value` (labeled)  -- parses as a plain `:` Infix_Expr, same production named
		#     struct members use. Matched against whatever label is declared at that *position*.
		#   - anything else (positional)
		# Returns [kind, name_or_label, value_expr] -- name_or_label is nil for :positional. Never interprets `arg`/the name-or-label side itself; that's the caller's job once it knows which expression actually holds the real value.
		def classify_argument arg
			if arg.is_a?(Tape::Infix_Expr) && arg.operator&.value == ':=' && arg.left.is_a?(Tape::Identifier_Expr)
				[:named, arg.left.value, arg.right]
			elsif arg.is_a?(Tape::Infix_Expr) && arg.operator&.value == ':' && arg.left.is_a?(Tape::Identifier_Expr)
				[:labeled, arg.left.value, arg.right]
			else
				[:positional, nil, arg]
			end
		end

		# `<name: String, age: Number>` alone is a structure-only (each named member's declared type, no real data yet; see #interp_struct). `()` is how you turn that struct into an actual instance: the call's own arguments become each member's real value. Goes through #build_struct like every other struct construction so a declared `Struct` type's own body/methods still run.
		#
		# Arguments can be positional (matched by index, same order as declared) or named (`name := value`,
		# matched by the member's declared *name* -- #classify_argument, same production/mechanism
		# #interp_func_body already uses for named function arguments). A `label: value` argument has no
		# struct equivalent to check a label against, so it's treated as plain positional, same as an
		# unlabeled one. A member the call doesn't supply (positionally or by name) is left unset, same
		# as it always has been -- structs don't raise Missing_Argument the way functions do; Struct.new's
		# own values[i].nil? ? types[i] fallback (struct.rb) is what shows it as type-only.
		#
		# @param struct [Tape::Struct]
		# @param expr [Tape::Call_Expr]
		def interp_struct_call struct, expr
			named_args = {}
			positional = []
			seen_named = false

			expr.arguments.each do |arg|
				kind, name_or_label, value_expr = classify_argument arg

				if seen_named && kind != :named
					raise Tape::Positional_Argument_After_Named.new(expr)
				end

				value = wrap_string_literal_value(value_expr, interpret(value_expr))

				if kind == :named
					seen_named = true
					raise Tape::Duplicate_Named_Argument.new(expr, name_or_label) if named_args.key? name_or_label
					named_args[name_or_label] = value
				else
					positional << value
				end
			end

			unless named_args.empty?
				unknown_name = named_args.keys.find { |name| !struct.names.include? name }
				raise Tape::Unknown_Named_Argument.new(expr, unknown_name) if unknown_name
			end

			values = struct.names.each_index.map do |i|
				name_key       = struct.names[i]
				has_positional = i < positional.length
				has_named      = name_key && named_args.key?(name_key)

				if has_positional && has_named
					raise Tape::Argument_Given_By_Name_And_Position.new(expr, name_key)
				end

				if has_named
					named_args.delete(name_key)
				elsif has_positional
					positional[i]
				else
					# Neither supplied -- fall back to the schema's own declared default.
					struct.values[i]
				end
			end

			instance = build_struct struct.names, struct.type_names, struct.type_objects, values

			# #build_struct always links a fresh instance's `.types` to the shared, declared `Struct` type alone (`struct_type.types`, generically `['Struct']`) -- if `struct` (the schema being called) is itself named (see #interp_type's bare named struct handling), carry that name over too, own-name-first, so the constructed instance is `Ident | Struct`-shaped, not just generically Struct-shaped: === and a `-> Ident` return-type contract both key off `.types`.
			schema_name = struct.name
			if schema_name
				instance.name = schema_name # `@`-only (`@.name`); a `name` member owns plain `.name`
				prefix_type instance, schema_name
			end

			instance
		end

		# @param expr [Tape::Route_Expr]
		# @return Tape::Route
		def interp_route expr
			func = interpret expr.expression

			route                 = Tape::Route.new
			route.name            = func.name
			route.enclosing_scope = stack.last
			route.handler         = func
			route.http_method     = expr.http_method
			route.path            = expr.path
			route.path            = route.path[1..] if route.path.start_with? '/'
			route.param_names     = expr.param_names || []

			route.parts = route.path.split('/').reject do
				_1.empty?
			end

			# Always keyed by "method:path", even when the handler is a named function
			# (`get://path some_handler`) — the name identifies the *function*, not the route, and two
			# different routes can legitimately share one handler. Keying by name instead used to
			# collide in exactly that case, silently dropping every route but the last to reuse a name.
			route_key = "#{route.http_method.value}:#{route.path}"

			# Store route in the enclosing Type's @routes if it has one (e.g., Server)
			enclosing_type = stack.reverse.find do |scope|
				scope.is_a? Tape::Type # note: You could have an instance on the stack, or an empty scope, whatever.
			end
			if enclosing_type
				enclosing_type.routes            ||= {}
				enclosing_type.routes[route_key] = route
			end

			@route_functions_by_route_name[route_key] = route
			stack.last.declare route_key, route

			route
		end

		# @param route [Tape::Route] The route (or onclick handler wrapper) to execute
		# @param req [Tape::Request] Request object to inject
		# @param res [Tape::Response] Response object to inject
		# @param url_params [Hash] Extracted URL parameters (e.g., {"id" => "123"})
		# @param server_instance [Tape::Instance] The server instance (for accessing instance variables)
		# @return The result of handler execution
		def interp_route_body route, req, res, url_params = {}, server_instance: nil
			handler = route.handler
			params  = handler.parameters

			# A closure built inside a nested call (e.g. `btn.onclick = (;...)` written inside a type's
			# own `Self(;)`) has `.enclosing_scope` pointing at that call's own transient frame, not the
			# instance it truly belongs to -- the instance sits one or more levels further up that
			# frame's own `.enclosing_scope` chain. An ordinary dot-call (`w.render()`) never hits this:
			# #rebind_func_to_scope rebinds `.enclosing_scope` straight to the resolving instance at call
			# time. A route/onclick handler, invoked later from a request that built none of this, gets
			# no such rebind -- so the rest of the chain has to be restored by hand here, or a sibling
			# field the closure references (an onclick referencing another field on the same instance)
			# raises Undeclared_Identifier on every invocation after the one that originally built it.
			outer_chain = []
			scope       = handler.enclosing_scope&.enclosing_scope
			while scope && !stack.any? { |s| s.equal? scope }
				outer_chain << scope
				scope = scope.enclosing_scope
			end
			outer_chain.reverse_each { |s| push_scope s }

			call_scope = Tape::Scope.new "#{handler.name || 'anonymous'}_route"
			push_scope handler.enclosing_scope
			push_scope server_instance if server_instance
			push_scope call_scope

			# Make request and response available without explicit declaration
			call_scope.declare 'request', req
			call_scope.declare 'response', res

			# Bind URL parameters as function arguments. For example, get://:abc/:def ( abc, def; )
			params.each do |param|
				value = url_params[param.name.value] || url_params[param.name.value.to_sym]

				if value.nil?
					if route.param_names.include? param.name.value
						# todo: I haven't triggered this yet to ensure this works.
						raise Tape::Route_Param_Expected_But_Not_Found.new(route)
					end

					# Use default value or raise
					if param.default
						value = interpret param.default
					else
						# todo: Is this reachable?
						raise Tape::Missing_Argument.new(expr)
					end
				end

				call_scope.declare param.name.value, value
			end

			body   = handler.expressions
			result = nil

			body.compact.each do |expr|
				# bug todo: Sometimes body contains `nil` when that should never be the case
				result = interpret expr
				break if result.is_a? Tape::Return
			end

			if result.is_a? ::String
				res.declarations['body'] = result
			elsif result.is_a? Tape::Array
				html = ''
				result.values.each do |it|
					if it.is_a? ::String
						html += it
					elsif it.is_a?(Tape::Instance) && it.types.include?('Dom')
						html += render_dom_to_html it
					end
				end
				res.declarations['body'] = html
			elsif result.is_a? Tape::Instance
				# todo: Maybe find a better class name than Dom, and add a constant for it.
				if result.types.include? 'Dom'
					html                     = render_dom_to_html result
					res.declarations['body'] = html
				else
					res.declarations['body'] = result.inspect
				end
			end

			# Clean up scopes in reverse order
			popped_call = pop_scope
			Drive.assert popped_call == call_scope

			if server_instance
				popped_instance = pop_scope
				Drive.assert popped_instance == server_instance
			end

			popped_enclosing = pop_scope
			Drive.assert popped_enclosing == handler.enclosing_scope

			outer_chain.each { pop_scope }

			result
		end

		def interp_statement expr
			instance = Tape::Statement.new expr.expression
			# Capture the scope this literal was built in -- see Tape::Statement's class comment.
			instance.captured_scope = stack.last
			link_instance_to_type instance, 'Statement'

			# Unlike `Statement(...)` (which goes through #build_instance_of_type and runs the type's own body), a bare literal builds the Ruby object directly -- do that here too, or use_caller_scope/memoize/etc never get declared on the instance.
			type = instance.enclosing_scope
			if type
				instance.expressions = type.expressions
				run_type_body_on_instance type, instance
			end

			instance
		end

		# Enforces use_caller_scope/memoize for an already-built Tape::Statement (#interp_call's `Tape::Statement` branch). Immediate `` `expr`() `` and backtick items in percent/array literals never build a real Statement, so they skip this entirely.
		def invoke_statement statement
			return statement['_memoized_value'] if statement['memoize'] && statement['_memoized']

			result = if statement['use_caller_scope'] || statement.captured_scope.nil?
				interpret statement.expression
			else
				# Same trick as Func closures: push the captured scope back on top so lookup finds it before the caller's own frames. #push_then_pop returns #pop_scope's result, not the block's, so the value has to be captured from inside the block instead.
				captured_result = nil
				push_then_pop(statement.captured_scope) { captured_result = interpret(statement.expression) }
				captured_result
			end

			if statement['memoize']
				statement['_memoized']       = true
				statement['_memoized_value'] = result
			end

			result
		end

		# @param expr [Tape::Fence_Expr]
		def interp_fence expr
			# `expr.value` is the fence's body wrapped in a String_Expr, not yet interpreted -- passing
			# it straight to Tape::Fence.Self (as this used to) stored the raw AST node as the fence's
			# own value, so `@puts`ing a fence printed an object dump instead of its text. Interpret it
			# first, same as any other String_Expr, to get the real Ruby string.
			#
			# `Fence | String {}` (tapes/fence.tape, loaded by tapes/global.tape) is the real declared
			# Drive-level type for this -- link to it, not 'String' directly, mirroring Tape::Fence <
			# Tape::String on the Ruby side. Without linking to *some* declared type here, #stringify_
			# for_display's `to_s`/`to_string` lookup finds nothing and falls back to returning the
			# raw Ruby instance, which is what was actually causing the object dump -- not just the
			# un-interpreted value fixed above.
			finish_intrinsic_instance Tape::Fence.new(interpret(expr.value)), 'Fence' # note: Tape::Fence extends Tape::String
		end

		# @param expr [Tape::Html_Fence_Expr]
		def interp_html_fence expr
			interp_string expr.body
		end

		# `|`/`^` copy a mutable composed-in value (Array/Dictionary/Instance) by reference otherwise,
		# so every instance of every composing type would share the exact same object. Func/bare Type
		# values are untouched -- those are meant to stay shared.
		def dup_composed_value value
			return value unless value.is_a? Tape::Instance

			duped              = value.dup
			duped.declarations = value.declarations.dup

			case duped
			when Tape::Array
				duped.values                 = duped.values.dup
				duped.declarations['values'] = duped.values
			when Tape::Dictionary
				duped.hash                 = duped.hash.dup
				duped.declarations['hash'] = duped.hash
			end

			duped
		end

		def interp_composition expr
			# These are interpreted sequentially, so there are no precedence rules. I think that'll be better in the long term because there's no magic behind their evaluation. You can ensure the correct outcome by using these operators to form the types you need.

			right      = maybe_instance interpret expr.identifier
			unless right.is_a? Tape::Scope
				raise Tape::Invalid_Composition_With_A_Non_Scope_type.new(right)
			end
			curr_scope = stack.last

			case expr.operator.value
			when '|'
				# Union with Tape::Type

				right.declarations.each do |key, value|
					curr_scope[key] = dup_composed_value(value) unless curr_scope.has?(key)
				end

				curr_scope.static_declarations ||= ::Set.new
				curr_scope.static_declarations.merge right.static_declarations

				curr_scope.types ||= ::Set.new
				curr_scope.types.merge right.types
			when '~'
				# Removal of Tape::Type

				operand_keys_to_remove = right.declarations.keys

				# Maybe I'll have other keys to protect in the future.
				operand_keys_to_remove.reject! do |key|
					key.to_s == 'Self'
				end

				operand_keys_to_remove.each do |key|
					curr_scope.delete key
				end

				curr_scope.static_declarations.subtract right.static_declarations

				curr_scope.types.delete_if do |type|
					type == expr.identifier.value
				end
			when '&'
				# Intersection of Types, aka what they share.

				shared_keys    = right.declarations.keys.select do |key|
					curr_scope.has? key
				end
				keys_to_delete = curr_scope.declarations.keys - shared_keys

				keys_to_delete.each do |key|
					curr_scope.declarations.delete key
				end

				curr_scope.static_declarations = curr_scope.static_declarations & right.static_declarations

			when '^'
				# Symmetric difference of Types, aka what they don't share.

				shared_keys = curr_scope.declarations.keys.select do |key|
					right.has? key
				end

				current_unique_keys = curr_scope.declarations.keys - shared_keys
				operand_unique_keys = right.declarations.keys - shared_keys
				keys_to_keep        = current_unique_keys + operand_unique_keys

				curr_scope.declarations.delete_if do |key, _|
					!keys_to_keep.include? key
				end

				curr_scope.static_declarations = curr_scope.static_declarations ^ right.static_declarations

				operand_unique_keys.each do |key|
					curr_scope[key] = dup_composed_value(right[key])
				end
			else
				raise Tape::Invalid_Composition_Operator.new(expr)
			end
		end

		# Struct-flavored sibling of #interp_composition: `Both | Abc | Def <extra: String>` composes *structs*, not Types. Members are positional, so the merge tracks `[name, type_name, type_object, value]` tuples by hand instead of Scope's key-based storage.
		def interp_struct_composition expr
			members = [] # accumulator: [[name, type_name, type_object, value], ...]

			member_index = ->(name) { name && members.index { |m| m[0] == name } }

			expr.expressions.each do |composition_expr|
				operand = interpret composition_expr.identifier
				raise Tape::Invalid_Composition_With_A_Non_Struct_type.new(expr) unless operand.is_a? Tape::Struct

				operand_members = operand.names.each_index.map { |i| [operand.names[i], operand.type_names[i], operand.type_objects[i], operand.values[i]] }

				case composition_expr.operator.value
				when '|'
					# Union -- leftmost source wins a name collision, same as #interp_composition's own `unless curr_scope.has?(key)`.
					operand_members.each do |member|
						next if member_index.call(member[0])
						members << member
					end
				when '~'
					# Removal -- drop any accumulated member whose name the operand also declares.
					operand_names = operand_members.filter_map { |m| m[0] }
					members.reject! { |m| m[0] && operand_names.include?(m[0]) }
				when '&'
					# Intersection -- keep only accumulated members the operand also names. An unnamed member has nothing to share by name, so it doesn't survive an intersection.
					operand_names = operand_members.filter_map { |m| m[0] }
					members.select! { |m| m[0] && operand_names.include?(m[0]) }
				when '^'
					# Symmetric difference -- drop whatever's shared, keep (and pull in) whatever's unique to either side.
					operand_names = operand_members.filter_map { |m| m[0] }
					shared_names  = members.filter_map { |m| m[0] }.select { |name| operand_names.include? name }
					members.reject! { |m| shared_names.include? m[0] }
					operand_members.each do |member|
						next unless member[0]
						next if shared_names.include? member[0]
						members << member
					end
				else
					raise Tape::Invalid_Composition_Operator.new(composition_expr)
				end
			end

			if expr.struct_body
				# This declaration's own extra members (`<extra: String>`) always win over a composed-in name, same as a type's own `{}` body over composition.
				own = interp_struct expr.struct_body, allow_spread: false
				own.names.each_index do |i|
					member = [own.names[i], own.type_names[i], own.type_objects[i], own.values[i]]
					if (idx = member_index.call(member[0]))
						members[idx] = member
					else
						members << member
					end
				end
			end

			names, type_names, types, values = members.empty? ? [[], [], [], []] : members.transpose
			struct                           = build_struct names, type_names, types, values
			register_bare_named_struct expr.name, struct, expr
		end

		# @param for_loop_expr [Tape::For_Loop_Expr]
		def interp_for_loop for_loop_expr
			stride = interpret(for_loop_expr.stride) if for_loop_expr.stride

			Drive.assert stride.nil? || stride.is_a?(::Integer), "Stride must be an integer" if stride

			loop_type = for_loop_expr.type&.value || 'each' # one of Tape::FOR_VERBS
			result    = nil

			collection = interpret for_loop_expr.collection
			values     = case collection
			when Tape::Dictionary
				collection.hash
			when Tape::Array
				collection.values
			when Tape::Set
				collection.set.to_a

			when Tape::Range
				collection.range
			when Tape::String
				collection.value.chars

			when Tape::Struct
				# `@.members` (an `Tape::Array` of `Tape::Member`, the `@members` ivar) is only populated when the opt-in `tapes/struct.tape` layer is loaded (see #build_struct) -- a bare Struct with no matching declared `Struct` type has nothing to iterate.
				collection.members&.values || []

			else
				collection
			end

			# New for-loop verbs, to be handled with stride and without
			#
			#   for <collection> [verb: map/select/reject] [by <stride>]
			#   end
			#
			iterate_body = -> (element, index) do
				body_result = nil
				begin
					scope = Scope.new('for_loop')
					push_scope scope
					scope.declare 'it', element
					scope.declare 'at', index
					if collection.is_a? Tape::Dictionary
						scope.declare 'value', element
						scope.declare 'key', index
					end
					catch :skip do
						for_loop_expr.body.each do |e|
							body_result = interpret e
							throw(:stop, body_result) if body_result.is_a? Tape::Return
						end
					end
				ensure
					pop_scope
				end
				body_result
			end

			# Initialize collection variables outside catch block so they persist after stop
			collected = []
			count_val = 0
			elements  = if stride && !collection.is_a?(Tape::Dictionary)
				# `each_slice` yields raw Ruby Arrays -- wrap each chunk as a real Tape::Array so `it` behaves like any other Drive value (`==`, `.push`, etc.), not just dot-index access (`it.0`), which already worked because #interp_dot_infix calls #maybe_instance on its receiver regardless.
				values.each_slice(stride).map { |chunk| Tape::Array.new(chunk) }.each_with_index
			elsif values.respond_to? :each_with_index
				values.each_with_index
			else
				# Here we return collection itself, in case it is iterable. We'll catch that case below.
				collection
			end

			# todo; give the raise below a real Error type
			# we've returned the collection above and are going to treat it differently
			if elements.equal? collection
				# todo; assert that this function takes an Int
				raise "Cannot iterate something that doesn't respond to next(Int->Any;)\n#{for_loop_expr.inspect}" unless collection.is_a?(Tape::Instance) && collection.has?('next')


				next_function = collection.get('next') # The actual signature of this functin is next(Int->Any;)
				begin
					scope = Scope.new('for_loop')
					push_scope scope

					# todo; construct a Call_Expr receiver/arguments from the original Func_Expr
					# call = Tape::Call_Expr.new
					# call.receiver = interpret next_function
					# call.arguments = [iteration]
					# result_of_next = interpret next_function # I need the Func_Expr
					for_loop_body_result = catch :stop do
						iteration            = 0
						while true
							call   = Tape::Call_Expr.new
							result = interp_func_body next_function, call, arg_values: [iteration]
							# todo; see how arg_values are wrapped differently from [iteration]

							break if result.is_a?(Tape::Instance) && result.name == 'Done'

							scope.declare 'it', result
							scope.declare 'at', iteration
							iteration += 1

							catch :skip do
								for_loop_expr.body.each do |e|
									for_loop_body_result = interpret e
									throw(:stop, for_loop_body_result) if for_loop_body_result.is_a? Tape::Return
								end
							end
						end
					end
				ensure
					pop_scope
				end
				for_loop_body_result
			else
				stop_value = catch :stop do
					elements.each do |element, index|
						if collection.is_a? Tape::Dictionary
							new_it  = element[1]
							new_at  = element[0]
							element = new_it
							index   = new_at
						end

						case loop_type
						when 'each'
							result = iterate_body.call element, index
						when 'map'
							collected << iterate_body.call(element, index)
						when 'select'
							collected << element if truthy? iterate_body.call(element, index)
						when 'reject'
							collected << element unless truthy? iterate_body.call(element, index)
						when 'count'
							count_val += 1 if truthy? iterate_body.call(element, index)
						end
					end
					nil
				end

				# Assign results after catch block so partial results are preserved on stop
				case loop_type
				when 'map', 'select', 'reject'
					result = Tape::Array.new(collected)
					link_instance_to_type result, 'Array'
				when 'count'
					result = count_val
				end

				result     = stop_value if stop_value.is_a? Tape::Return
			end

			result
		end

		def interp_conditional expr
			# All conditional forms (if/unless/while/until) use #truthy? uniformly now -- `if`/`while` used to require the condition be the literal value `true`, so `if [1,2,3]` never took its true branch.
			case expr.type.value
			when 'while', 'until', 'elwhile', 'elswhile'
				result    = nil
				condition = interpret expr.condition

				index           = 0
				on_skip_handler = Proc.new do
					index += 1
					stack.last.declare 'at', index

					expr.when_true.each do |stmt|
						result = interpret(stmt)
					end
				end

				iteration_proc = Proc.new do
					catch :skip do
						on_skip_handler.call
					end
					condition = interpret(expr.condition)
				end

				catch :stop do
					if expr.type.value == 'until'
						until truthy? condition
							iteration_proc.call
						end
					else
						while truthy? condition
							iteration_proc.call
						end
					end
				end

				if expr.when_false.is_a? Tape::Conditional_Expr
					result = interp_conditional expr.when_false
				elsif expr.when_false.is_a? ::Array
					expr.when_false.each do |expr|
						result = interpret expr
					end
				end

				return result
			else
				# `unless` is just `if` with when_true/when_false swapped -- both branches used to be
				# separately maintained copies of this same body-selection + running logic.
				condition   = interpret expr.condition
				truthy_body = expr.type.value == 'unless' ? expr.when_false : expr.when_true
				falsy_body  = expr.type.value == 'unless' ? expr.when_true : expr.when_false
				body        = truthy?(condition) ? truthy_body : falsy_body

				if body.is_a? Tape::Conditional_Expr
					interp_conditional body
				else
					body.each.inject(nil) do |result, expr|
						interpret expr
					end
				end
			end
		end

		# The value-producing Context functions (`@puts`, `@assert`, `@connect`, ...). Args are
		# already-evaluated values; `at` anchors errors; `receiver`
		# is the Context instance the func was called on (for `to_s`, which needs its subject scope).
		def interp_intrinsic name, args, at = nil, receiver = nil
			case name
			when 'to_s'
				subject = receiver.respond_to?(:subject) ? receiver.subject : receiver
				label   = subject && (subject.name.is_a?(Tape::Lexeme) ? subject.name.value : subject.name)
				label   ||= subject && subject.class.name.split('::').last
				"@#{label}"
			when 'puts'
				args.each { |v| puts stringify_for_display(v, show_quotes: true) } # todo: settable output stream
				args.length == 1 ? args.first : (args.empty? ? nil : wrap_tape_array(args)) # passthrough
			when 'pputs' # pretty puts
				args.each { |v| puts stringify_for_display(v, show_quotes: true) } # todo: settable output stream
				args.length == 1 ? args.first : (args.empty? ? nil : wrap_tape_array(args)) # passthrough
			when 'sleep'
				args.first ? sleep(args.first) : nil
			when 'assert'
				raise Tape::Assert_Triggered.new(at, args[1]) unless truthy? args.first
				args.first
			when 'refute'
				raise Tape::Refute_Triggered.new(at, args[1]) if truthy? args.first
				args.first
			when 'connect'
				require 'sequel'
				database = args.first
				link_instance_to_type database, 'Database'
				unless database.get 'connection'
					url = database.get('url') or raise Tape::Url_Not_Set_For_Database_Instance
					database.declare 'connection', Sequel.sqlite(adapter: 'sqlite', database: url)
				end
				database
			when 'start_server'
				server = args.first
				raise Tape::Invalid_Server_Argument.new(at) unless server.is_a? Tape::Instance
				server.port   = Integer(server.get(:port) || Tape::Server::DEFAULT_PORT)
				server.routes = collect_routes_from_instance server
				servers << server
				start_server server # the Ruby method -- server thread, webrick, etc
				server
			when 'stop_server'
				server = args.first
				raise Tape::Invalid_Server_Argument.new(at) unless server.is_a? Tape::Instance
				stop_server server
				server
			end
		end

		# `@ruby` inside a function body -- dispatches to the enclosing scope's `proxy_<funcname>`.
		def interp_ruby_proxy expr
			func_scope = stack.last
			raise Tape::Invalid_Ruby_Proxy_Usage.new(func_scope) unless func_scope.is_a? Tape::Func

			func_name        = func_scope.name
			proxy_method     = "proxy_#{func_name.value}"
			instance_or_type = func_scope.enclosing_scope

			# For a static proxy on a Type (`Record.find`), build a throwaway instance of the Ruby class so the proxy can read the Type's declarations.
			target = if instance_or_type.instance_of?(Tape::Type) && instance_or_type.name
				ruby_class = find_ruby_class_for_type instance_or_type
				if ruby_class
					temp_instance              = ruby_class.new instance_or_type.name
					temp_instance.declarations = instance_or_type.declarations
					temp_instance
				else
					instance_or_type
				end
			else
				instance_or_type
			end

			if proxy_method && !target.respond_to?(proxy_method)
				raise Tape::Missing_Ruby_Proxy_Declaration.new target, expr
			end

			result = target.send proxy_method, *func_scope.arguments

			# A Ruby-built instance (`Tape::String.new` in a proxy) seeds `@types` from `self.class.name` -- re-wire its type identity so `===`/return-type checks pass.
			adopt_type result, result.class.name.split('::').last if result.is_a?(Tape::Instance) && result.enclosing_scope.nil?

			result
		end

		# Calling a synthesized Context function stand-in (see #synthesized_context_func). `func` carries
		# the member name and `enclosing_scope` (the Context). Stack functions (`@push_scope`, `@load`,
		# ...) run right here in the caller's frame -- nothing was pushed -- so `stack.last` is the real
		# caller scope, and they read raw arg exprs (`@push_scope` needs a bare identifier). The rest go
		# through #interp_intrinsic with their args evaluated.
		def interp_context_function func, call_expr
			word      = func.context_function_name
			arg_exprs = call_expr.arguments || []

			if Tape::Context::STACK_FUNCTIONS.include? word
				interp_context_stack_function word, arg_exprs, call_expr
			else
				interp_intrinsic word, arg_exprs.map { |e| interpret e }, call_expr, func.enclosing_scope
			end
		end

		# The Context functions that read/mutate `stack.last` or the interpreter's scope stack.
		# Run in the caller's frame (no pushed function frame).
		def interp_context_stack_function word, arg_exprs, at
			case word
			when 'declare'
				data = arg_exprs.map { |e| interpret e }
				if data.first.is_a? Tape::Struct
					data.first.members.values.each { |m| stack.last.declare(m.name, m.value, m.type) if m.name }
					return data.first
				end
				case data.count
				when 1 then stack.last.declare data[0], nil
				when 2 then stack.last.declare data[0], data[1]
				when 3 then stack.last.declare data[0], data[1], data[2]
				else raise Tape::Invalid_Context_Function_Usage.new(at)
				end

			when 'load'
				filepath = interpret arg_exprs.first
				load_file_into_scope filepath, stack.last

			when 'push_scope'
				# Must be a bare identifier naming something already bound -- a literal/constructor call builds a fresh object each time, so #pop_scope's identity assert could never match it later.
				target_expr = arg_exprs.first
				raise Tape::Invalid_Scope_Function_Argument.new(target_expr) unless target_expr.is_a?(Tape::Identifier_Expr)
				target = maybe_instance(interpret target_expr)
				raise Tape::Invalid_Scope_Function_Argument.new(target_expr) unless target.is_a?(Tape::Type)
				push_scope target

			when 'pop_scope'
				target_expr = arg_exprs.first
				raise Tape::Invalid_Context_Function_Usage.new(at) unless target_expr
				raise Tape::Invalid_Scope_Function_Argument.new(target_expr) unless target_expr.is_a?(Tape::Identifier_Expr)
				scope_to_pop = maybe_instance interpret target_expr
				raise Tape::Invalid_Scope_Function_Argument.new(target_expr) unless scope_to_pop.is_a?(Tape::Type)
				# By identity -- an instance and a reference to its type don't interchange.
				Drive.assert pop_scope == scope_to_pop
				scope_to_pop

			when 'splat', 'splatr'
				target = maybe_instance interpret(arg_exprs.first)
				raise Tape::Invalid_Context_Function_Usage.new(at) unless target
				raise Tape::Invalid_Scope_Function_Argument.new(arg_exprs.first) unless target.is_a?(Tape::Scope)
				word == 'splatr' ? stack.last.add_readable_scope(target) : stack.last.add_writable_scope(target)
				target

			when 'unsplat'
				raise Tape::Invalid_Context_Function_Usage.new(at) if arg_exprs.empty?
				target = maybe_instance interpret arg_exprs.first
				stack.last.remove_readable_scope target
				stack.last.remove_writable_scope target
				target
			end
		end

		def interp_subscript expr
			if expr.expression.expressions.count > 1
				raise Tape::Too_Many_Subscript_Expressions.new(expr.expression)
			end

			receiver  = maybe_instance interpret expr.receiver
			subscript = expr.expression.expressions.first

			case receiver
			when Tape::Dictionary, Tape::Array
				key = interpret subscript
				# `arr[1...3]` -- a Tape::Range slice. Unwrap to the backing ::Range; the result is a raw
				# Ruby sub-array (or nil for an out-of-bounds start), so re-link it.
				if key.is_a?(Tape::Range)
					sliced = receiver.proxy_get key.range
					return sliced.is_a?(::Array) ? wrap_tape_array(sliced) : sliced
				end
				receiver.proxy_get key
			when Tape::Nil
				# todo: What should happen when subscripting nil? A warning of some kind maybe?
				nil
			when Tape::String
				index = interpret subscript
				index = index.range if index.is_a?(Tape::Range) # `"abc"[0...2]`
				receiver.value[index]
			else
				raise Tape::Invalid_Subscript_Receiver.new expr.receiver
			end
		end

		# `Key_Type [ PRIMARY, ]` declares `Key_Type` in the current scope, same as a Type/Struct declaration does -- unlike a nested enum member (`build_enum`, called directly, skips this), which is only ever reachable through its parent (`Outer.Nested`), not the enclosing scope.
		def interp_enum expr
			instance = build_enum expr
			stack.last.declare expr.name.value, instance
			instance
		end

		# Builds (but doesn't declare) a real Tape::Enum for an Enum_Expr -- shared by #interp_enum and nested enum members (#build_enum_member).
		def build_enum expr
			# Named at construction, not via `.name =` after -- a later attr write never touches @declarations.
			instance = Tape::Enum.new expr.name.value
			link_instance_to_type instance, 'Enum'

			# Skips normal Type-construction, so Enum's own Drive-level body (keys/values/types/count, @operator ==) is run by hand.
			type = instance.enclosing_scope
			if type
				instance.expressions = type.expressions
				run_type_body_on_instance type, instance
			end

			keys, values, types = [], [], []
			expr.expressions.each do |member_expr|
				name, value, member_type = build_enum_member member_expr
				keys << name
				values << value
				types << member_type
				instance.declarations[name] = value
			end

			# Reflective data is `@`-only now (`@.keys` / `@.values` / `@.types` / `@.type` / `@.count`).
			instance.enum_type   = expr.type ? find_in_stack(expr.type.value) : nil
			instance.enum_keys   = keys
			instance.enum_values = values
			instance.enum_types  = types

			instance
		end

		# Links a raw Tape::Array to the real Array type so its own Drive-level methods (to_s(;), etc.) are reachable. Used by #build_enum and #build_instance_of_type.
		def wrap_tape_array list
			adopt_type Tape::Array.new(list), 'Array'
		end

		# What a variadic param binds -- a Tape::Array linked to the `Arguments` type (see tapes/array.tape).
		def wrap_arguments_array list
			adopt_type Tape::Array.new(list), 'Arguments'
		end

		# Returns [name, value, type] for one enum member, per #parse_enum_expr's five member forms (see CLAUDE.md). Bare/typed-only members get a Symbol matching their own name; `:=`/`: Type =` members use their real value; nested enums recurse into #build_enum.
		def build_enum_member member_expr
			case member_expr
			when Tape::Enum_Expr
				[member_expr.name.value, build_enum(member_expr), nil]
			when Tape::Nil_Init_Expr
				name = member_expr.left.value
				[name, name.to_sym, nil]
			when Tape::Identifier_Expr
				name        = member_expr.value
				member_type = member_expr.type ? find_in_stack(member_expr.type.value) : nil
				[name, name.to_sym, member_type]
			when Tape::Infix_Expr
				name        = member_expr.left.value
				member_type = member_expr.left.type ? find_in_stack(member_expr.left.type.value) : nil
				[name, interpret(member_expr.right), member_type]
			end
		end

		# Resolves a `: Type` annotation's value. A bare struct annotation (`id: <a: Number>`) interprets straight to a Struct. An Identifier_Expr carrying a trailing `\` tag (`id: Array\String`, `id: Thing\One\Two`) resolves through a synthetic Type_Expr reference so the tag chain is bound; a plain one just interprets. `type_expr` is an Identifier_Expr, not a Type_Expr (see #parse_identifier_expr), hence the synthetic reference -- same trick #interp_func_body etc. use to reuse existing dispatch.
		def interp_type_annotation type_expr
			return interp_struct type_expr if type_expr.is_a? Tape::Struct_Expr
			return interpret type_expr unless type_expr.tag

			reference      = Tape::Type_Expr.new
			reference.name = type_expr.value
			reference.tag  = type_expr.tag
			interp_type reference
		end

		def interp_struct expr, allow_spread: true
			# A `Name <...>` whose own members reference `Name` (`parent: Node`, `enclosing_scope: Scope`)
			# needs `Name` on the scope while those members are being interpreted -- declare an empty
			# stand-in first, the same way a bare Type is declared before its body runs.
			# #register_bare_named_struct swaps the finished struct in at the end.
			self_ref_stub = predeclare_bare_named_struct_stub expr

			types         = [] # per-member type object (or the raw value itself for unnamed members)
			values        = [] # per-member real value, nil when a named member has none
			names         = []
			single_member = allow_spread && expr.types.length == 1 # only a lone unnamed member spreads -- see below

			expr.types.each_with_index do |member, i|
				if expr.names[i]
					# note; Named member (e.g. `some_string: String`), the member's own identifier (`some_string`) is just a label, not something to look up; resolve its declared type instead. Named members are never spread: the name is always its namespace (`.tag.columns`), even when the value is itself a Struct.
					if member.is_a?(Tape::Func_Signature_Expr)
						# `to_s: (-> String;)` -- the member's type is the signature itself, no value.
						types << build_func_signature(member)
						values << nil
					elsif member.type
						# `member.type` is already a full Identifier_Expr (#parse_identifier_expr's `: Type` recurses) or a bare Struct_Expr (`id: <a: Number>`), not a bare Lexeme -- directly interpretable, no rewrapping needed. A trailing `\<...>`/`\Name` on that annotation (`id: Array\String`) only ever populates `.tag` there (see #parse_identifier_expr), not a real `Type_Expr` -- a plain #interpret would silently resolve the untagged base type, so route through #interp_type_annotation instead.
						types << interp_type_annotation(member.type)
						if member.member_default
							default_value = interpret(member.member_default)
							values << wrap_string_literal_value(member.member_default, default_value)
						else
							values << nil
						end
					else
						# Bare `name := value` member, no `: Type` annotation -- infer the member's declared type from the default's own runtime type, same as plain `:=` does everywhere else.
						default_value = interpret(member.member_default)
						types << find_in_stack(inferred_type_name(default_value)) # numerics collapse to `Number`
						values << wrap_string_literal_value(member.member_default, default_value)
					end
					names << expr.names[i]
				else
					value = interpret member

					if single_member && value.is_a?(Tape::Struct)
						types.concat value.type_objects
						values.concat value.values
						names.concat value.names
					else
						types << value
						# A bare Type used as the member itself (`<Number>`, schema-only, no real data yet) isn't a value -- push nil, same as a named member's own `: Type` annotation with no default does, rather than the Type object itself (which used to leak into display code expecting a real value or nil).
						values << (value.is_a?(Tape::Type) && !value.is_a?(Tape::Instance) ? nil : wrap_string_literal_value(member, value))
						names << nil
					end
				end
			end

			# Each member's "type" here is just its value's own inferred type name (numerics stay `Number`)
			type_names = types.map { |value| inferred_type_name value }
			struct     = build_struct names, type_names, types, values

			# A leading TYPE_IDENTIFIER before `<...>` (`Task <id: Number, done: Bool>`) makes `expr.name` a raw Lexeme -- a Bare Named Struct (see CLAUDE.md), registered globally here. `\<...>`'s inline-literal form sets `.tag.name` to a plain String instead, so it never re-triggers this.
			if expr.name.is_a? Tape::Lexeme
				repoint_struct_self_reference(struct, self_ref_stub) if self_ref_stub
				return register_bare_named_struct(expr.name.value, struct, expr, self_ref_stub)
			end

			struct
		end

		# Ensures `expr.name` resolves while this struct's own members are interpreted, so a member
		# annotated with the struct's own name (`parent: Node`) doesn't raise Undeclared_Identifier --
		# the same reason a bare Type is declared before its body runs. Returns the stand-in (a fresh
		# empty struct declared here, or a prior `Name <>` empty forward declaration), or nil when this
		# isn't a fresh / forward-declared bare named struct. #register_bare_named_struct swaps the
		# finished struct in.
		def predeclare_bare_named_struct_stub expr
			return nil unless expr.name.is_a? Tape::Lexeme
			name     = expr.name.value
			existing = find_in_stack name

			# `Name <>` written earlier as an empty forward declaration -- members resolve against it,
			# and it gets filled in below (a non-empty prior shape is a real conflict, left to raise).
			return existing if existing.is_a?(Tape::Struct) && existing.names.empty?
			return nil unless existing.nil? && tagged_variants_for(name).empty?

			stub       = Tape::Struct.new
			stub.name  = name # `@`-only (`@.name`)
			stub.types = ::Set[name]
			link_instance_to_type stub, 'Struct'
			stack.last.declare name, stub
			stub
		end

		# The finished struct is a different object than the stub self-referential members captured
		# while resolving their `: Name` annotations -- repoint those slots at it. Nothing else holds
		# the stub.
		def repoint_struct_self_reference struct, stub
			objects = struct.type_objects
			objects.map! { |t| t.equal?(stub) ? struct : t } if objects
		end

		# Registers (or idempotently confirms) a Bare Named Struct under `name` -- redeclaring the identical shape is a no-op; anything else already bound there raises instead of clobbering it.
		def register_bare_named_struct name, struct, expr, stub = nil
			existing = find_in_stack name

			# `stub` is the empty stand-in from #predeclare_bare_named_struct_stub (a fresh one, or an
			# earlier `Name <>` forward declaration) -- fill it in with the finished struct. Not a real
			# prior shape, so the shape-mismatch rule below doesn't apply.
			if stub && existing.equal?(stub)
				struct.name = name # `@`-only (`@.name`)
				prefix_type struct, name
				stack.last.declare name, struct
				return struct
			end

			if existing.is_a?(Tape::Struct) && existing.name == name && existing.structure_declaration_equal?(struct)
				return existing
			end

			# A tagged Type declaration never registers under the plain identifier namespace (only in `tagged_type_variants`), so `find_in_stack` alone can't see a conflicting one -- check both.
			if existing.nil? && tagged_variants_for(name).empty?
				struct.name = name # `@`-only (`@.name`); Ruby proxy code (e.g. Database) reads Scope#name directly
				prefix_type struct, name
				stack.last.declare name, struct if struct.names.all?
				return struct
			end

			raise Tape::Undeclared_Tagged_Type.new(expr)
		end

		# A value built directly from a string literal gets wrapped into a real Tape::String carrying the literal's own `quotation_style`, instead of staying the bare Ruby string #interp_string normally returns. Struct/Member's to_s(;) (tapes/member.tape) and Array/Dictionary/Tuple's to_s(;) (tapes/array.tape, tapes/dictionary.tape, tapes/global.tape) read `.quotation_style` straight off the value to decide how to quote it for display.
		def wrap_string_literal_value source_expr, value
			return value unless source_expr.is_a?(Tape::String_Expr) && value.is_a?(::String)
			finish_intrinsic_instance Tape::String.new(value, source_expr.quotation_style), 'String'
		end

		# The low-level Tape::Struct object is always built first and exactly the same way regardless of `struct_type` -- it's what #type_objects/etc. read from, and every existing member-matching call site depends on it being real.
		def build_struct names, type_names, types, values
			struct_type = find_in_stack 'Struct'
			struct      = Tape::Struct.new names, type_names, types, values

			unless struct_type.is_a?(Tape::Type)
				link_instance_to_type struct, 'Struct'
				return struct
			end

			# `.name` stays nil here -- an anonymous struct has no name; #register_bare_named_struct
			# names a bare named one, #interp_struct_call names a constructed schema instance.
			struct.types           = struct_type.types
			struct.enclosing_scope = struct_type
			run_type_body_on_instance struct_type, struct

			# `@.members` -- Tape::Member instances, one per member, when the `Member`/`Struct` tape layer
			# is loaded (`tapes/struct.tape`). The plain quartet (`@names`/`@type_names`/`@type_objects`/
			# `@values`) is already on the struct from Struct#initialize.
			member_type = find_in_stack 'Member'
			if member_type.is_a?(Tape::Type)
				members = names.each_index.map do |i|
					member_display_type = names[i] ? types[i] : find_in_stack(type_names[i])
					member              = Tape::Member.new names[i], member_display_type, values[i]
					link_instance_to_type member, 'Member'
					member
				end

				members_array = Tape::Array.new members
				link_instance_to_type members_array, 'Array'
				struct.members = members_array
			end

			struct
		end

		# @param expr [Tape::Operator_Overload_Expr]
		def interp_operator_overload expr
			# expr attrs:  func_expr(Func_Expr)  fixity(Lexeme)  precedence(Int)  value(String)
			# This is setting up operators to be treated as regular functions, whose identifier is its operator symbols without spaces.

			stack.last.declare expr.value, interpret(expr.func_expr)
		end

		# note: This is the entry point for all expressions. This is called in a loop until all expressions are evaluated, or the program crashes.
		def interpret expr
			case expr
			when Tape::Number_Expr, Tape::Symbol_Expr
				expr.value

			when Tape::Identifier_Expr
				interp_identifier expr

			when Tape::String_Expr
				interp_string expr

			when Tape::Type_Expr
				interp_type expr

			when Tape::Route_Expr
				interp_route expr

			when Tape::Func_Expr
				interp_func expr

			when Tape::Func_Signature_Expr
				interp_func_signature expr

			when Tape::Composition_Expr
				# Reaching here means a bare `| Compo` showed up nested somewhere other than a type body's own top level -- #finish_type_declaration/#run_type_body_on_instance dispatch that case explicitly, bypassing this.
				raise Tape::Composition_Outside_Type_Declaration.new(expr)

			when Tape::Prefix_Expr
				interp_prefix expr

			when Tape::Nil_Init_Expr
				# This is a special infix expression `<ident>,` that desugars to `ident = ident or nil`. left is assigned nil if it doesn't exist, or is returned if it does
				interp_nil_init expr

			when Tape::Infix_Expr
				interp_infix expr

			when Tape::Postfix_Expr
				interp_postfix expr

			when Tape::Percent_Literal_Expr
				interp_percent_literal expr

			when Tape::Circumfix_Expr
				interp_circumfix expr

			when Tape::Call_Expr
				interp_call expr

			when Tape::For_Loop_Expr
				interp_for_loop expr

			when Tape::Conditional_Expr
				interp_conditional expr

			when Tape::Array_Index_Expr
				maybe_instance expr.indices_in_order

			when Tape::Subscript_Expr
				interp_subscript expr

			when Tape::Statement_Expr
				interp_statement expr

			when Tape::Fence_Expr
				interp_fence expr

			when Tape::Html_Fence_Expr
				interp_html_fence expr

			when Tape::Comment_Expr
				expr.value

			when Tape::Operator_Overload_Expr
				interp_operator_overload expr

			when Tape::Operator_Expr
				case expr.value
				when 'skip'
					throw :skip
				when 'stop'
					throw :stop
				end

			when Tape::Struct_Expr
				interp_struct expr

			when Tape::Enum_Expr
				interp_enum expr

			when nil
				maybe_instance nil

			else
				raise Tape::Interpret_Expr_Not_Implemented.new(expr)
			end
		end
	end
end
