module Tape
	Lexeme = ::Struct.new(:type, :value, :reserved, :l0, :c0, :l1, :c1, :source_file, :quotation_style) do
		def == other
			if other.is_a? Lexeme
				value == other.value
			else
				super other
			end
		end

		# Token types whose `.value` is arbitrary literal content (a string's/symbol's/number's own text, a fence block's raw body) rather than real syntax -- that content can coincidentally spell a meaningful punctuation/keyword string (`')'`, `'end'`, `';'`, ...), but a literal can never legitimately BE the delimiter/keyword something is scanning for. Excluded from #is's string-value comparisons below so a `curr?(')')`-style check (used everywhere, chief among many #parse_circumfix_expr's own closing-delimiter loop) can't mistake a literal's content for real syntax.
		LITERAL_TYPES = %i[string symbol number fence html].freeze

		def is compare
			if compare.is_a? Symbol
				compare == type
			elsif compare.is_a? ::String
				!LITERAL_TYPES.include?(type) && compare == value
			elsif compare.is_a? ::Array
				compare.any? do |it|
					if it.is_a? Symbol
						it == type
					else
						!LITERAL_TYPES.include?(type) && it == value
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
