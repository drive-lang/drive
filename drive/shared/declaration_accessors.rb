# Mixin for Tape::Instance subclasses (external/ruby/*.rb). Forwards unknown method
# calls to @declarations instead of requiring a hand-written getter/setter pair for
# every Drive-declared member. A real method (hand-written, or from a superclass)
# always wins -- method_missing only runs after Ruby fails to find one.
module Declaration_Accessors
	def method_missing name, *args
		key = name.to_s

		if key.end_with? '='
			field = key.delete_suffix '='
			return @declarations[field] = args.first if @declarations.key? field
		elsif @declarations.key? key
			return @declarations[key]
		end

		super
	end

	def respond_to_missing? name, include_private = false
		key = name.to_s.delete_suffix '='
		@declarations.key?(key) || super
	end
end
