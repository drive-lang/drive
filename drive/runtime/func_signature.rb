module Tape
	class Func_Signature # Does not need to be a scope
		attr_accessor :param_types, :return_type

		def initialize param_types = [], return_type = nil
			@param_types = param_types
			@return_type = return_type
		end

		# An identifier typed as a signature (`double: (Number -> Number;)`) can only ever be
		# satisfied by a real implementation matching that signature -- never by another bare
		# Func_Signature value, even a structurally identical one. A signature describes a shape a
		# Function must have, not a value in its own right that can stand in for one.
		# @param func [Tape::Func] a real function whose own signature must match this one
		def matches? other
			other.is_a?(Func) && other.func_signature.param_types == param_types && other.func_signature.return_type == return_type
		end

		def to_s
			"(#{param_types.join(',')} -> #{return_type};)"
		end
	end
end
