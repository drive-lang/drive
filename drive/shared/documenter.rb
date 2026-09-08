module Drive
	# A proof of concept to see what a documentation stage might look like
	class Documenter
		include Tape
		attr_accessor :input

		def initialize input
			@input = input
		end

		def output
			input.map do |expr|
				case expr
				when Tape::Comment_Expr
					expr.value
				else
					nil
				end
			end.compact
		end
	end
end
