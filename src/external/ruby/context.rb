require 'objspace'

module Tape
	class Context < Struct
		attr_accessor :subject

		def initialize subject = nil
			super()
			@name    = 'Context'
			@subject = subject
		end
	end
end
