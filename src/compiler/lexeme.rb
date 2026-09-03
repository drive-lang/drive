module Tape
	Lexeme = ::Struct.new(:type, :value, :reserved, :l0, :c0, :l1, :c1, :source_file, :quotation_style) do
		def == other
			if other.is_a? Lexeme
				value == other.value
			else
				super other
			end
		end

		def is compare
			if compare.is_a? Symbol
				compare == type
			elsif compare.is_a? ::String
				compare == value
			elsif compare.is_a? ::Array
				compare.any? do |it|
					if it.is_a? Symbol
						it == type
					else
						it == value
					end
				end
			else
				compare == self
			end
		end

		def isnt compare
			is(compare) == false
		end

		def line_col
			"#{l0}:#{c0}..#{l1}:#{c1}"
		end
	end
end
