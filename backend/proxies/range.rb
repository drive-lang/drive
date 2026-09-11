module Prog
	class Range < Instance
		extend Ruby_Proxies
		include ::Enumerable
		attr_accessor :range

		def initialize range = nil
			super 'Range'
			@range = range.is_a?(::Range) ? range : (0...0)
		end

		def each &block
			return @range.each unless block
			@range.each(&block)
			self
		end

		def to_a = @range.to_a

		proxy_delegate 'range'
		proxy :begin, as: :start
		proxy :end, as: :finish
		proxy :exclude_end?, as: :excludes_end?
		proxy :size, as: :length
		proxy :size, as: :count
		proxy :min
		proxy :max
		proxy :sum
		proxy :cover?, as: :include? # `covers?` is a prog-level alias (backend/range.prog)

		# A fresh Array of every element.
		def proxy_values
			Prog::Array.new @range.to_a
		end

		def proxy_to_s
			"#{@range.begin}#{@range.exclude_end? ? '..<' : '..'}#{@range.end}"
		end
		alias to_s proxy_to_s

		def == other
			case other
			when Prog::Range then @range == other.range
			when ::Range then @range == other
			else false
			end
		end
	end
end
