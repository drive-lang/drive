module Disk
	class Scope
		attr_accessor :enclosing_scope, :readable_scopes, :writable_scopes, :declarations, :name, :type_by_identifier, :static_declarations, :tagged_type_variants, :context, :display_name

		# {filepath => result} for every @load run in this scope, and only this scope -- keyed by resolved filepath so a second @load of the same file into the same scope skips re-running it (see #load_file_into_scope) but still returns the same result the first run produced, rather than nil. Does not recurse into the stack, though that may be useful later on.
		attr_accessor :loaded_filepaths

		def initialize name = nil
			@name               = name
			@declarations       = {}
			@type_by_identifier = {}
			# WeakMaps, not Sets: membership here must not keep an instance alive on its own -- otherwise @splat/@splatr (and the param shorthand) would pin whatever's added for as long as the *containing* scope lives, even after every other reference to it is gone. Storing each entry as its own key AND value (wm[x] = x) is just how you use a WeakMap as a weak set -- there's no dedicated weak-Set in the stdlib.
			# Insertion order still matters here (most-recently-added wins on a name collision, like a stack -- see test_multiple_unpacks), so lookups below deliberately reverse .keys before searching. Ruby doesn't document WeakMap's iteration order the way it does Hash/Set's, but it matches insertion order in every version this has been tested against.
			@readable_scopes     = ObjectSpace::WeakMap.new
			@writable_scopes     = ObjectSpace::WeakMap.new
			@loaded_filepaths    = {}
			@static_declarations = ::Set.new
			# `Type\Struct { }` declarations of the same base name (e.g. every tagged variant of "String") are kept here, separate from @declarations -- see #Interpreter#interp_tagged_type_declaration/#find_tagged_type_variant. A base name maps to every variant declared under it in this scope; matching is by real structure equality (names + types), not a mangled string key.
			@tagged_type_variants = Hash.new { |h, k| h[k] = [] }
		end

		def declare identifier, value, type = nil
			self[identifier]                = value
			@type_by_identifier[identifier] = type if type
			value
		end

		# todo: Currently there is no clear rule on multiple unpacks. :double_unpack
		# note; Lookup order goes @declarations, @writable_scopes, @readable_scopes
		def get key
			key_str = key&.to_s

			return @declarations[key_str] if @declarations.key?(key_str) # note; calling #key? on @declarations here because I specifically want to see if this key is on @declarations.

			scope = @writable_scopes.keys.reverse_each.find { it.has? key_str }
			return scope[key_str] if scope

			scope = @readable_scopes.keys.reverse_each.find { it.has? key_str }
			return scope[key_str] if scope

			nil
		end

		def []= key, value
			key_str = key&.to_s

			return @declarations[key_str] = value if @declarations.key?(key_str)

			existing_writable = @writable_scopes.keys.reverse_each.find { it.has? key_str }
			return existing_writable.declarations[key_str] = value if existing_writable

			@declarations[key_str] = value
		end

		def [] key
			get key
		end

		def is compare
			@name == compare
		end

		# todo: Currently there is no clear rule on multiple unpacks. :double_unpack
		def has? identifier
			id_str = identifier.to_s

			return true if @writable_scopes.keys.any? do |sibling|
				sibling.has? id_str
			end

			return true if @readable_scopes.keys.any? do |sibling|
				sibling.has? id_str
			end

			@declarations.key?(id_str) || @static_declarations.include?(id_str)
		end

		def delete key
			return nil unless key
			key_str = key&.to_s

			return @declarations.delete(key_str) if @declarations.key?(key_str)

			existing_writable = @writable_scopes.keys.reverse_each.find { it.has? key_str }
			return existing_writable.declarations.delete(key_str) if existing_writable

			@declarations.delete key_str
		end

		def add_readable_scope scope
			return nil unless scope # todo; should this be an error?

			@readable_scopes[scope] = scope
		end

		def add_writable_scope scope
			return nil unless scope

			@writable_scopes[scope] = scope
		end

		def remove_readable_scope scope
			@readable_scopes.delete scope
		end

		def remove_writable_scope scope
			@writable_scopes.delete scope
		end

		def inspect
			filtered = instance_variables.reject { |v| v == :@enclosing_scope }
			vars     = filtered.map { |v| "#{v}=#{instance_variable_get(v)}" }
			"#<#{self.class.name} #{vars.join(', ')}>"
		end

		def to_s
			"#<#{self.class.name} name=#{@name.inspect} declarations=#{@declarations.keys.inspect}>"
		end
	end

	class Global < Scope
		def initialize
			super 'Global'
		end
	end

	class Temporary < Scope
	end

	class Type < Scope
		attr_accessor :expressions, :types, :routes
		attr_accessor :tag_instance
		attr_accessor :tag_declaration
		attr_accessor :declaration_in_progress

		def initialize name = nil
			super name
			@types = ::Set[name]
			# `name` is `@`-only (`@.name` / `Type.@name`) -- the Ruby-level `Scope#name` attr is the
			# store, read live by Context#proxy_name. Not in @declarations, not a static.
			# `@.display_name` -- same as name until a tag makes the real display richer (see #declare_tag).
			@display_name            = name
			@declaration_in_progress = false
		end
	end

	class Instance < Type
		def initialize name = 'Instance'
			super name
		end

		# This is mostly for Array and Dictionary, so we can automatically forward [] and []= to the correct storage location. Their proxy_delegate is the object that ruby_proxies uses to forward calls to already anyway
		def []= key, value
			delegate_name = self.class.respond_to?(:proxy_delegate_name) && self.class.proxy_delegate_name

			if delegate_name && key.to_s == delegate_name
				delegate_value = value.respond_to?(key) ? value.send(key) : value
				send "#{key}=", delegate_value
				# Read back what the setter actually stored, not the raw input -- a subclass setter may
				# coerce (Disk::Integer#value= runs to_i, Disk::Decimal#value= builds a BigDecimal).
				@declarations[key.to_s] = send key
			else
				super
			end
		end
	end

	class Func < Scope
		attr_accessor :expressions, :parameters, :arguments, :func_signature
		# Set (to the member name) on a synthesized Context function -- Interpreter#interp_call routes
		# it straight to the intrinsic instead of running a body. See #synthesized_context_func.
		attr_accessor :context_function_name, :func_expr
	end

	class Route < Func
		attr_accessor :http_method, :path, :handler, :parts, :param_names
	end

	class Any < Scope
		ANY = new()

		def self.shared
			ANY
		end

		private_class_method :new

		def initialize
			super 'Any'
		end
	end

	class Nil < Instance # Like Ruby's NilClass, this represents the absence of a value. An ordinary instance -- constructible like any other type, so `Nil()` / a tagged `Nil\Error()` work and Drive code can hold its own shared nil.
	end

	class Bool < Instance
		attr_accessor :truthiness

		def !
			!@truthiness
		end

		def self.truthy
			TRUE
		end

		def self.falsy
			FALSE
		end

		# private_class_method :new # prevent external instantiation

		def initialize truthiness = true
			super((!!truthiness).to_s.capitalize) # Scope class only needs @name
			@truthiness                 = !!truthiness
			@declarations['truthiness'] = @truthiness
		end

		TRUE  = new(true)
		FALSE = new(false)
	end

	# Disk::Range is an Instance wrapping a Ruby ::Range -- see drive/backings/range.rb + disks/range.disk.

	class Server < Instance
		DEFAULT_PORT = 8080
		attr_accessor :port, :routes, :webrick_server, :server_thread
	end

	class Request < Scope
		def initialize
			super 'Request'
		end
	end

	class Response < Scope
		attr_accessor :webrick_response

		def proxy_redirect location
			declarations['status']              = 303
			declarations['headers']['Location'] = location
			nil
		end
	end

end
