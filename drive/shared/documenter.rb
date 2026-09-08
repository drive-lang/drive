module Drive
	# A proof of concept to see what a documentation stage might look like
	class Documenter
		include Disk
		attr_accessor :input

		def initialize input
			@input = input
		end

		def output
			input.map do |expr|
				case expr
				when Disk::Comment_Expr
					expr.value
				else
					nil
				end
			end.compact
		end
	end
end
