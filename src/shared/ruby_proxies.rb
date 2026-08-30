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

	def proxy_delegate_name
		@proxy_delegate_name
	end

	def proxy method_name, as: method_name
		@proxy_methods ||= []
		@proxy_methods << { lost_name: as, ruby_method: method_name }
		define_method "proxy_#{as}" do |*args|
			_proxy_delegate_.send method_name, *args
		end
	end

	# For an Lost method with multiple param-typed declarations (`find_table (struct: Struct;)`, `find_table (name: String;)`) --
	# Lost itself doesn't support overload dispatch (a repeated name just overwrites the earlier declaration), so only declare
	# ONE `find_table (; @ruby)` in the .tape file. This dispatches by the first argument's own Ruby class instead, in mapping
	# order (first match wins, same as a `case`/`when` chain), to the matching Ruby method:
	#
	#   proxy_overload :find_table,
	#       Lost::Struct => :find_table_struct,
	#       Lost::String => :find_table_named
	def proxy_overload method_name, mapping
		define_method "proxy_#{method_name}" do |*args|
			arg     = args.first
			matched = mapping.find { |klass, _| arg.is_a? klass }
			raise "proxy_overload: no match for ##{method_name} with argument of type #{arg.class}" unless matched

			send matched.last, arg
		end
	end
end