module Backend
	# A proof of concept to see what a documentation stage might look like
	class Documenter
		include Prog
		attr_accessor :input

		def initialize input
			@input = input
		end

		def output
			input.map do |expr|
				case expr
				when Prog::Comment_Expr
					expr.value
				else
					nil
				end
			end.compact
		end
	end
end
