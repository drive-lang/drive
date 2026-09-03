module Ruby_Proxies
	def self.extended base
		base.instance_variable_set :@proxy_methods, []
	end

	def proxy_methods
		@proxy_methods ||= []
	end

	def proxy_delegate object_name
		@proxy_delegate_name = object_name.to_s

		define_method "_proxy_delegate_" do |*args|
			send object_name
		end
	end

	# Walks the superclass chain -- `@proxy_delegate_name` is a class-level ivar, so a subclass
	# (Tape::Integer < Tape::Number) doesn't inherit it and would otherwise report nil, breaking
	# Instance#[]='s sync of the delegate member.
	def proxy_delegate_name
		@proxy_delegate_name || (superclass.proxy_delegate_name if superclass.respond_to?(:proxy_delegate_name))
	end

	def proxy method_name, as: method_name
		@proxy_methods ||= []
		@proxy_methods << { tape_name: as, ruby_method: method_name }
		define_method "proxy_#{as}" do |*args|
			_proxy_delegate_.send method_name, *args
		end
	end

	# For an Tape method with multiple param-typed declarations (`find_table (struct: Struct;)`, `find_table (name: String;)`) --
	# Tape itself doesn't support overload dispatch (a repeated name just overwrites the earlier declaration), so only declare
	# ONE `find_table (; @ruby)` in the .tape file. This dispatches by the first argument's own Ruby class instead, in mapping
	# order (first match wins, same as a `case`/`when` chain), to the matching Ruby method:
	#
	#   proxy_overload :find_table,
	#       Tape::Struct => :find_table_struct,
	#       Tape::String => :find_table_named
	def proxy_overload method_name, mapping
		define_method "proxy_#{method_name}" do |*args|
			arg     = args.first
			matched = mapping.find { |klass, _| arg.is_a? klass }
			raise "proxy_overload: no match for ##{method_name} with argument of type #{arg.class}" unless matched

			send matched.last, arg
		end
	end
end
