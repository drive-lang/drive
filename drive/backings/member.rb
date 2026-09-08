module Disk
	# name: String
	# type: Any
	# value: Any
	class Member < Instance
		attr_accessor :name, :type, :value

		def initialize name = nil, type = nil, value = nil
			super 'Member'
			@name  = name
			@type  = type
			@value = value

			@declarations['name']  = name
			@declarations['type']  = type
			@declarations['value'] = value
		end
	end
end
