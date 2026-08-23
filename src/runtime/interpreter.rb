require 'webrick'
require 'cgi'
require 'json'

module Lost
	class Interpreter
		# Source lines by filepath, keyed the same way #register_source always has -- kept class-level (not per-instance) so Error_Formatter can read a snippet without holding a live Interpreter, which used to be the only reason errors.rb needed a `runtime` reference at all.
		@cached_source_by_filename = {} # {filepath: [String]}

		# Parsed ASTs by resolved filepath, kept class-level (not per-instance) for the same reason: `lost/preload.tape` (and everything it transitively @loads) is immutable source, identical for every Interpreter in the process, so re-lexing/re-parsing it fresh on every `Lost.interp` call was pure waste -- it used to be instance-level, meaning a brand-new Interpreter (which every `Lost.interp` call constructs) never saw a warm cache. Doesn't cache the *interpretation* of that AST (each Interpreter still builds its own fresh Standard_Library scope from it), only the lex+parse step, so per-instance isolation (mutating a builtin in one test can't leak into another) is unaffected.
		@cached_expressions_by_filepath = {} # {filepath: [Lost::Expression]}

		# Resolved filepaths whose AST has already passed type-checking at least once, kept class-level alongside the cache above. Type-checking is a pure function of the AST (no interpreter state involved) -- a cached, never-changing file that already passed once will always pass, so re-walking it on every subsequent load is pure waste, same as re-parsing was.
		@type_checked_filepaths = {} # {filepath: true}

		class << self
			attr_accessor :cached_source_by_filename, :cached_expressions_by_filepath, :type_checked_filepaths

			# Lets Ruby proxy methods (no interpreter reference otherwise) reach interpreter state, e.g. #find_table_type_for_schema. Not thread-safe across multiple interpreters; fine for one-per-process.
			attr_accessor :current
		end

		attr_accessor :input, :lexer, :parser, :load_standard_library, :stack, :route_functions_by_route_name, :servers, :dom_onclick_function_handlers, :dom_input_elements, :last_output, :current_source_file, :stdlib_scope, :declarations, :global

		def initialize
			@dom_input_elements            = {} # {element_hash: Lost::Instance} for inputs/textareas
			@dom_onclick_function_handlers = {} # {handler_hash: Lost::Func}
			@route_functions_by_route_name = {} # {route: Lost::Route}

			@load_standard_library = true
			@input                 = [] # [Lost::Expression]
			@stack                 = [] # [Lost::Scope]
			@servers               = [] # [Lost::Server]

			@lexer               = Lexer.new
			@parser              = Parser.new
			@declarations        = {} # {::String => Lost::Declaration}, see Declarator
			@forced_declarations = Set.new # identity-tracked Lost::Expression, see #resolve_forward_declaration

			Interpreter.current = self
		end

		def run source_code
			top_level_source_file = current_source_file

			if @stack.empty?
				# todo; Global should be created by interping lost/global.tape, which is what I want to rename lost/preload.tape to
				global  = Global.new
				@global = global # kept separately from @stack -- #interp_member_access temporarily swaps @stack out for dot-access resolution, so `stack.first` isn't reliably Global the way this needs
				@stack << global
				if load_standard_library
					# Stdlib lives in its own Scope, reachable via Global's readable scope -- not Global's own declarations. Reassigning a builtin can't mutate it (readable_scopes never redirects writes), just shadows locally. Composing and deliberate @push_scope reopening still work. `global` is pushed before this load so `~/` still resolves to Global while the stdlib itself loads.
					# Also held here as a real instance var, not just the WeakMap entry above -- readable/writable scope membership deliberately never keeps anything alive on its own (see CLAUDE.md), which is correct for things a caller adds and is expected to hold their own reference to elsewhere, but @stdlib_scope has no other holder anywhere. Without this, it's one GC pass away from being collected mid-program, taking the entire standard library (String, Array, everything) down with it.
					@stdlib_scope = Lost::Scope.new('Standard_Library')
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
				loop_servers
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

			# `Ident := @load 'file'` / `IDENT := @load 'file'` -- a named load builds a scope of its own, same declarative category as `This := That {}` above. Only a Capitalized/UPPERCASE left-hand name opts in, matching Lost's own casing convention for a namespace-like binding -- a lowercase `mod := @load 'file'` stays a plain variable, not hoisted
			expr.right.is_a?(Directive_Expr) && expr.right.name.value == 'load' &&
				%i(Identifier IDENTIFIER).include?(Lost.type_of_identifier(expr.left.value))
		end

		# A bare `@load 'file'` (no assignment) merges directly into the current scope -- always hoistable, no casing concept applies since there's no left-hand name to check. Kept separate from #hoistable_declaration_expr?'s recursive `:=`/`=` unwrap so this can't accidentally leak permissiveness into the *named* load case, which is deliberately restricted to a Capitalized/UPPERCASE left-hand name.
		def bare_load_directive_expr? expr
			expr.is_a?(Directive_Expr) && expr.name.value == 'load'
		end

		# @param [::String] name
		# @return [::Boolean] whether a declaration was found and forced
		def resolve_forward_declaration name
			decl = @declarations[name]
			return false unless decl&.expr
			return false unless hoistable_declaration_expr?(decl.expr) || bare_load_directive_expr?(decl.expr)
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
					puts Lost::Ascii.dim "Shutting down..."
					keep_running = false
					puts "\n\s\s(V) (;,,;) (V)"
					Thread.main.exit
				end
				Signal.trap 'INT', trap_fn
				Signal.trap 'TERM', trap_fn

				while keep_running
					@servers.each do |server|
						puts "Lost Server `#{server.name}` started at http://localhost:#{server.port}"
						server.server_thread&.join
					end
				end
			ensure
				@servers.each { |s| stop_server s }
			end
		end

		# Preserves its @input, interprets given file, then restores its @input.
		# @param [::String] filepath of the code to load
		# @param [Lost::Scope] scope to load code into
		# @return The output of the interpreted file
		def load_file_into_scope filepath, into_scope
			filepath.insert(-1, '.tape') unless filepath.end_with? '.tape' # note; I feel like this isn't the smartestest way to achieve this.

			resolved_path = if filepath.start_with? 'lost/'
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
			Lost.assert pop_scope.equal? into_scope

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

		def add_onclick_handler handler
			key                                = handler.hash
			dom_onclick_function_handlers[key] = handler
			key
		end

		def add_input_element instance
			key                     = instance.hash
			dom_input_elements[key] = instance
			key
		end

		def scope_for_identifier expr
			unless expr.is_a? Lost::Identifier_Expr
				return stack.last
			end

			case expr.scope_operator&.value
			when '~/' # global
				stack.first
			when '../' # underlying type within context, aka accessing a static declaration
				stack.reverse_each.find do |scope|
					scope.instance_of? Lost::Type
				end
			when './' # instance within context, aka self, this, etc
				current_instance
			else
				# If no scope operator, search through all scopes to find the identifier
				found_scope = nil
				stack.reverse_each do |scope|
					if scope.has?(expr.value) || scope.respond_to?("proxy_#{expr.value}")
						found_scope = scope
						break
					elsif scope.is_a?(Lost::Instance) && scope.enclosing_scope&.has?(expr.value)
						# Method exists on the Type - return the instance as the scope so lookups happen in instance context
						found_scope = scope
						break
					end
				end
				found_scope
			end
		end

		def maybe_instance expr
			# todo, when String and so on, because everything needs to be some type of scope to live inside the runtime. Every object in Lost::Scope.declarations{} is either a primitive like String, Integer, Float, or they're an instanced version like Lost::Number.
			case expr
			when Integer, Float
				# Lost::Number_Expr is already handled in #interpret but this is short-circuiting that for cases like 1.something where we have to make sure the 1 is no longer a numeric literal, but instead a runtime object version of the number 1.
				number = Lost::Number.new expr, 1, Lost.type_of_number_expr(expr)

				finish_intrinsic_instance number, 'Number'
			when ::String
				finish_intrinsic_instance Lost::String.new(expr), 'String'
			when ::Array
				finish_intrinsic_instance Lost::Array.new(expr), 'Array'
			when ::Hash
				finish_intrinsic_instance Lost::Dictionary.new(expr), 'Dictionary'
			when nil
				nil_instance = Lost::Nil.shared
				link_instance_to_type nil_instance, 'Nil'
				nil_instance
			when true
				finish_intrinsic_instance Lost::Bool.truthy, 'Bool'
			when false
				finish_intrinsic_instance Lost::Bool.falsy, 'Bool'
			else
				expr
			end
		end

		def finish_intrinsic_instance instance, type_name
			instance.name = type_name
			link_instance_to_type instance, type_name
			instance.types = instance.enclosing_scope ? instance.enclosing_scope.types : Set[type_name]
			instance
		end

		def link_instance_to_type instance, type_name
			global_scope = stack.first
			if global_scope.has? type_name
				instance.enclosing_scope = global_scope[type_name]
			end
		end

		def track_static_declaration scope, ident_expr
			return unless ident_expr.is_a?(Lost::Identifier_Expr) && ident_expr.scope_operator&.value == '../'
			scope.static_declarations ||= Set.new
			scope.static_declarations.add ident_expr.value.to_s
		end

		# The Instance the currently executing method body belongs to, if any -- searched by role (nearest Lost::Instance in the stack), not position. #interp_func_body always pushes a fresh per-call Func frame on top of the instance for every call, so `stack.last` is never the instance itself while a method runs -- shared by `self`/`./` resolution (#interp_identifier, #scope_for_identifier) and privacy enforcement (#check_dot_access_permissions!) below, all three needing "the instance I'm currently running as".
		def current_instance
			stack.reverse_each.find { |scope| scope.is_a? Lost::Instance }
		end

		def check_dot_access_permissions! scope, ident, expr
			binding = Lost.binding_of_ident scope, ident
			privacy = Lost.privacy_of_ident ident

			case scope
			when Lost::Instance
				if privacy == :private && !current_instance.equal?(scope)
					raise Lost::Cannot_Call_Private_Instance_Member.new(expr)
				end
			when Lost::Type
				if binding == :instance
					# todo: This does not print the correct code location, here is a paste of the output:
					#       Cannot_Call_Instance_Member_On_Type
					#       :1:1
					raise Lost::Cannot_Call_Instance_Member_On_Type.new(expr)
				elsif privacy == :private
					raise Lost::Cannot_Call_Private_Static_Member_On_Type.new(expr)
				end
			end
		end

		def find_ruby_class_for_type type
			type.types.to_a.reverse.each do |type_name|
				lost_name = "Lost::#{type_name}"
				next unless Object.const_defined? lost_name
				k = Object.const_get lost_name
				return k if k.is_a?(Class) && k < Lost::Instance && k != Lost::Instance
			end
			nil
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
			when Lost::Number then 'Number'
			when Integer, Float then 'Number'
			when Lost::String then 'String'
			when Lost::Array then 'Array'
			when Lost::Dictionary then 'Dictionary'
			when Lost::Bool then 'Bool'
			when Lost::Instance then value.types.first
			when Lost::Type then value.name
			# todo: Why are these here? Excluding the else clause
			when true, false then 'Bool'
			when ::String then 'String'
			when ::Array then 'Array'
			when ::Hash then 'Dictionary'
			else nil
			end
		end

		def composed_types_for value
			case value
			when Lost::Type
				value.types
			else
				# Covers intrinsics (Number/String/Array/Dictionary/Bool) and anything else -- neither needs special handling, both resolve by name.
				composed_types_by_name type_name_to_string(value)
			end
		end

		def composed_types_by_name name
			return Set.new unless name
			global = stack.first
			global.has?(name) ? global[name].types : Set[name]
		end

		# Does `a` (composed types + struct members) carry at least everything `b` does? Shared by `=>=`/`=<=`/`===`/`=!=` -- see #interp_comparison_infix.
		def superset_of_types_and_tag? a_types, a_tag, b_types, b_tag
			types_superset   = b_types.all? { |type| a_types.include? type }
			members_superset = (b_tag || []).all? { |member| (a_tag || []).include? member }
			types_superset && members_superset
		end

		# If `name` is already an Lost::Func_Signature, return it as-is (an inline signature has no name to look up). Otherwise, if it's bound to one anywhere on the stack, return that. Otherwise nil — meaning `name` is an ordinary nominal type name (e.g. 'Number').
		def resolve_func_signature name
			return name if name.is_a? Lost::Func_Signature
			return nil unless name
			value = find_in_stack name
			value.is_a?(Lost::Func_Signature) ? value : nil
		end

		# @param expr [Lost::Func_Signature_Expr]
		def build_func_signature expr
			param_types = expr.params.map { |param| param.type&.value }
			Lost::Func_Signature.new param_types, expr.type&.value
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
				puts Lost::Ascii.dim "#{'DOM'.rjust(7, ' ')} #{req.path}"
				handle_request server, req, res
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
			Thread.kill server.server_thread if server.server_thread
		end

		def handle_request server, request, response
			path_string  = request.path
			query_string = request.query_string
			http_method  = request.request_method.downcase
			path_parts   = request.path.split('/').reject { _1.empty? }
			body_hash    = CGI.parse(request.body || "").transform_values(&:first)
			headers_hash = request.header.to_h

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
				object_id = path_parts.last.to_i
				handler   = dom_onclick_function_handlers[object_id]
				if handler
					begin
						if request.body && !request.body.empty?
							json_body = JSON.parse request.body rescue {}
							inputs = json_body['inputs'] || {}
							inputs.each do |element_id, value|
								input_instance = dom_input_elements[element_id.to_i]
								input_instance.declare 'value', value if input_instance
							end
						end

						route             = Lost::Route.new
						route.handler     = handler
						route.param_names = []

						req = build_lost_request path_string, http_method, body_hash, parse_query_string(query_string), {}, headers_hash
						res = build_lost_response response

						interp_route_body route, req, res

						component = handler.enclosing_scope
						if component.is_a?(Lost::Instance) && component.declarations['render']
							new_html = render_dom_to_html component
							html_id  = component.declarations['html_id']

							response.status              = 200
							response['Content-Type']     = 'text/html'
							response['X-Lost-Target-Id'] = html_id if html_id
							response.body                = new_html
							return
						end
					rescue => e
						warn "\n[Lost Onclick Error] #{e.class}: #{e.message}"
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

				req = build_lost_request path_string, http_method, body_hash, query_params, url_params, headers_hash

				begin
					res    = build_lost_response response
					result = interp_route_body route_function, req, res, url_params, server_instance: server

					response.status = res.declarations['status']
					response.body   = res.declarations['body']
					res.declarations['headers'].each { |k, v| response.header[k] = v }

					if response.body.to_s =~ /<html|<body|<head/i
						response.body.prepend "<!DOCTYPE html>"

						dom_js     = File.read 'src/runtime/dom.js'
						script_tag = "<script>#{dom_js}</script>"

						body_str = response.body.to_s
						if body_str.include?('<head>')
							response.body = body_str.sub('<head>', '<head>' + script_tag)
						elsif body_str.include?('<body>')
							response.body = body_str.sub('<body>', '<body>' + script_tag)
						else
							response.body = script_tag + body_str
						end
					end

					result

				rescue WEBrick::HTTPStatus::Status => e
					raise e

				rescue => e
					warn "\n[Lost Server Error] #{e.class}: #{e.message}"
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
			routes.values.find do |route|
				next unless route.http_method.value == http_method
				next unless route.parts.count == path_parts.count

				path_parts.zip(route.parts).all? do |req_part, route_part|
					(req_part == route_part) || (route_part.start_with?(':'))
				end
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

		def build_lost_request path_string, http_method, body_hash, query_params, url_params, headers_hash
			req          = Lost::Request.new
			body_dict    = Lost::Dictionary.new body_hash
			query_dict   = Lost::Dictionary.new query_params
			params_dict  = Lost::Dictionary.new url_params
			headers_dict = Lost::Dictionary.new headers_hash
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

		def build_lost_response webrick_response
			res                                  = Lost::Response.new
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

		def render_dom_to_html dom_instance
			render = dom_instance.declarations['render']

			inner_html = if render
				call_expr           = Lost::Call_Expr.new
				call_expr.receiver  = render
				call_expr.arguments = []

				render_result = interp_func_body render, call_expr

				"".tap do |html|
					if render_result.is_a? ::String
						html << render_result

					elsif render_result.is_a? Lost::Array
						render_result.values.each do |child|
							if child.is_a? ::String
								html << child
							elsif child.is_a?(Lost::Instance) && child.types.include?('Dom')
								html << render_dom_to_html(child)
							end
						end

					elsif render_result.is_a?(Lost::Instance) && render_result.types.include?('Dom')
						html << render_dom_to_html(render_result)

					end
				end
			end

			renderer = Lost::Dom_Renderer.new dom_instance, inner_html

			if renderer.onclick_expr
				add_onclick_handler renderer.onclick_expr
			end

			if renderer.is_input_element?
				add_input_element dom_instance
			end

			renderer.to_html_string
		end

		# Raises the right error for a `./`/`../` scope operator that resolved to no scope at all -- shared by #interp_identifier, #interp_infix_assignment, #interp_infix_declaration. Any other operator value (`~/`, or none) raises Invalid_Scope_Syntax.
		def raise_missing_scope_operator_target! expr, scope_operator_value
			case scope_operator_value
			when './'
				raise Lost::Cannot_Use_Instance_Scope_Operator_Outside_Instance.new(expr)
			when '../'
				raise Lost::Cannot_Use_Type_Scope_Operator_Outside_Type.new(expr)
			else
				raise Lost::Invalid_Scope_Syntax.new(expr)
			end
		end

		# A function found via #interp_identifier needs to be duplicated and rebound to the resolving scope before use, so composed types (e.g. `Thing | Record`) call functions against the right receiver instead of whatever scope they happened to be declared on. Non-Func values pass through unchanged.
		def rebind_func_to_scope value, scope
			return value unless value.is_a? Lost::Func
			func                 = value.dup
			func.enclosing_scope = scope
			func
		end

		def interp_identifier expr
			if expr.directive
				# todo: Why is this not handled by Parser#complete_expression?
				dir_expr      = Lost::Directive_Expr.new
				dir_expr.name = expr
				return interp_directive dir_expr
			end

			scope = case expr.value
			when 'nil'
				return nil
			when 'true'
				# todo; return Lost::Bool.truthy
				return true
			when 'false'
				# todo; return Lost::Bool.falsy
				return false
			when 'Self'
				found = stack.reverse_each.find { |scope| scope.instance_of? Lost::Type }
				return found if found
				raise Lost::Cannot_Use_Type_Scope_Operator_Outside_Type.new(expr)
			when 'self'
				return current_instance if current_instance
				raise Lost::Cannot_Use_Instance_Scope_Operator_Outside_Instance.new(expr)
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
					raise Lost::Undeclared_Identifier.new(expr)
				end
			elsif scope
				# note: Delegate ruby calls automatically
				proxy_method = "proxy_#{expr.value}"
				if scope.has?(expr.value) && !scope.respond_to?(proxy_method)
					result = scope.get expr.value
					# If the result is a function, duplicate it and set its enclosing_scope to the current scope. This ensures composed types (like `Thing | Record`) have functions that reference the correct type
					return rebind_func_to_scope(result, scope) if result.is_a? Lost::Func
					result
				elsif scope.respond_to? proxy_method
					# Prefer the instance's own owning Type first -- for a tagged variant (e.g. `Array\Web_Server`) this is a distinct Type from the plain global one, and holds the actual override. Only fall back to a blind by-name search of the stack (which only ever finds the plain global type, e.g. plain "Array") when the instance isn't linked to a Type that declares this method itself.
					type_def       = if scope.enclosing_scope.is_a?(Lost::Type) && scope.enclosing_scope.has?(expr.value)
						scope.enclosing_scope
					else
						type_name  = scope.class.name.split('::').last
						type_scope = stack.reverse_each.find { |s| s.has?(type_name) }
						type_scope && type_scope[type_name]
					end
					declared_value = type_def[expr.value] if type_def

					if declared_value.is_a? Lost::Func
						# Use the actual function from the Type, not an empty wrapper
						return rebind_func_to_scope(declared_value, scope)
					else
						# It's a variable/property
						return scope.send(proxy_method)
					end
				elsif scope.is_a?(Lost::Instance) && scope.enclosing_scope&.is_a?(Lost::Type) && scope.enclosing_scope&.has?(expr.value)
					if expr.type || expr.type_struct
						# A bare annotated identifier (`x: Number`) must self-declare its own per-instance copy, exactly like the nil-init idiom (`x,`) already does (see #interp_nil_init's identical shadowing fix) -- reading straight through to the enclosing Type's own nil placeholder instead would mean the instance never gets its own key, so a later `./x = value` would wrongly raise Cannot_Assign_Undeclared_Identifier.
						self_declare_annotated_identifier expr
					else
						# todo: This seems like a hack. This currently prevents instances from shadowing it's type's declarations.
						# Method/property exists on the Type, not the instance
						return rebind_func_to_scope(scope.enclosing_scope.get(expr.value), scope)
					end
				elsif expr.type || expr.type_struct
					self_declare_annotated_identifier expr
				else
					raise Lost::Undeclared_Identifier.new(expr)
				end
			else
				# When scope is nil, errors must be raised
				if %w(./ ../).include? expr.scope_operator&.value
					raise_missing_scope_operator_target! expr, expr.scope_operator.value
				elsif expr.type || expr.type_struct
					self_declare_annotated_identifier expr
				elsif stack.any? { |s| s.equal? global } && resolve_forward_declaration(expr.value) && global.has?(expr.value)
					# not reached yet in file order, but declared somewhere later on -- forced early. Identity check (not #include?, which is `==` and can hit an Lost type's own overload -- e.g. Lost::Array#== assumes its operand also has .values). Global being absent from the stack means we're deliberately excluding it (a plain `x.y` dot access, #interp_dot_scope's exclude_global_scope: true) -- a member missing on x should stay missing, not quietly resolve to an unrelated global
					global[expr.value]
				elsif (variants = tagged_variants_for(expr.value)).length == 1
					# A tagged declaration (`Task\Schema {}`) never binds its bare name like a plain `Type {}` does -- unambiguous with one variant, so allow it (mirrors Bare Named Structs). 2+ variants stay unreachable except via `Name\Tag`.
					variants.first
				else
					raise Lost::Undeclared_Identifier.new(expr)
				end
			end

			if value.is_a?(Lost::Type)
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

				result    = expr.value
				sub_exprs = result.scan(/(?<!\\)`(.*?)(?<!\\)`/).flatten

				sub_exprs.each do |sub|
					# Reuses the interpreter's own @parser (not a fresh Lost.parse) so it still knows about @operator declarations registered elsewhere in the program -- #input= resets the cursor but not @custom_infix/etc.
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
				Lost::Return.new returned
			else
				overload_func = find_in_stack expr.operator.value
				if overload_func.is_a? Lost::Func
					call           = Lost::Call_Expr.new
					call.arguments = [expr.expression]
					interp_func_body overload_func, call
				else
					raise Lost::Unhandled_Prefix.new(expr)
				end
			end
		end

		# @param expr [Lost::Infix_Expr]
		def interp_infix_assignment expr
			assignment_scope = scope_for_identifier expr.left # Reminder; this returns a scope whether or not the identifier exists

			# A type annotation (`x: Number = value`) is itself a declaration, so it's allowed to introduce a brand-new identifier just like `:=`, even though plain `=` otherwise requires the identifier to already exist. An inline signature (`x: Type(Param;) = value`) is the same idea — expr.left is a Func_Signature_Expr instead of a plain annotated Identifier_Expr, but it's just as self-declaring. A bare struct annotation (`thing: <String, Number> = value`) is self-declaring the same way, even with no `expr.left.type`.
			has_type_annotation = (expr.left.is_a?(Lost::Identifier_Expr) && (expr.left.type || expr.left.type_struct)) ||
			                      expr.left.is_a?(Lost::Func_Signature_Expr)
			assignment_scope    ||= stack.last if has_type_annotation

			# If using a scope operator but the scope doesn't exist, raise an error
			if expr.left.is_a?(Lost::Identifier_Expr) && expr.left.scope_operator && assignment_scope.nil?
				raise_missing_scope_operator_target! expr, expr.left.scope_operator.value
			end

			# For plain identifiers (no scope operator) inside an Instance/Type body, new declarations should go to that Instance/Type, not to an enclosing scope that happens to have the same identifier. This fixes a bug that prevented HTML Layout's `title` from capturing Title's `title` declaration in examples/basic_html_page.tape.
			if expr.left.is_a?(Lost::Identifier_Expr) && !expr.left.scope_operator
				current_scope = stack.last

				if (current_scope.is_a?(Lost::Instance) || current_scope.is_a?(Lost::Type)) &&
				   assignment_scope != current_scope && !current_scope.has?(expr.left.value)
					# The identifier exists in some enclosing scope but not in the current Instance/Type. Treat this as a new declaration on the current scope.
					assignment_scope = current_scope
				end
			end

			#
			# Special handling for load directive assignment, subscript, and maybe more later.
			#

			if expr.left.is_a? Lost::Subscript_Expr
				if expr.left.expression.expressions.count > 1
					raise Lost::Too_Many_Subscript_Expressions.new(expr.left)
				end
				# note: I'm interpreting only the first expression of left.expression.expressions as the key because the brackets are a Circumfix_Expr which uses an array to store the values.
				receiver = interpret expr.left.receiver
				key      = interpret expr.left.expression.expressions.first
				value    = interpret expr.right

				if receiver.is_a? Lost::Dictionary
					receiver.proxy_set key, value
					return receiver.proxy_get key
				else
					receiver[key] = value
					return receiver[key] # note: Intentionally returning the value here because the code starting with the directive check runs to the end of the method. todo: Imrpove?
				end
			end

			# Handle dot assignment
			if expr.left.is_a?(Lost::Infix_Expr) && expr.left.operator.value == '.'
				return assign_dot_member expr, expr.left, interpret(expr.right)
			end

			if expr.right.is_a?(Lost::Directive_Expr) && expr.right.name.value == 'load'
				filepath  = interpret expr.right.expression
				new_scope = Lost::Scope.new expr.left.value
				load_file_into_scope filepath, new_scope
				right_value = new_scope
			else
				right_value = interpret expr.right
			end

			# A Class-styled identifier (`My_Type = Other {}`) assigning a Scope value is itself a declaration, same reasoning as has_type_annotation above: `=` onto a fresh Class-styled name is how types get named/aliased, so it's allowed to introduce the identifier rather than requiring `:=` first.
			is_class_declaration = Lost.type_of_identifier(expr.left.value) == :Identifier && right_value.is_a?(Lost::Scope)
			assignment_scope     ||= stack.last if is_class_declaration

			# Before the actual assignment, the identifier is checked for specific behavior errors based on its expression type (class, constant, variable/function)
			case Lost.type_of_identifier expr.left.value
			when :IDENTIFIER
				# It can only be assigned once, so if the declaration exists, fail. An undeclared constant falls through to the Cannot_Reassign_Undeclared_Identifier check below.
				if assignment_scope&.has? expr.left.value
					raise Lost::Cannot_Reassign_Constant.new(expr.left)
				end
			when :Identifier
				# It can only be assigned `value` of Lost::Scope, which includes Lost::Type
				if !right_value.is_a?(Lost::Scope)
					raise Lost::Cannot_Assign_Incompatible_Type.new(expr)
				end
			when :identifier
				if assignment_scope
					# If the left side of the expression was declared with a type annotation, the type of `right_value` is enforced here.
					# `expr.left.type` covers the first, self-declaring assignment (the annotation is right here on this expression); the recorded type_by_identifier value covers every reassignment after that, once the annotation itself is gone. An inline signature (Func_Signature_Expr) supplies its own type directly, since it has no name to look up.
					type      = if expr.left.is_a? Lost::Func_Signature_Expr
						build_func_signature expr.left
					else
						expr.left.type&.value || assignment_scope.type_by_identifier[expr.left.value]
					end
					type      = type.name if type.is_a?(Lost::Type)
					signature = resolve_func_signature type

					if signature
						unless signature.matches? right_value
							raise Lost::Type_Contract_Violation.new(expr, signature.to_s, describe_value_shape(right_value))
						end
					else
						name = type_name_to_string(right_value)
						if type && name != type
							raise Lost::Type_Contract_Violation.new(expr, type, name)
						end
					end
				end
			end

			unless assignment_scope && (assignment_scope.has?(expr.left.value) || has_type_annotation || is_class_declaration)
				# it may not be declared using =
				raise Lost::Cannot_Assign_Undeclared_Identifier.new(expr)
			end

			if expr.left.is_a?(Lost::Identifier_Expr) && expr.left.type
				assignment_scope.type_by_identifier[expr.left.value] = expr.left.type.value
			elsif expr.left.is_a? Lost::Func_Signature_Expr
				# Recorded so future reassignments (which are plain Identifier_Exprs with no annotation of their own) still resolve back to this signature to check against.
				assignment_scope.type_by_identifier[expr.left.value] = build_func_signature expr.left
			end

			assignment_scope.declare expr.left.value, right_value
			track_static_declaration assignment_scope, expr.left

			return right_value
		end

		# todo; Types may be composed of multiple types, what happens in that case?
		# @param expr [Lost::Infix_Expr]
		def interp_infix_declaration expr
			# `(a, b) := <tuple-or-struct-valued expr>` -- destructuring, handled entirely separately from the single-identifier case below (no scope operators, no type-by-identifier locking against a bare `.value`, none of it applies to a target list).
			if expr.left.is_a?(Lost::Circumfix_Expr) && expr.left.grouping == '()'
				return interp_destructuring_declaration expr
			end

			if expr.left.is_a?(Lost::Infix_Expr) && expr.left.operator&.value == '.'
				return assign_dot_member expr, expr.left, interpret(expr.right), declare: true
			end

			# Only scope-operator forms (`../x`, `./x`, `.x`) target a specific scope. A plain `:=` always declares on the current scope, shadowing any identically-named identifier in an enclosing scope rather than re-declaring on it.
			has_scope_operator = expr.left.is_a?(Lost::Identifier_Expr) && expr.left.scope_operator
			assignment_scope   = scope_for_identifier expr.left if has_scope_operator

			# If using a scope operator but the scope doesn't exist, raise an error (mirrors interp_infix_assignment).
			if has_scope_operator && assignment_scope.nil?
				raise_missing_scope_operator_target! expr, expr.left.scope_operator.value
			end

			assignment_scope ||= stack.last

			# note; `./`, `../` self-declaring a member that doesn't exist yet is valid but only while the type/instance is still under construction (see #still_under_construction?) -- calling a static method later and self-declaring a brand-new static from inside it isn't allowed.
			if has_scope_operator && assignment_scope.is_a?(Lost::Type) && !assignment_scope.has?(expr.left.value)
				raise Lost::Cannot_Assign_Undeclared_Identifier.new(expr) unless still_under_construction? assignment_scope
			end

			right_value = if expr.right.is_a?(Lost::Directive_Expr) && expr.right.name.value == 'load'
				filepath  = interpret expr.right.expression
				new_scope = Lost::Scope.new expr.left.value
				load_file_into_scope filepath, new_scope
				new_scope
			else
				interpret expr.right
			end

			assignment_scope.declare expr.left.value, right_value

			assignment_scope.type_by_identifier[expr.left.value] = type_name_to_string right_value
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
				raise Lost::Invalid_Destructuring_Target.new(expr)
			end

			right_value = interpret expr.right
			values      = destructurable_values right_value

			unless values
				raise Lost::Invalid_Destructuring_Source.new(expr)
			end

			if targets.length > values.length
				raise Lost::Destructuring_Arity_Mismatch.new(expr, targets.length, values.length)
			end

			targets.each_with_index do |target, i|
				value = values[i]

				if target.is_a? Lost::Identifier_Expr
					declare_destructuring_local expr, target, value
				else
					assign_dot_member expr, target, value
				end
			end

			right_value
		end

		def destructuring_target? target
			target.is_a?(Lost::Identifier_Expr) ||
				(target.is_a?(Lost::Infix_Expr) && target.operator&.value == '.' && target.right.is_a?(Lost::Identifier_Expr))
		end

		def declare_destructuring_local expr, target, value
			if target.type
				expected = target.type.value
				actual   = type_name_to_string value
				if actual != expected
					raise Lost::Type_Contract_Violation.new(expr, expected, actual)
				end
			end

			assignment_scope = stack.last
			assignment_scope.declare target.value, value, type_name_to_string(value)
			track_static_declaration assignment_scope, target
		end

		# True for a top-level `../x := value` or `Self.x := value` static declaration -- both run once during the type's own body walk and must not be re-run for every constructed instance (see #run_type_body_on_instance). `Self.x := value` has a different AST shape than `../x := value` (a `.` dot-target on the left of `:=`, not a scope-operator-prefixed Identifier_Expr), so it needs its own check here rather than falling out of the same one.
		def static_var_declaration_expr? expr
			return false unless expr.is_a?(Lost::Infix_Expr) && expr.operator&.value == ':='

			left = expr.left
			return true if left.is_a?(Lost::Identifier_Expr) && left.scope_operator&.value == '../'

			left.is_a?(Lost::Infix_Expr) && left.operator&.value == '.' &&
				left.left.is_a?(Lost::Identifier_Expr) && !left.left.scope_operator && left.left.value == 'Self'
		end

		# A scope that is "under construction" is still allowed to self-declare a brand-new member via `./`, `../`, `self`, or `Self`
		def still_under_construction? scope
			if scope.is_a? Lost::Instance
				scope.has? 'new'
			else
				scope.declaration_in_progress
			end
		end

		# Shared by every way of writing through `.` onto an already-interpreted receiver.
		def assign_dot_member expr, target, value, declare: false
			receiver = interpret target.left
			property = target.right.value

			# `self`/`Self` are keyword sugar for `./`/`../` (see #interp_identifier) but arrive here as an ordinary `.` dot-target. `./x`/`../x` writes (#interp_infix_declaration's scope-operator branch, #interp_infix_assignment's general flow) never run Cannot_Reassign_Constant or check_dot_access_permissions! at all -- only the external-`.`-write rules below do (see "Member Creation Is Strict") -- so self/Self route around both entirely here too, for both `=` and `:=`, matching `./`/`../` exactly rather than just the not-yet-declared case.
			self_keyword = target.left.is_a?(Lost::Identifier_Expr) && !target.left.scope_operator &&
			               Lost::SELF_KEYWORDS.include?(target.left.value)

			if self_keyword && receiver.is_a?(Lost::Scope)
				unless receiver.has?(property) || still_under_construction?(receiver)
					raise Lost::Cannot_Assign_Undeclared_Identifier.new(expr)
				end

				if declare
					receiver.static_declarations.add property if target.left.value == 'Self'
					return receiver.declare property, value, type_name_to_string(value)
				end

				expected = receiver.type_by_identifier[property]
				actual   = type_name_to_string value
				raise Lost::Type_Contract_Violation.new(expr, expected, actual) if expected && actual != expected

				receiver[property] = value
				return value
			end

			unless receiver.is_a?(Lost::Scope) && receiver.has?(property)
				raise Lost::Cannot_Assign_Undeclared_Identifier.new(expr)
			end

			if Lost.type_of_identifier(property) == :IDENTIFIER
				raise Lost::Cannot_Reassign_Constant.new(expr)
			end

			check_dot_access_permissions! receiver, property, expr

			actual = type_name_to_string value
			if declare
				receiver.type_by_identifier[property] = actual
			else
				expected = receiver.type_by_identifier[property]
				if expected && actual != expected
					raise Lost::Type_Contract_Violation.new(expr, expected, actual)
				end
			end

			receiver[property] = value
			value
		end

		# Lost::Tuple/Lost::Struct both carry a plain Ruby-level `.values` reader holding the raw backing array (distinct from their Lost-level `.values` dot-access, which wraps the same data in an Lost::Array for Lost code to read).
		def destructurable_values value
			case value
			when Lost::Tuple, Lost::Struct
				value.values
			end
		end

		# @param expr [Lost::Infix_Expr]
		def interp_dot_infix expr
			return interp_dot_new expr if expr.right.is 'new'

			receiver = maybe_instance interpret expr.left

			unless receiver.kind_of?(Lost::Scope) || receiver.kind_of?(Lost::Range)
				raise Lost::Invalid_Dot_Infix_Left_Operand.new(expr)
			end

			case receiver
			when Lost::Array, Lost::Tuple
				interp_dot_array_or_tuple receiver, expr
			when Lost::Range
				interp_dot_range receiver, expr
			when Lost::Dictionary
				interp_dot_dictionary receiver, expr
			else
				# A tagged type reference on the right (`ns.Abc\<Number>`) isn't an Identifier_Expr, so it bypasses #interp_dot_scope's right-operand validation.
				if expr.right.instance_of? Lost::Type_Expr
					return interp_member_access receiver, expr.right
				end

				interp_dot_scope receiver, expr
			end
		rescue Lost::Undeclared_Identifier, Lost::Cannot_Call_Instance_Member_On_Type
			raise unless expr.operator.value == '.?'
			nil
		end

		def stringify_for_display value, show_quotes: false
			value = maybe_instance value
			# A bare Type's `to_s` (copied from its own body) assumes real instance context and crashes if called directly on the Type itself, so only attempt it on a genuine Instance.
			return value unless value.is_a? Lost::Instance

			method_name       = show_quotes && value.is_a?(Lost::String) ? 'pretty_print' : 'to_s'
			to_s_ident        = Lost::Identifier_Expr.new
			to_s_ident.lexeme = Lost::Lexeme.new(:identifier, method_name)
			func              = begin
				interp_member_access value, to_s_ident
			rescue Lost::Undeclared_Identifier
				nil
			end
			return value unless func.is_a? Lost::Func

			call           = Lost::Call_Expr.new
			call.arguments = []
			interp_func_body func, call
		end

		# Interprets `expr` (the right side of `x.y`) scoped only to `receiver` and global scope, so a missing member can't fall through to an unrelated identically-named one still active further down the caller's stack (this caused a real infinite recursion before the fix).
		def interp_member_access receiver, expr, exclude_global_scope: false
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

		# Bare `X.new` (no parens) is equivalent to `X()`: full construction including `new(;)`, so a constructor with required params raises Missing_Argument. `X.new(...)` with parens never lands here; #interp_call intercepts it and routes to #interp_type_call directly.
		# @param expr [Lost::Infix_Expr]
		def interp_dot_new expr
			receiver = interpret expr.left

			unless receiver.is_a? Lost::Type
				raise Lost::Cannot_Initialize_Non_Type_Identifier.new expr.left
			end

			call           = Lost::Call_Expr.new
			call.receiver  = expr.left
			call.arguments = []
			interp_type_call receiver, call
		end

		# The dot sub-handlers below all take the receiver #interp_dot_infix already interpreted rather than re-interpreting expr.left themselves — re-interpreting ran the receiver expression's side effects (calls, constructions) a second or third time.
		# Bounds/type-checked element access for `.N`/`.N.M...` dot-index syntax on an Array/Tuple -- plain `values[index]` (Ruby's own Array#[]) silently returns nil past the end, and silently truncates a non-integer index (e.g. `.0.1` lexes as the single float 0.1, which Ruby's [] truncates to index 0) -- both looked like a legitimate result instead of a mistake.
		def array_index_value collection, index, expr
			unless index.is_a?(::Integer) && index.between?(-collection.values.length, collection.values.length - 1)
				raise Lost::Invalid_Array_Index.new(expr)
			end
			collection.values[index]
		end

		def interp_dot_array_or_tuple scope, expr
			case
			when expr.right.is(Lost::Func_Expr) && expr.right.name.value == 'each'
				interp_each_loop scope, expr.right
				scope

			when expr.right.is(Lost::Number_Expr)
				array_index_value scope, expr.right.value, expr

			when expr.right.is(Lost::Array_Index_Expr)
				expr.right.indices_in_order.reduce(scope) do |current, index|
					raise Lost::Invalid_Dot_Infix_Left_Operand.new(expr) unless current.is_a?(Lost::Array)
					array_index_value current, index, expr
				end

			else
				interp_dot_scope scope, expr
			end
		end

		def interp_dot_range range, expr
			return interp_each_loop range, expr.right if expr.right.is(Lost::Func_Expr) && expr.right.name.value == 'each'
			interp_dot_scope range, expr
		end

		def interp_dot_dictionary dict, expr
			if expr.right.is_a? Lost::Identifier_Expr
				key_sym = expr.right.value.to_sym
				if dict.hash.has_key?(key_sym)
					return dict.hash[key_sym]
				end
			end

			interp_member_access dict, expr.right
		end

		def interp_dot_scope scope, expr
			raise Lost::Invalid_Dot_Infix_Left_Operand.new(expr) if scope.nil?
			raise Lost::Invalid_Dot_Infix_Right_Operand.new(expr.right) unless expr.right.instance_of? Lost::Identifier_Expr

			check_dot_access_permissions! scope, expr.right.value, expr

			interp_member_access scope, expr.right, exclude_global_scope: true
		end

		def interp_each_loop collection, func_expr
			collection.each do |it|
				each_scope                 = Lost::Scope.new 'each(;)'
				each_scope.enclosing_scope = stack.last
				push_scope each_scope
				each_scope.declare 'it', it
				func_expr.parameters.each { |e| interpret e }
				func_expr.expressions.each { |e| interpret e }
				pop_scope
			end
		end

		# The values for expr.operator, expr.left, and expr.right should all exist by this point
		# @param expr [Lost::Nil_Init_Expr]
		def interp_nil_init expr
			# attr_accessor :operator, :left, :right
			current_scope = stack.last

			# Same shadowing fix as interp_infix_assignment: inside an Instance/Type body, a plain identifier's nil-init must declare on the current Instance/Type even if an enclosing scope (e.g. the Type, whose body already ran once at definition time) already has an identically-named identifier. Otherwise re-running `thing,` per-instance in interp_type_call finds the Type's stale copy and never declares it on the instance.
			if (current_scope.is_a?(Lost::Instance) || current_scope.is_a?(Lost::Type)) && !current_scope.has?(expr.left.value)
				current_scope.declare expr.left.value, interpret(expr.right)
				track_static_declaration current_scope, expr.left
				return current_scope.get expr.left.value
			end

			begin
				return interpret expr.left
			rescue # Lost::Undeclared_Identifier and ArgumentError # todo: Why `ArgumentError: empty string`. Once this is resolved, then the rescue here should explicitly catch Undeclared_Identifier, probably.
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
			if operand.is_a?(Lost::Instance) && operand.has?(operator)
				return operand.get operator
			end

			if operand.is_a?(Lost::Scope) && operand.enclosing_scope.is_a?(Lost::Type) && operand.enclosing_scope.has?(operator)
				return operand.enclosing_scope.get operator
			end

			find_in_stack operator, excluding: Lost::Type
		end

		# Second-level dispatcher for infix operators, mirroring #interpret's own shape: each branch hands off to one interp_*_infix handler. The first group dispatches before operand evaluation — the assignment family treats the left side as a target rather than a value, `@` (the unpack marker) isn't a value at all, and logical operators must stay lazy to short-circuit. Every remaining operator evaluates each operand exactly once, here, and passes the values down so no handler re-interprets an operand (side effects run once).
		# @param expr [Lost::Infix_Expr]
		def interp_infix expr
			operator = expr.operator.value

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
			call           = Lost::Call_Expr.new
			call.arguments = [expr.left, expr.right]
			interp_func_body overload, call, arg_values: values
		end

		# Interprets its own operands (the one infix handler that does) because `&&`/`||` must short-circuit. A scope-level @operator overload still wins first, called with the raw expressions so the operands evaluate once, eagerly, inside the call.
		def interp_logical_infix expr
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, nil) if overload.is_a? Lost::Func

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

			if overload.is_a? Lost::Func
				call_operator_overload overload, expr, [left, right]
			else
				maybe_instance(left).send expr.operator.value, maybe_instance(right)
			end
		end

		# note; I'm special casing these because they don't behave like the traditional == and != in Ruby.
		# The literal `Any` type (lost/preload.tape), a universal wildcard -- see #interp_comparison_infix.
		def any_type? value
			value.is_a?(Lost::Type) && value.name == 'Any'
		end

		def interp_comparison_infix expr, left, right
			# `Any` is a supertype of everything except nil, no composition needed. True for every "equal-ish" op, false for "different-ish" ones.
			if ANY_WILDCARD_COMPARISON_OPERATORS.include?(expr.operator.value) && (any_type?(left) || any_type?(right))
				other = any_type?(left) ? right : left
				equal = !other.nil?
				return %w(== === =>= =<=).include?(expr.operator.value) ? equal : !equal
			end

			case expr.operator.value
			when '===', '=!=', '=>=', '=<=', '=/='
				# `.type_objects`, not `.types` -- `Lost::Struct < Instance < Type` inherits Type's own
				# `.types` (the composed-type-name Set, e.g. `Set['Struct']` for every struct alike),
				# which shadows/collides with what's actually wanted here: the struct's own per-member
				# type objects (`.type_objects`, backed by its `@declarations['types']`).
				left_tag  = left.is_a?(Lost::Type) ? left.tag_instance&.type_objects : nil
				right_tag = right.is_a?(Lost::Type) ? right.tag_instance&.type_objects : nil

				# note; `left`/`right` are whatever #interpret returned (a raw Ruby Integer/String/etc for literals, not necessarily an Lost::Type/Instance), so `.types` can't be called on them directly. Using #composed_types_for here which resolves the correct composed-type set.
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

				# note; A type declaring `@operator ==` but no `@operator !=` of its own (the common case lost/struct.tape's Member/Struct are exactly this) used to fall straight through to Ruby's own #!= for `!=`, which is identity-based and ignores the custom == entirely, two structurally-equal Members compared unequal with `!=` even though `==` correctly said they were equal. `!=` now derives from a declared `==` overload (negated) when it has no overload of its own, matching how most languages auto-derive != from ==.
				if !overload.is_a?(Lost::Func) && expr.operator.value == '!='
					overload      = find_operator_overload '==', left
					negate_result = true
				end

				if overload.is_a? Lost::Func
					result = call_operator_overload overload, expr, [left, right]
					negate_result ? !truthy?(result) : result
				elsif left.respond_to?(expr.operator.value) && !(expr.operator.value == '<=>' && left.method(:<=>).owner == ::Kernel)
					left.send expr.operator.value, right
				else
					# note; Numbers/Strings reach here fine (they decay to plain Ruby values with a native <=>/</>/etc.), but a plain Lost::Instance has none of these implemented -- except <=>, which Ruby's own Kernel/Object gives every object a trivial, identity-based default for. `respond_to?` alone can't tell that apart from a real one, so the method's actual owner is checked too. There's no sensible fallback to invent here, equality doesn't imply order.
					raise Lost::Undeclared_Infix_Operator.new expr
				end
			end
		end

		# (a += b)  ==>  (a = (a + b)). Compound operators only ever consult a scope-level @operator overload (never the operand's own), since their built-in meaning is assignment, not a property of the operand's type.
		def interp_compound_infix expr, left, right
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, [left, right]) if overload.is_a? Lost::Func

			base_op = expr.operator.value[..-2] # Trim the = from +=, -=, etc.
			result  = maybe_instance(left).send base_op, maybe_instance(right)

			# Assign back to left side -- a dot-target (`instance.member += ...`) goes through the same
			# #assign_dot_member path plain `.`-assignment uses; #scope_for_identifier only understands
			# plain Identifier_Exprs, so a dot-target used to silently fall through to `stack.last` and
			# declare a bogus `nil`-named identifier there instead of touching the actual member.
			if expr.left.is_a?(Lost::Infix_Expr) && expr.left.operator&.value == '.'
				assign_dot_member expr, expr.left, result
			else
				assignment_scope = scope_for_identifier expr.left
				assignment_scope.declare expr.left.value, result
			end
		end

		def interp_range_infix expr, start, finish
			overload = find_operator_overload expr.operator.value
			return call_operator_overload(overload, expr, [start, finish]) if overload.is_a? Lost::Func

			case expr.operator.value
			when '...'
				Lost::Range.new start, finish
			when '..<'
				Lost::Range.new start, finish, exclude_end: true
			when '>..'
				Lost::Range.new start + 1, finish
			when '>.<'
				Lost::Range.new start + 1, finish, exclude_end: true
			end
		end

		# A user-declared @operator with no built-in category of its own. The operand's own overload wins over a global one (#find_operator_overload). Reachable with no overload in scope when the operator is declared inside some other scope (the parser's pre-scan registers it file-wide) — that used to silently evaluate to nil; now it raises.
		def interp_custom_infix expr, left, right
			overload = find_operator_overload expr.operator.value, maybe_instance(left)
			unless overload.is_a? Lost::Func
				raise Lost::Undeclared_Infix_Operator.new(expr)
			end

			call_operator_overload overload, expr, [left, right]
		end

		# @param expr [Lost::Postfix_Expr]
		def interp_postfix expr
			# note: See constants.rb POSTFIX for exhaustive list of language-defined postfixes. Currently there are no built-in postfix operators.
			# 1) look up the opreator (expr.operator.value) as it should be a normal func in the scope.
			# 2) call it with expr.expression as its argument. It should only take one argument.
			postfix_overloaded_func = find_in_stack expr.operator.value

			if !postfix_overloaded_func
				raise "Could not find #{expr.operator.value} declared anywhere man!"
			end

			call           = Lost::Call_Expr.new
			call.arguments = [expr.expression]
			interp_func_body postfix_overloaded_func, call
		end

		# @param expr [Lost::Percent_Literal_Expr < Lost::Circumfix_Expr]
		def interp_percent_literal expr
			literal_expr_class = case expr.kind
			when 'string', 'str', 'Str', 'STR' then Lost::String_Expr
			when 'symbol', 'sym', 'Sym', 'SYM' then Lost::Symbol_Expr
			end

			# %string/%symbol preserve the identifier's own casing; the rest force one.
			casing = case expr.kind
			when 'string', 'symbol' then :itself
			when 'str', 'sym' then :downcase
			when 'Str', 'Sym' then :capitalize
			when 'STR', 'SYM' then :upcase
			end

			array_expr             = Lost::Circumfix_Expr.new
			array_expr.grouping    = '[]'
			array_expr.expressions = expr.expressions.map do |it|
				# A backtick item is evaluated immediately, like string interpolation, then folded through the same to_s + casing treatment as every other item. No Lost::Statement gets built here (unlike #invoke_statement's callers), so use_caller_scope/memoize never come into play -- it's always immediate, in whatever scope this literal is written in.
				if it.is_a? Lost::Statement_Expr
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
				array             = Lost::Array.new
				array.expressions = expr.expressions

				values = []
				expr.expressions.each do |e|
					# Same as #interp_percent_literal above: `` `expr` `` inside an array literal evaluates immediately, no Lost::Statement built.
					e = e.expression if e.is_a? Lost::Statement_Expr
					values << interpret(e)
				end
				link_instance_to_type array, 'Array'

				# Make values accessible as an Lost identifier (`for values`, `arr.values`), sharing the same list object as the real backing store so mutations (push/pop/etc) stay in sync.
				array.values                 = values
				array.declarations['values'] = values

				array
			when '()'
				if expr.expressions.count == 1
					# note: Single expressions should be treated as though they were not inside parentheses so that algebraic expressions can be grouped using parentheses. If I wrap single expressions in a Tuple then I have to also unwrap them later for arithmetic operations.
					interpret expr.expressions.first
				else
					values = expr.expressions.map { |e| interpret(e) }
					tuple  = Lost::Tuple.new values
					link_instance_to_type tuple, 'Tuple'
					tuple.declarations['values'] = tuple.values
					tuple
				end
			when '{}'
				dict = expr.expressions.reduce(Lost::Dictionary.new) do |dict, it|
					if it.is_a? Lost::Identifier_Expr
						dict.proxy_set it.value.to_sym, nil
					elsif it.is_a? Lost::Infix_Expr
						case it.operator.value
						when ':', '='
							if it.left.is_a?(Lost::Identifier_Expr) || it.left.is_a?(Lost::Symbol_Expr) || it.left.is_a?(Lost::String_Expr)
								# note; Deliberately NOT wrap_string_literal_value here, unlike Array/Tuple literals -- Dictionary#hash is handed straight to Ruby-level consumers as a raw Hash (Sequel queries in table.rb chief among them), so wrapping a value into Lost::String here broke every DB call passing string attributes. #to_s below just always double-quotes String values instead of matching the original literal's quote char.
								dict.proxy_set it.left.value.to_sym, interpret(it.right)
							else
								# The left operand should be allowed to be any hashable object. It's too early in the project to consider hashing but this'll be a good reminder.
								raise Lost::Invalid_Dictionary_Key.new(it)
							end
						else
							raise Lost::Invalid_Dictionary_Infix_Operator.new(it)
						end
					end
					# In case I forget, #reduce requires that the injected value be returned to be passed to the next iteration.
					dict
				end
				link_instance_to_type dict, 'Dictionary'
				dict
			else
				raise Lost::Unknown_Circumfix_Grouping.new(expr)
			end
		end

		# @param expr [Lost::Call_Expr]
		def interp_call expr
			# `X.new(...)` parses as Call_Expr(receiver: Infix_Expr(X, '.', new), arguments: [...]). Intercept it here, before evaluating the receiver, so we don't route through interp_dot_new (which eagerly builds a whole Instance for bare `X.new`) and then build a second Instance via interp_type_call below. Bare `X.new` with no call still goes through interp_dot_new untouched, since it never reaches interp_call.
			if expr.receiver.is_a?(Lost::Infix_Expr) && expr.receiver.operator&.value == '.' && expr.receiver.right.is('new')
				type = interpret expr.receiver.left

				# Lost::Struct < Instance < Type (Ruby class hierarchy), so a bare struct schema value (`thing := <a: Number>`, or a persisted named struct -- see #interp_type) passes the `is_a? Lost::Type` check below too, but it has no `.expressions` for #interp_type_call's construction path to run -- route it through the same Lost::Struct call path #interp_call's own receiver-dispatch further down already uses for `thing(...)`.
				if type.is_a? Lost::Struct
					return interp_struct_call type, expr
				end

				unless type.is_a? Lost::Type
					raise Lost::Cannot_Initialize_Non_Type_Identifier.new(expr.receiver.left)
				end

				return interp_type_call type, expr
			end

			# A bare `` `expr`() `` written and called in the same place -- always immediate, in whatever scope it's written in. No Lost::Statement is ever built here, so #invoke_statement (used below, once one *has* been built and stored) doesn't apply.
			if expr.receiver.is_a? Lost::Statement_Expr
				return interpret expr.receiver.expression
			end

			receiver = interpret expr.receiver

			# A nil-safe dot chain (`x.?method`) that found nothing evaluates to nil deliberately -- a trailing call (`x.?method()`) should short-circuit to nil too, not try to invoke nil.
			if receiver.nil? && expr.receiver.is_a?(Lost::Infix_Expr) && expr.receiver.operator&.value == '.?'
				return nil
			end

			case receiver
			when Lost::Route
				interp_func_body receiver.handler, expr

			when Lost::Func
				interp_func_body receiver, expr

			when Lost::Struct
				interp_struct_call receiver, expr

			when Lost::Statement
				# Reached once a Statement has been stored in a variable (or field, etc.) and is being called from somewhere else -- Lost::Statement < Instance, so this has to come before the generic Instance branch below or it'd be mistaken for "construct a new Statement".
				invoke_statement receiver

			when Lost::Instance, Lost::Type
				interp_type_call receiver, expr

			when Lost::Func_Signature
				raise Lost::Cannot_Call_Func_Signature.new expr

			else
				raise Lost::Cannot_Call_Value.new expr.receiver
			end
		end

		# @param expr [Lost::Type_Expr]
		def interp_type expr
			return interp_anonymous_composition expr if expr.anonymous_composition

			# No body was parsed (`x: Abc\<Number>`, `y := Abc\<Number>`, `Abc\<Number>()`, `Abc\<4815>()`) so this references an existing type rather than declaring one. Dup it so tagging this reference doesn't mutate the shared declaration every other reference sees.
			if expr.expressions.nil?
				if expr.tag
					supplied = resolve_tag_reference expr, allow_spread: false

					# note; `expr.name` is normally a real type name ("String"), but if it's instead a local alias bound to an earlier tagged reference (`X := String\<Flying>`), re-tag against *that value's own* family name rather than treating "X" itself as a type name. So `X\<duck>` should behave exactly like `String\<duck>`, since `.name` on any Type object (dup'd or not) always reflects its true declared family.
					aliased     = find_in_stack expr.name
					lookup_name = aliased.is_a?(Lost::Type) ? aliased.name : expr.name

					existing = find_tagged_type_variant lookup_name, supplied

					# Declaring spreads a lone unnamed Struct-valued member (#interp_struct); unify by retrying a failed unspread match with spreading applied, rather than statically committing to one or the other.
					if !existing.is_a?(Lost::Type) && expr.tag.is_a?(Lost::Struct_Expr) && expr.tag.types.length == 1 && expr.tag.names[0].nil?
						spread_supplied = interp_struct expr.tag, allow_spread: true
						spread_existing = find_tagged_type_variant lookup_name, spread_supplied
						if spread_existing.is_a? Lost::Type
							supplied = spread_supplied
							existing = spread_existing
						end
					end
					unless existing.is_a? Lost::Type
						# Nothing declared under this name -> bare named struct (see Bare Named Structs, CLAUDE.md). Also allows re-declaring the same struct with an identical shape as a no-op.
						redeclaring_same_struct = aliased.is_a?(Lost::Struct) && aliased.get('name') == expr.name && aliased.structure_declaration_equal?(supplied)
						if (aliased.nil? || redeclaring_same_struct) && tagged_variants_for(lookup_name).empty?
							supplied.declare 'name', expr.name
							supplied.types = Set[expr.name] + supplied.types # `.types` inherited `Set['Struct']` alone from Struct#initialize's `super 'Struct'`; put the struct's own declared name first (own-name-before-composed, same order an ordinary `Ident | Struct {}` composition would produce) so type-identity checks (===, a `-> Ident` return-type contract, `type_name_to_string`'s `.types.first`, ...) see it as `Ident`-shaped, not just generically Struct-shaped.
							stack.last.declare expr.name, supplied if supplied.names.all?
							return supplied
						end

						# Base name is a real Type but nothing matches this shape yet -- a bare reference auto-declares it (empty body), same as writing `Array\String {}` explicitly first.
						unless aliased.is_a? Lost::Type
							raise Lost::Undeclared_Tagged_Type.new(expr)
						end
						existing                = declare_tagged_type_variant lookup_name, supplied, []
					end
				else
					existing = find_in_stack expr.name
					unless existing.is_a? Lost::Type
						raise Lost::Undeclared_Identifier.new(expr)
					end
				end

				# Object#dup is shallow so  @declarations/@static_declarations would still be the exact same Hash/Set every reference and the matched variant share, so tagging one would silently mutate all the others (and the variant itself). Fork them explicitly.
				referenced                     = existing.dup
				referenced.declarations        = existing.declarations.dup
				referenced.static_declarations = (existing.static_declarations || Set.new).dup
				if expr.tag
					# Call-site member values are usually positional (`Woof<'hello', 4815>`), but a member can be named at the reference site too (`Woof<key := 'hello'>`) to disambiguate an otherwise-ambiguous match. Either way, re-associate them with the names — and pick up any defaults — from the matched variant's own struct declaration (`Woof<String, key: Dictionary> {}`) so `.tag.key` still works on the resulting instance.
					declaration            = existing.tag_declaration
					declaration_names      = declaration.is_a?(Lost::Struct) ? declaration.names : []
					declaration_types      = declaration.is_a?(Lost::Struct) ? declaration.type_objects : [] # declared type objects, used below only to detect an unfilled default via identity
					declaration_type_names = declaration.is_a?(Lost::Struct) ? declaration.type_names : []
					declaration_values     = declaration.is_a?(Lost::Struct) ? declaration.values : []

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
				end
				declare_tag referenced
				return referenced
			end

			if expr.tag
				interp_tagged_type_declaration expr
			else
				interp_bare_type_declaration expr
			end
		end

		# A composition chain with no `{}` body (`Abc|Def`, `A & B`, ...) is a value, not a declaration, built by applying the chain to a fresh, unnamed Type exactly as if `X | Abc | Def { }` had been written for some unnamed X.
		def interp_anonymous_composition expr
			anonymous             = Lost::Type.new nil
			anonymous.types       = Set.new # Type#initialize seeds `@types = Set[name]` -- Set[nil] here, which would leave a stray nil in .types (breaking #find_ruby_class_for_type's `"Lost::#{type_name}"` lookup) since the union step below only ever adds, never resets.
			anonymous.expressions = [] # A real declaration always ends up with this set (even to []) via #interp_bare_type_declaration's own body-merge -- there's no body here, but #run_type_body_on_instance still expects an Array to iterate when constructing an instance.

			seed            = Lost::Composition_Expr.new
			seed.operator   = Lost::Lexeme.new(:operator, '|')
			seed.identifier = Lost::Identifier_Expr.new.tap { |it| it.lexeme = Lost::Lexeme.new(:Identifier, expr.name) }

			push_then_pop anonymous do
				interp_composition seed
				expr.expressions.each { |composition| interp_composition composition }
			end

			anonymous
		end

		# Shared tail of both declaration paths below: parent the type to the declaring scope, link it to its Lost:: Ruby class when one exists, record its own name in @types, and run `body_expressions` in the type's scope.
		def finish_type_declaration type, body_expressions
			type.enclosing_scope = stack.last

			lost_name = "Lost::#{type.name}"
			defined   = type.name[0] != '_' && Object.const_defined?(lost_name) # note; #const_defined? does not allow underscore as the first character, hence the underscore check.
			link_instance_to_type type, type.name if defined

			type.types ||= []
			type.types << type.name
			type.types = type.types.uniq

			type.declaration_in_progress = true
			begin
				push_then_pop type do
					body_expressions.each do |sub_expr|
						interpret sub_expr
					end
				end
			ensure
				type.declaration_in_progress = false
			end

			type
		end

		# A plain, untagged declaration (`String { ... }`) -- reopens/extends the same shared Type object across multiple declarations of the same bare name, e.g. how preload.tape's files each contribute to the same base String/Array/etc.
		def interp_bare_type_declaration expr
			existing = stack.last.has?(expr.name) && stack.last[expr.name]
			type     = existing.is_a?(Lost::Type) ? existing : Lost::Type.new(expr.name)

			type.expressions = (type.expressions || []) + expr.expressions
			finish_type_declaration type, expr.expressions

			stack.last.declare type.name, type
			type
		end

		# Resolves `expr.tag` (either form of `\`'s RHS) to a real Lost::Struct -- an inline literal (`Abc\<Number>`) interprets to one directly; a named reference (`Abc\Task_Schema`) is used as-is if it's already a Struct, or wrapped into the single-unnamed-member equivalent if it's a Type (`Abc\String` behaves like `Abc\<String>`); anything else raises. A named reference also records its own identifier text as `bare_reference_name` (see Struct#bare_reference_name) -- the *only* signal that later tells #tag_display_name to print `Array\String` back out bare instead of falling back to the struct's own `<...>` rendering.
		def resolve_tag_reference expr, allow_spread: true
			return interp_struct expr.tag, allow_spread: allow_spread if expr.tag.is_a? Lost::Struct_Expr

			value = interpret expr.tag
			if value.is_a? Lost::Struct
				value.bare_reference_name ||= expr.tag.value
				return value
			end

			unless value.is_a? Lost::Type
				raise Lost::Tag_Reference_Must_Be_Type_Or_Struct.new(expr)
			end

			# The single member's own value stays nil, same as any other schema-only member (see #interp_struct) -- `value` here is always a bare Type (just checked above), not real data.
			struct                     = build_struct [nil], [type_name_to_string(value)], [value], [nil]
			struct.bare_reference_name = expr.tag.value
			struct
		end

		# A tagged declaration (`String\<dict: Dictionary> { ... }`) is its own type, separate from the bare `String` and every other tag under the same name -- this stops one variant's `new`/methods from clobbering another's (a real bug this fixed).
		def interp_tagged_type_declaration expr
			struct = resolve_tag_reference expr
			declare_tagged_type_variant expr.name, struct, expr.expressions
		end

		# Shared by a real declaration and an auto-declared reference (interp_type) -- both just extend-or-create a Type variant under `name` tagged with `struct`.
		def declare_tagged_type_variant name, struct, body_expressions
			existing = tagged_variants_for(name, current_scope_only: true).find do |variant|
				variant.tag_declaration.structure_declaration_equal? struct
			end

			if existing
				variant = existing
			else
				variant             = Lost::Type.new(name)
				blueprint           = stack.last.has?(name) && stack.last[name]
				variant.expressions = blueprint.is_a?(Lost::Type) ? (blueprint.expressions || []).dup : []
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
			struct = interp_struct param.type_struct, allow_spread: false

			struct.names.each_with_index do |name, i|
				next unless name # unnamed members have nothing to check by name

				declared_type = struct.type_names[i]
				next if declared_type == 'Any'

				unless value.is_a?(Lost::Scope) && value.has?(name)
					raise Lost::Type_Contract_Violation.new(expr, "<#{struct.names.compact.join(', ')}>", describe_value_shape(value))
				end

				member_value = value.get name
				candidates   = member_value.nil? ? [] : member_candidate_type_names(member_value)
				unless candidates.include? declared_type
					raise Lost::Type_Contract_Violation.new(expr, declared_type, type_name_to_string(member_value))
				end
			end
		end

		# All type names a supplied member value could match a declared struct's member under -- its own primary name first, then everything it composes, so e.g. a `Div` satisfies a member declared `Dom` without being named Dom itself. See #find_tagged_type_variant.
		def member_candidate_type_names value
			case value
			when ::Integer, ::Float
				['Number']
			when ::String
				['String']
			when ::Symbol
				['Symbol']
			when ::TrueClass, ::FalseClass
				['Bool']
			else
				if value.is_a?(Lost::Type) && value.types && !value.types.empty?
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

			exact_types = candidate_lists.map(&:first)
			candidates.find { |variant| variant.tag_declaration.type_names == exact_types } ||
				candidates.find { |variant| variant.tag_declaration.satisfied_by_candidates? candidate_lists }
		end

		# Tagged variants declared under `base_name`, searched the same way #find_in_stack resolves a plain identifier -- innermost to outermost, stopping at the first scope that has any (lexical shadowing, not merging). `current_scope_only` restricts the search to `stack.last` alone, for declaration-time collision checks -- a nested tagged declaration should only ever collide with another declared in that exact scope, never one from an enclosing one.
		def tagged_variants_for base_name, current_scope_only: false
			scopes = current_scope_only ? [stack.last] : stack.reverse_each
			scopes.each do |scope|
				# `stack` can briefly hold non-Scope receivers during dot-access (e.g. Lost::Range).
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

		# For Lost::Database#proxy_create_table: finds the Table-composed type declared with this exact schema, if any, so the created table can be tagged with the model's real identity. Nil if none matches.
		def find_table_type_for_schema schema
			all_tagged_type_variants.find do |variant|
				variant.types.include?('Table') && variant.tag_declaration&.structure_declaration_equal?(schema)
			end
		end

		# Searches the full scope stack (innermost to outermost) for `key`, the same way a bare identifier resolves via #scope_for_identifier -- checking only `stack.last` would miss a type declared in an outer/global scope while evaluating from inside a nested context (e.g. a type's own declaration body during composition). This returns an Lost type. `excluding:` skips scopes of that class -- used by #find_operator_overload to keep looking past a currently-executing Type/Instance body, since merely being on the stack doesn't mean the *current* operands belong to it (Instance < Type, so excluding: Lost::Type skips both).
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
			"#{scope.name}#{Lost::TAG_OPERATOR}#{qualifier}"
		end

		# Makes `.tag` readable via Lost dot-access on a Type, Instance, or type reference, and marks it static so it's also readable straight off a bare Type (not just an instance). Only adds the declaration when this particular one actually has a tag, so plain untagged types don't pick up a stray `tag` member. Also refreshes `.display_name` (see Type#initialize) to fold the tag into the type's own displayable name, so a consumer like lost/member.tape's `to_s` never needs to know `.tag` exists at all.
		def declare_tag scope
			return unless scope.tag_instance

			scope.declarations['tag']          = scope.tag_instance
			scope.declarations['display_name'] = tag_display_name(scope)
			scope.static_declarations          = (scope.static_declarations || Set.new) + %w(tag display_name)
		end

		#
		# Lost::Type_Expr is converted to Lost::Type in #interp_type.
		# Lost::Instance inherits Lost::Type's @name and @types.
		#
		#     (See types.rb for Lost::Type and Lost::Instance declarations)
		#     (See expressions.rb for Lost::Type_Expr declaration)
		#
		# - Push instance onto stack
		# - Interpret type.expressions so the declarations are made on the instance
		# - Keep instance on the stack
		# - For each Lost::Func declared on instance, set `func.enclosing_scope = instance`
		# - Interpret type[:new], the initializer
		# - Delete :new from instance, inheritd from type, not needed on the instance
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

							if expr.is_a?(Lost::Func_Expr) && expr.name.is_a?(Lost::Identifier_Expr) &&
							   expr.name.scope_operator&.value == '../'
								next
							end

							interpret expr
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
				next unless decl.is_a? Lost::Func

				cloned                     = decl.dup
				cloned.enclosing_scope     = instance
				instance.declarations[key] = cloned
			end
		end

		# Builds the raw instance for #interp_type_call: backed by its Lost:: Ruby class when one exists, linked to its type, struct bound, and the type's body run on it. `new(;)` is invoked afterward by #interp_type_call itself.
		def build_instance_of_type type, expr
			ruby_class = find_ruby_class_for_type type
			instance   = ruby_class ? ruby_class.new : Lost::Instance.new(type.name)

			# `.name =`/`.types =` are Ruby attr writes only -- for a composed type sharing a built-in's Ruby class (e.g. `Tasks | Table {}` -> Lost::Table), the `declarations[...]` writes below are also needed or an Lost-level `.name`/`.types` dot-read stays stuck on the backing class's own values.
			instance.name                  = type.name
			instance.declarations['name']  = type.name
			instance.types                 = type.types
			instance.declarations['types'] = wrap_lost_array type.types.to_a
			instance.enclosing_scope       = type
			instance.expressions           = type.expressions

			# note; Bind structs onto the instance before the type's expressions (and therefore `new`) are interpreted below, so `new(;)`'s own body can reference `.tag`. This is a completely separate binding path from the call's own arguments — member values never get forwarded into `new`'s params.
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

			func_new = instance[:new]
			if func_new
				interp_func_body func_new, expr
			elsif expr.arguments.count > 0
				# No initializer was declared so we have nowhere to pass the arguments
				raise Lost::Arguments_Given_But_Not_Expected.new(expr)
			end

			instance.delete :new
			instance
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
			func                 = Lost::Func.new expr.lexeme
			func.name            = expr.lexeme
			func.enclosing_scope = stack.last
			func.expressions     = expr.expressions
			func.parameters      = expr.parameters
			param_types          = expr.parameters.map do |p|
				p.type&.value
			end
			func.func_signature  = Lost::Func_Signature.new(param_types, expr.type&.value)

			if func.name&.value
				stack.last.declare func.name.value, func

				track_static_declaration stack.last, expr.name
			end

			func
		end

		def interp_func_body func, expr, arg_values: nil
			# A bare Capitalized/UPPERCASE param (`f ( ABC; ABC )`) parses as a signature-literal-style bare type (`param.type` set, `param.name` left nil, see #parse_func) rather than a named param -- real function params always start lowercase. Every other param-binding path below assumes `.name` is always present, so this is checked once, up front, with a real error instead of a raw NoMethodError the first time something reads `param.name.value`.
			nameless_param = func.parameters.find { |param| param.name.nil? }
			raise Lost::Invalid_Parameter_Name.new(expr, nameless_param.type.value) if nameless_param

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
						raise Lost::Positional_Argument_After_Named.new(expr)
					end

					if kind == :named
						seen_named = true
						raise Lost::Duplicate_Named_Argument.new(expr, name_or_label) if named_args.key? name_or_label
						named_args[name_or_label] = interpret value_expr
					else
						arg_labels << (kind == :labeled ? name_or_label : nil)
						positional << interpret(value_expr)
					end
				end

				positional
			end

			# note: `func` is the single, shared Func object registered when the function was declared. Pushing it directly as the call frame (as this used to do) meant every invocation declared its params onto that same shared object, so recursive/repeated calls stomped on each other's param values. Each call gets its own fresh scope instead.
			call_scope                 = Lost::Func.new func.name
			call_scope.expressions     = func.expressions
			call_scope.parameters      = func.parameters
			call_scope.enclosing_scope = func.enclosing_scope
			call_scope.arguments       = arg_values

			# Push type scope if calling an instance method (instance methods need access to type-level declarations)
			# Also push the type's enclosing_scope so sibling types can be found
			if func.enclosing_scope.is_a?(Lost::Instance) && func.enclosing_scope.enclosing_scope
				type = func.enclosing_scope.enclosing_scope
				push_scope type.enclosing_scope if type.enclosing_scope # Push the Type's enclosing scope
				push_scope type # Push the Type
			end
			push_scope func.enclosing_scope
			push_scope call_scope

			# Validated up front, before binding, so a typo'd name reports as "not a declared parameter" rather than getting masked by whatever other param that typo incidentally starved of a value (a confusing Missing_Argument with no mention of the real mistake).
			unless named_args.empty?
				declared_names = func.parameters.map { |param| param.name.value }
				unknown_name   = named_args.keys.find { |name| !declared_names.include? name }
				raise Lost::Unknown_Named_Argument.new(expr, unknown_name) if unknown_name
			end

			if func.parameters.empty? && arg_values.any?
				raise Lost::Arguments_Given_But_Not_Expected.new(expr)
			end

			func.parameters.each_with_index do |param, i|
				name_key       = param.name.value
				has_positional = i < arg_values.length
				has_named      = named_args.key? name_key

				if has_positional && has_named
					raise Lost::Argument_Given_By_Name_And_Position.new(expr, name_key)
				end

				value = if has_named
					named_args.delete name_key
				elsif has_positional
					arg_values[i]
				elsif param.default
					interpret param.default
				else
					raise Lost::Missing_Argument.new(expr)
				end

				# Labels are positional, not a lookup key -- a labeled argument at position `i` must match that position's declared label (Swift/ObjC-style), never used to reorder arguments. A bare, unlabeled argument is always accepted regardless of whether the param declares a label -- labels are opt-in at the call site, not mandatory. Named arguments bypass label-checking entirely -- they're matched by declared name, not position, so there's no positional label to compare against.
				supplied_label = arg_labels[i]
				if !has_named && supplied_label && supplied_label != param.label&.value
					raise Lost::Argument_Label_Mismatch.new(expr, param.label&.value, supplied_label)
				end

				check_struct_type_contract param, value, expr if param.type_struct

				stack.last.declare param.name.value, value

				if value.is_a? Lost::Type
					if param.respond_to?(:add_to_readable) && param.add_to_readable
						call_scope.add_readable_scope value
					elsif param.respond_to?(:add_to_readable) && param.add_to_writable
						call_scope.add_writable_scope value
					end
				end

			end

			body = call_scope.expressions
			if call_scope.name == 'assert'
				raise Lost::Assert_Triggered.new(expr) unless interpret(body.first) == true # Just to be explicit.
			end

			result = nil
			body.compact.each do |e|
				result = interpret e
				break if result.is_a? Lost::Return
			end

			Lost.assert pop_scope == call_scope
			Lost.assert pop_scope == func.enclosing_scope

			if func.enclosing_scope.is_a?(Lost::Instance) && func.enclosing_scope.enclosing_scope
				type = func.enclosing_scope.enclosing_scope
				Lost.assert pop_scope == type
				pop_scope if type.enclosing_scope # Pop the Type's enclosing scope
			end

			return_value = result.is_a?(Lost::Return) ? result.value : result

			if func.func_signature.return_type
				# Compositional, not exact-name -- a `-> Table` returning a `Task`-composed value is a safe covariant return.
				actual_type = type_name_to_string return_value
				unless composed_types_for(return_value).include? func.func_signature.return_type
					raise Lost::Type_Contract_Violation.new(expr, func.func_signature.return_type, actual_type)
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
			if arg.is_a?(Lost::Infix_Expr) && arg.operator&.value == ':=' && arg.left.is_a?(Lost::Identifier_Expr)
				[:named, arg.left.value, arg.right]
			elsif arg.is_a?(Lost::Infix_Expr) && arg.operator&.value == ':' && arg.left.is_a?(Lost::Identifier_Expr)
				[:labeled, arg.left.value, arg.right]
			else
				[:positional, nil, arg]
			end
		end

		# `<name: String, age: Number>` alone is a structure-only (each named member's declared type, no real data yet; see #interp_struct). `()` is how you turn that struct into an actual instance: the call's own arguments become each member's real value, positionally, same order as declared. Goes through #build_struct like every other struct construction so a declared `Struct` type's own body/methods still run.
		#
		# @param struct [Lost::Struct]
		# @param expr [Lost::Call_Expr]
		def interp_struct_call struct, expr
			values   = expr.arguments.map { |arg| wrap_string_literal_value(arg, interpret(arg)) }
			instance = build_struct struct.names, struct.type_names, struct.type_objects, values

			# #build_struct always links a fresh instance's `.types` to the shared, declared `Struct` type alone (`struct_type.types`, generically `['Struct']`) -- if `struct` (the schema being called) is itself named (see #interp_type's bare named struct handling), carry that name over too, own-name-first, so the constructed instance is `Ident | Struct`-shaped, not just generically Struct-shaped: === and a `-> Ident` return-type contract both key off `.types`.
			schema_name = struct.get 'name'
			if schema_name
				instance.declarations['name'] = schema_name
				instance.types                = Set[schema_name] + instance.types
			end

			instance
		end

		# @param expr [Lost::Route_Expr]
		# @return Lost::Route
		def interp_route expr
			func = interpret expr.expression

			route                 = Lost::Route.new
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
				scope.is_a? Lost::Type # note: You could have an instance on the stack, or an empty scope, whatever.
			end
			if enclosing_type
				enclosing_type.routes            ||= {}
				enclosing_type.routes[route_key] = route
			end

			@route_functions_by_route_name[route_key] = route
			stack.last.declare route_key, route

			route
		end

		# @param route [Lost::Route] The route to execute
		# @param req [Lost::Request] Request object to inject
		# @param res [Lost::Response] Response object to inject
		# @param url_params [Hash] Extracted URL parameters (e.g., {"id" => "123"})
		# @param server_instance [Lost::Instance] The server instance (for accessing instance variables)
		# @return The result of handler execution
		def interp_route_body route, req, res, url_params = {}, server_instance: nil
			handler = route.handler
			params  = handler.parameters

			call_scope = Lost::Scope.new "#{handler.name || 'anonymous'}_route"
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
						raise Lost::Route_Param_Expected_But_Not_Found.new(route)
					end

					# Use default value or raise
					if param.default
						value = interpret param.default
					else
						# todo: Is this reachable?
						raise Lost::Missing_Argument.new(expr)
					end
				end

				call_scope.declare param.name.value, value
			end

			body   = handler.expressions
			result = nil

			body.compact.each do |expr|
				# bug todo: Sometimes body contains `nil` when that should never be the case
				result = interpret expr
				break if result.is_a? Lost::Return
			end

			if result.is_a? ::String
				res.declarations['body'] = result
			elsif result.is_a? Lost::Array
				html = ''
				result.values.each do |it|
					if it.is_a? ::String
						html += it
					elsif it.is_a?(Lost::Instance) && it.types.include?('Dom')
						html += render_dom_to_html it
					end
				end
				res.declarations['body'] = html
			elsif result.is_a? Lost::Instance
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
			Lost.assert popped_call == call_scope

			if server_instance
				popped_instance = pop_scope
				Lost.assert popped_instance == server_instance
			end

			popped_enclosing = pop_scope
			Lost.assert popped_enclosing == handler.enclosing_scope

			result
		end

		def interp_statement expr
			instance = Lost::Statement.new expr.expression
			# Capture the scope this literal was built in -- see Lost::Statement's class comment.
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

		# Enforces use_caller_scope/memoize for an already-built Lost::Statement (#interp_call's `Lost::Statement` branch). Immediate `` `expr`() `` and backtick items in percent/array literals never build a real Statement, so they skip this entirely.
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

		# @param expr [Lost::Fence_Expr]
		def interp_fence expr
			# `expr.value` is the fence's body wrapped in a String_Expr, not yet interpreted -- passing
			# it straight to Lost::Fence.new (as this used to) stored the raw AST node as the fence's
			# own value, so `@puts`ing a fence printed an object dump instead of its text. Interpret it
			# first, same as any other String_Expr, to get the real Ruby string.
			#
			# `Fence | String {}` (lost/fence.tape, loaded by lost/preload.tape) is the real declared
			# Lost-level type for this -- link to it, not 'String' directly, mirroring Lost::Fence <
			# Lost::String on the Ruby side. Without linking to *some* declared type here, #stringify_
			# for_display's `to_s`/`pretty_print` lookup finds nothing and falls back to returning the
			# raw Ruby instance, which is what was actually causing the object dump -- not just the
			# un-interpreted value fixed above.
			finish_intrinsic_instance Lost::Fence.new(interpret(expr.value)), 'Fence' # note: Lost::Fence extends Lost::String
		end

		# @param expr [Lost::Html_Fence_Expr]
		def interp_html_fence expr
			interp_string expr.body
		end

		def interp_composition expr
			# These are interpreted sequentially, so there are no precedence rules. I think that'll be better in the long term because there's no magic behind their evaluation. You can ensure the correct outcome by using these operators to form the types you need.

			right      = maybe_instance interpret expr.identifier
			unless right.is_a? Lost::Scope
				raise Lost::Invalid_Composition_With_A_Non_Scope_type.new(right)
			end
			curr_scope = stack.last

			case expr.operator.value
			when '|'
				# Union with Lost::Type

				right.declarations.each do |key, value|
					curr_scope[key] = value unless curr_scope.has?(key)
				end

				curr_scope.static_declarations ||= Set.new
				curr_scope.static_declarations.merge right.static_declarations

				curr_scope.types ||= []
				curr_scope.types += right.types
				curr_scope.types = curr_scope.types.uniq
			when '~'
				# Removal of Lost::Type

				operand_keys_to_remove = right.declarations.keys

				# Maybe I'll have other keys to protect in the future.
				operand_keys_to_remove.reject! do |key|
					key.to_s == 'new'
				end

				operand_keys_to_remove.each do |key|
					curr_scope.delete key
				end

				curr_scope.static_declarations.subtract right.static_declarations

				curr_scope.types = curr_scope.types.reject do |type|
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
					curr_scope[key] = right[key]
				end
			else
				raise Lost::Invalid_Composition_Operator.new(expr)
			end
		end

		# @param for_loop_expr [Lost::For_Loop_Expr]
		def interp_for_loop for_loop_expr
			collection = interpret for_loop_expr.collection
			stride     = interpret(for_loop_expr.stride) if for_loop_expr.stride

			Lost.assert stride.nil? || stride.is_a?(Integer), "Stride must be an integer" if stride

			loop_type = for_loop_expr.type&.value || 'each' # one of Lost::FOR_VERBS
			result    = nil

			values = case collection

			when Lost::Dictionary
				collection.hash
			when Lost::Array
				collection.values

			when Lost::Range
				collection
			when Lost::String
				collection.value.chars

			when Lost::Struct
				# `.members` (an `Lost::Array` of `Lost::Member`) is only populated when the opt-in `lost/struct.tape` layer is loaded (see #build_struct) -- a bare Struct with no matching declared `Struct` type has nothing to iterate.
				collection.declarations['members']&.values || []

			else
				collection # todo; This could be a number, and every other object in the language.
			end

			# New for-loop verbs, to be handled with stride and without
			#
			#   for <collection> [verb: map/select/reject] [by <stride>]
			#   end
			#
			# Each iteration gets its own fresh Scope (rather than one shared/mutated `scope` for
			# the whole loop, as this used to do) -- a closure built inside the body (e.g. a
			# Statement literal capturing `it`) must keep that iteration's own value, not a scope
			# later iterations go on to overwrite. See todos.md [BUGS] for the repro this fixes.
			# note; Pushes/pops by hand (not #push_then_pop) because `return` inside a for-loop body
			# throws :stop past this per-iteration scope on its way out to the outer `catch :stop`
			# below -- #push_then_pop has no `ensure`, so its own pop_scope would never run once
			# the scope moved from wrapping the whole loop (old behavior) to wrapping just one
			# iteration (see the comment above). The `ensure` here keeps the stack balanced
			# regardless of how this iteration's scope gets exited.
			iterate_body = -> (element, index) do
				body_result = nil
				scope       = Scope.new('for_loop')
				push_scope scope
				begin
					scope.declare 'it', element
					scope.declare 'at', index
					if collection.is_a? Lost::Dictionary
						scope.declare 'value', element
						scope.declare 'key', index
					end
					catch :skip do
						for_loop_expr.body.each do |e|
							body_result = interpret e
							throw(:stop, body_result) if body_result.is_a? Lost::Return
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
			elements  = if stride && !collection.is_a?(Lost::Dictionary)
				# `each_slice` yields raw Ruby Arrays -- wrap each chunk as a real Lost::Array so `it` behaves like any other Lost value (`==`, `.push`, etc.), not just dot-index access (`it.0`), which already worked because #interp_dot_infix calls #maybe_instance on its receiver regardless.
				values.each_slice(stride).map { |chunk| Lost::Array.new(chunk) }.each_with_index
			else
				values.each_with_index
			end

			stop_value = catch :stop do
				elements.each do |element, index|
					if collection.is_a? Lost::Dictionary
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
				result = Lost::Array.new(collected)
			when 'count'
				result = count_val
			end

			result     = stop_value if stop_value.is_a? Lost::Return

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

				if expr.when_false.is_a? Lost::Conditional_Expr
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

				if body.is_a? Lost::Conditional_Expr
					interp_conditional body
				else
					body.each.inject(nil) do |result, expr|
						interpret expr
					end
				end
			end
		end

		def interp_directive expr
			case expr.name.value
			when 'declare' # ident: String, value, type
				interpreted_expr = interpret expr.expression
				if interpreted_expr.is_a? Lost::Struct
					interpreted_expr.members.values.each do |member|
						next unless member.name
						stack.last.declare member.name, member.value, member.type
					end
					return interpreted_expr
				end

				data = (expr.arguments || []).map { |arg| interpret arg }

				case data.count
				when 1
					# name
					stack.last.declare data[0], nil
				when 2
					# name, value
					stack.last.declare data[0], data[1]
				when 3
					# name, value, type
					stack.last.declare data[0], data[1], data[2]
				else
					raise Lost::Invalid_Directive_Usage.new(expr)
				end
			when 'puts'
				value = expr.expression ? interpret(expr.expression) : nil
				# Wrapping here (not generally) is what lets @puts reflect the argument's own quote char when it's a literal (see #wrap_string_literal_value) -- a plain variable/expression has no quotation_style to reflect, so it prints unquoted same as before.
				value = wrap_string_literal_value(expr.expression, value) if expr.expression
				puts stringify_for_display(value, show_quotes: true) # note: Don't remove this like I did, it is supposed to print out. todo: Be able to set your own output stream
				value
			when 'assert'
				condition = interpret expr.expression
				unless truthy? condition
					message = interpret expr.message if expr.message
					raise Lost::Assert_Triggered.new(expr, message)
				end
				condition

			when 'refute'
				condition = interpret expr.expression
				if truthy? condition
					message = interpret expr.message if expr.message
					raise Lost::Refute_Triggered.new(expr, message)
				end
				condition

			when 'ruby'
				# The @ruby directive evaluates to the result of calling the ruby Ruby method
				func_scope = stack.last
				unless func_scope.is_a? Lost::Func
					raise Lost::Invalid_Ruby_Proxy_Directive_Usage.new func_scope
				end

				func_name        = func_scope.name
				proxy_method     = "proxy_#{func_name.value}"
				instance_or_type = func_scope.enclosing_scope # An instance or type that should have the ruby method declared

				# note: For static proxies on Types (like Record.find), create a temporary instance of the Ruby class. This allows the proxy method to access the Type's declarations.
				target = if instance_or_type.instance_of?(Lost::Type) && instance_or_type.name
					ruby_class = find_ruby_class_for_type instance_or_type
					if ruby_class
						temp_instance              = ruby_class.new instance_or_type.name
						temp_instance.declarations = instance_or_type.declarations
						# todo: Do static_declarations need to be copied over?
						temp_instance
					else
						instance_or_type
					end
				else
					instance_or_type
				end

				unless target.respond_to? proxy_method
					raise Lost::Missing_Ruby_Proxy_Declaration.new expr
				end

				result = target.send proxy_method, *func_scope.arguments

				# Auto-link instances created by proxy methods to their global types
				if result.is_a?(Lost::Instance) && result.enclosing_scope.nil?
					type_name = result.class.name.split('::').last
					link_instance_to_type result, type_name
				end

				result

			when 'start_server'
				server = interpret expr.expression
				unless server.is_a? Lost::Instance
					raise Lost::Invalid_Start_Directive_Argument.new(expr)
				end

				server.port   = Integer(server.get(:port) || Lost::Server::DEFAULT_PORT)
				server.routes = collect_routes_from_instance server
				servers << server

				start_server server # sets server thread, webrick server, etc
				server

			when 'stop_server'
				server = interpret expr.expression
				unless server.is_a? Lost::Instance
					raise Lost::Invalid_Start_Directive_Argument.new(expr)
				end

				stop_server server
				server

			when 'connect'
				database = interpret expr.expression
				database.create_connection!
				database

			when 'push_scope'
				# Target must be a bare identifier naming something already bound -- a literal or constructor call builds a fresh object every evaluation, so #pop_scope's identity assert could never match it later (Scope#get returns the same object for repeat lookups of an existing Type/Instance).
				raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless expr.expression.is_a?(Lost::Identifier_Expr)

				if target = maybe_instance(interpret expr.expression)
					# Only Type/Instance makes sense to reopen -- a Func is duped on every lookup (#interp_identifier's enclosing_scope rebind), so it could never satisfy the identity check either.
					raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless target.is_a?(Lost::Type)
					push_scope target
				else
					raise Lost::Invalid_Directive_Usage.new(expr)
				end

			when 'pop_scope'
				raise Lost::Invalid_Directive_Usage.new(expr) unless expr.expression
				raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless expr.expression.is_a?(Lost::Identifier_Expr)

				scope_to_pop = maybe_instance interpret expr.expression
				raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless scope_to_pop.is_a?(Lost::Type)

				# note; these are by identity, so you cannot interchange an instance of a type and a reference to its type. push 1 cannot pair with pop Number
				Lost.assert pop_scope == scope_to_pop
				scope_to_pop

			when 'add_readable_scope', 'add_readable', 'readable'
				target = maybe_instance interpret(expr.expression)
				if target
					raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless target.is_a?(Lost::Scope)
					stack.last.add_readable_scope target
				else
					raise Lost::Invalid_Directive_Usage.new(expr)
				end

			when 'add_writable_scope', 'add_writable', 'writable'
				target = maybe_instance interpret(expr.expression)
				if target
					raise Lost::Invalid_Scope_Directive_Argument.new(expr.expression) unless target.is_a?(Lost::Scope)
					stack.last.add_writable_scope target
				else
					raise Lost::Invalid_Directive_Usage.new(expr)
				end

			when 'remove_readable_scope', 'remove_readable'
				raise Lost::Invalid_Directive_Usage.new(expr) unless expr.expression
				scope_to_remove = maybe_instance interpret expr.expression

				stack.last.remove_readable_scope scope_to_remove
				scope_to_remove

			when 'remove_writable_scope', 'remove_writable'
				raise Lost::Invalid_Directive_Usage.new(expr) unless expr.expression
				scope_to_remove = maybe_instance interpret expr.expression

				stack.last.remove_writable_scope scope_to_remove
				scope_to_remove

			when 'sleep' # @sleep <seconds>
				sleep interpret expr.expression

			when 'load'
				# note: #load_file_into_scope returns the output but it's ignored. Assigning the value of a @load directive executes code in #interp_infix_expr
				# Standalone load is interpreted into current scope by passing the scope into runtime#load_file
				filepath = interpret expr.expression
				load_file_into_scope filepath, stack.last

			else
				raise Lost::Invalid_Directive_Usage.new(expr)
			end
		end

		def interp_subscript expr
			if expr.expression.expressions.count > 1
				raise Lost::Too_Many_Subscript_Expressions.new(expr.expression)
			end

			receiver = maybe_instance interpret expr.receiver

			case receiver
			when Lost::Dictionary, Lost::Array
				key = interpret expr.expression.expressions.first
				receiver.proxy_get key
			when Lost::Nil
				# todo: What should happen when subscripting nil? A warning of some kind maybe?
				nil
			when Lost::String
				index = interpret expr.expression.expressions.first
				receiver.value[index]
			else
				raise Lost::Invalid_Subscript_Receiver.new(expr.receiver)
			end
		end

		# `Key_Type [ PRIMARY, ]` declares `Key_Type` in the current scope, same as a Type/Struct declaration does -- unlike a nested enum member (`build_enum`, called directly, skips this), which is only ever reachable through its parent (`Outer.Nested`), not the enclosing scope.
		def interp_enum expr
			instance = build_enum expr
			stack.last.declare expr.name.value, instance
			instance
		end

		# Builds (but doesn't declare) a real Lost::Enum for an Enum_Expr -- shared by #interp_enum and nested enum members (#build_enum_member).
		def build_enum expr
			# Named at construction, not via `.name =` after -- a later attr write never touches @declarations.
			instance = Lost::Enum.new expr.name.value
			link_instance_to_type instance, 'Enum'

			# Skips normal Type-construction, so Enum's own Lost-level body (keys/values/types/count, @operator ==) is run by hand.
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

			instance.declarations['type']   = expr.type ? find_in_stack(expr.type.value) : nil
			instance.declarations['keys']   = wrap_lost_array keys
			instance.declarations['values'] = wrap_lost_array values
			instance.declarations['types']  = wrap_lost_array types
			instance.declarations['count']  = keys.length

			instance
		end

		# Links a raw Lost::Array to the real Array type so its own Lost-level methods (to_s(;), etc.) are reachable. Used by #build_enum and #build_instance_of_type.
		def wrap_lost_array list
			array = Lost::Array.new list
			link_instance_to_type array, 'Array'
			array
		end

		# Returns [name, value, type] for one enum member, per #parse_enum_expr's five member forms (see CLAUDE.md). Bare/typed-only members get a Symbol matching their own name; `:=`/`: Type =` members use their real value; nested enums recurse into #build_enum.
		def build_enum_member member_expr
			case member_expr
			when Lost::Enum_Expr
				[member_expr.name.value, build_enum(member_expr), nil]
			when Lost::Nil_Init_Expr
				name = member_expr.left.value
				[name, name.to_sym, nil]
			when Lost::Identifier_Expr
				name        = member_expr.value
				member_type = member_expr.type ? find_in_stack(member_expr.type.value) : nil
				[name, name.to_sym, member_type]
			when Lost::Infix_Expr
				name        = member_expr.left.value
				member_type = member_expr.left.type ? find_in_stack(member_expr.left.type.value) : nil
				[name, interpret(member_expr.right), member_type]
			end
		end

		# Resolves a `: Type` annotation's value, honoring a trailing `\<...>`/`\Name` tag (`id: Array\String`) if one was parsed onto it. `type_expr` is an Identifier_Expr, not a Type_Expr (see #parse_identifier_expr), so a tagged annotation is resolved through a synthetic Type_Expr reference instead of #interpret directly -- same trick #interp_func_body etc. use to reuse existing dispatch via a synthetic Call_Expr.
		def interp_type_annotation type_expr
			return interpret type_expr unless type_expr.type_struct

			reference      = Lost::Type_Expr.new
			reference.name = type_expr.value
			reference.tag  = type_expr.type_struct
			interp_type reference
		end

		def interp_struct expr, allow_spread: true
			types         = [] # per-member type object (or the raw value itself for unnamed members)
			values        = [] # per-member real value, nil when a named member has none
			names         = []
			single_member = allow_spread && expr.types.length == 1 # only a lone unnamed member spreads -- see below

			expr.types.each_with_index do |member, i|
				if expr.names[i]
					# note; Named member (e.g. `some_string: String`), the member's own identifier (`some_string`) is just a label, not something to look up; resolve its declared type instead. Named members are never spread: the name is always its namespace (`.tag.columns`), even when the value is itself a Struct.
					if member.type
						# `member.type` is already a full Identifier_Expr (#parse_identifier_expr's `: Type` recurses), not a bare Lexeme -- directly interpretable, no rewrapping needed. A trailing `\<...>`/`\Name` on that annotation (`id: Array\String`) only ever populates `.type_struct` there (see #parse_identifier_expr), not a real `Type_Expr` -- a plain #interpret would silently resolve the untagged base type, so route through #interp_type_annotation instead.
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
						types << find_in_stack(type_name_to_string(default_value))
						values << wrap_string_literal_value(member.member_default, default_value)
					end
					names << expr.names[i]
				else
					value = interpret member

					if single_member && value.is_a?(Lost::Struct)
						types.concat value.type_objects
						values.concat value.values
						names.concat value.names
					else
						types << value
						# A bare Type used as the member itself (`<Number>`, schema-only, no real data yet) isn't a value -- push nil, same as a named member's own `: Type` annotation with no default does, rather than the Type object itself (which used to leak into display code expecting a real value or nil).
						values << (value.is_a?(Lost::Type) && !value.is_a?(Lost::Instance) ? nil : wrap_string_literal_value(member, value))
						names << nil
					end
				end
			end

			# Each member's "type" here is just its value's own inferred type name
			type_names = types.map { |value| type_name_to_string value }
			struct     = build_struct names, type_names, types, values

			# A leading TYPE_IDENTIFIER before `<...>` (`Task <id: Number, done: Bool>`) makes `expr.name` a raw Lexeme -- a Bare Named Struct (see CLAUDE.md), registered globally here. `\<...>`'s inline-literal form sets `.tag.name` to a plain String instead, so it never re-triggers this.
			return register_bare_named_struct(expr, struct) if expr.name.is_a? Lost::Lexeme

			struct
		end

		# Registers (or idempotently confirms) a Bare Named Struct under its own name. Redeclaring the identical shape is a no-op; anything else already bound under that name raises rather than silently clobbering it.
		def register_bare_named_struct expr, struct
			name     = expr.name.value
			existing = find_in_stack name

			if existing.is_a?(Lost::Struct) && existing.get('name') == name && existing.structure_declaration_equal?(struct)
				return existing
			end

			# A tagged Type declaration never registers under the plain identifier namespace (only in `tagged_type_variants`), so `find_in_stack` alone can't see a conflicting one -- check both.
			if existing.nil? && tagged_variants_for(name).empty?
				struct.declare 'name', name
				struct.types = Set[name] + struct.types
				stack.last.declare name, struct if struct.names.all?
				return struct
			end

			raise Lost::Undeclared_Tagged_Type.new(expr)
		end

		# A value built directly from a string literal gets wrapped into a real Lost::String carrying the literal's own `quotation_style`, instead of staying the bare Ruby string #interp_string normally returns. Struct/Member's to_s(;) (lost/member.tape) and Array/Dictionary/Tuple's to_s(;) (lost/array.tape, lost/dictionary.tape, lost/preload.tape) read `.quotation_style` straight off the value to decide how to quote it for display.
		def wrap_string_literal_value source_expr, value
			return value unless source_expr.is_a?(Lost::String_Expr) && value.is_a?(::String)
			finish_intrinsic_instance Lost::String.new(value, source_expr.quotation_style), 'String'
		end

		# The low-level Lost::Struct object is always built first and exactly the same way regardless of `struct_type` -- it's what #type_objects/etc. read from, and every existing member-matching call site depends on it being real.
		def build_struct names, type_names, types, values
			struct_type = find_in_stack 'Struct'
			struct      = Lost::Struct.new names, type_names, types, values

			unless struct_type.is_a?(Lost::Type)
				link_instance_to_type struct, 'Struct'
				return struct
			end

			struct.name            = struct_type.name
			struct.types           = struct_type.types
			struct.enclosing_scope = struct_type
			run_type_body_on_instance struct_type, struct

			zipped = %w(names type_names types values).zip [names, type_names, types, values]
			zipped.each do |key, list|
				array = Lost::Array.new list
				link_instance_to_type array, 'Array'
				struct.declarations[key] = array
			end

			member_type = find_in_stack 'Member'
			if member_type.is_a?(Lost::Type) && struct.has?('members')
				members = names.each_index.map do |i|
					member_display_type = names[i] ? types[i] : find_in_stack(type_names[i])
					member              = Lost::Member.new names[i], member_display_type, values[i]
					link_instance_to_type member, 'Member'
					member
				end

				members_array = Lost::Array.new members
				link_instance_to_type members_array, 'Array'
				struct.members                 = members_array
				struct.declarations['members'] = members_array
			end

			struct
		end

		# @param expr [Lost::Operator_Overload_Expr]
		def interp_operator_overload expr
			# expr attrs:  func_expr(Func_Expr)  fixity(Lexeme)  precedence(Int)  value(String)
			# This is setting up operators to be treated as regular functions, whose identifier is its operator symbols without spaces.

			stack.last.declare expr.value, interpret(expr.func_expr)
		end

		# note: This is the entry point for all expressions. This is called in a loop until all expressions are evaluated, or the program crashes.
		def interpret expr
			case expr
			when Lost::Number_Expr, Lost::Symbol_Expr
				expr.value

			when Lost::Identifier_Expr
				interp_identifier expr

			when Lost::String_Expr
				interp_string expr

			when Lost::Type_Expr
				interp_type expr

			when Lost::Route_Expr
				interp_route expr

			when Lost::Func_Expr
				interp_func expr

			when Lost::Func_Signature_Expr
				interp_func_signature expr

			when Lost::Composition_Expr
				interp_composition expr

			when Lost::Prefix_Expr
				interp_prefix expr

			when Lost::Nil_Init_Expr
				# This is a special infix expression `<ident>,` that desugars to `ident = ident or nil`. left is assigned nil if it doesn't exist, or is returned if it does
				interp_nil_init expr

			when Lost::Infix_Expr
				interp_infix expr

			when Lost::Postfix_Expr
				interp_postfix expr

			when Lost::Percent_Literal_Expr
				interp_percent_literal expr

			when Lost::Circumfix_Expr
				interp_circumfix expr

			when Lost::Call_Expr
				interp_call expr

			when Lost::For_Loop_Expr
				interp_for_loop expr

			when Lost::Conditional_Expr
				interp_conditional expr

			when Lost::Array_Index_Expr
				maybe_instance expr.indices_in_order

			when Lost::Subscript_Expr
				interp_subscript expr

			when Lost::Directive_Expr
				interp_directive expr

			when Lost::Statement_Expr
				interp_statement expr

			when Lost::Fence_Expr
				interp_fence expr

			when Lost::Html_Fence_Expr
				interp_html_fence expr

			when Lost::Comment_Expr
				expr.value

			when Lost::Operator_Overload_Expr
				interp_operator_overload expr

			when Lost::Operator_Expr
				case expr.value
				when 'skip'
					throw :skip
				when 'stop'
					throw :stop
				end

			when Lost::Struct_Expr
				interp_struct expr

			when Lost::Enum_Expr
				interp_enum expr

			when nil
				maybe_instance nil

			else
				raise Lost::Interpret_Expr_Not_Implemented.new(expr)
			end
		end
	end
end
