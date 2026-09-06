module Tape
	class Enum < Instance
		attr_accessor :enum_keys, :enum_values, :enum_types, :enum_type

		def initialize name = 'Enum'
			super name
			@enum_keys   = []
			@enum_values = []
			@enum_types  = []
			@enum_type   = nil
		end
	end
end
