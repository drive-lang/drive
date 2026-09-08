require 'bigdecimal'

module Tape
	# Base of the numeric family, mirroring Ruby's own `Numeric`. A bare literal never lands here --
	# `#maybe_instance` builds an `Integer` / `Float` / `Decimal` (below) directly off the Ruby value's
	# class. `Number` itself is what those compose, the type an annotation like `x: Number` names, and
	# the receiver every shared method is defined on.
	class Number < Instance
		extend Ruby_Proxies

		# The wrapped Ruby Numeric. `value` mirrors String/Array/Dictionary's own backing accessor.
		attr_reader :value

		def initialize value = 0
			super(self.class.name.split('::').last) # 'Number' / 'Integer' / 'Float' / 'Decimal'
			# #interp_directive builds a throwaway `ruby_class.new(type_name)` to dispatch static
			# proxies (`Integer.rand`) -- ignore the type-name String it hands us.
			self.value = value.is_a?(::Numeric) ? value : 0
		end

		# Also the sync point for a later `self.value = n` from Drive's own `Self(;)` -- that write reaches
		# here through Instance#[]=, since `value` is the proxy_delegate name. Subclasses override to
		# coerce (`Integer` -> `to_i`, etc).
		def value= numeric
			@value                 = numeric
			@declarations['value'] = numeric
		end

		def + other
			value + other.value
		end

		def - other
			value - other.value
		end

		def * other
			value * other.value
		end

		def ** other
			value ** other.value
		end

		def / other
			value / other.value
		end

		def % other
			value % other.value
		end

		def >> other
			value >> other.value
		end

		def << other
			value << other.value
		end

		def ^ other
			value ^ other.value
		end

		def & other
			value & other.value
		end

		def | other
			value | other.value
		end

		proxy_delegate 'value'
		proxy :numerator   # Ruby's own Numeric#numerator -- real parts for a Rational, self/1 otherwise
		proxy :denominator
		proxy :to_s
		proxy :abs
		proxy :floor
		proxy :ceil
		proxy :round
		proxy :even?
		proxy :odd?
		proxy :to_i
		proxy :to_f
		proxy :clamp

		def proxy_sqrt
			Math.sqrt value
		end

		def proxy_rand max
			max_val = max.respond_to?(:value) ? max.value : max.to_i
			::Kernel.rand(max_val + 1)
		end
	end

	# `4` -- backed by a Ruby Integer.
	class Integer < Number
		def value= numeric
			super(numeric.respond_to?(:to_i) ? numeric.to_i : 0)
		end
	end

	# `4.5` -- backed by a Ruby Float.
	class Float < Number
		def value= numeric
			super(numeric.respond_to?(:to_f) ? numeric.to_f : 0.0)
		end
	end

	# `Decimal('1.50')` -- backed by a Ruby BigDecimal. No literal form (Ruby has none either).
	class Decimal < Number
		def value= numeric
			coerced = case numeric
				when ::BigDecimal        then numeric
				when ::Numeric           then BigDecimal(numeric.to_s)
				when ::String            then (BigDecimal(numeric) rescue BigDecimal(0))
				else BigDecimal(0)
				end
			super(coerced)
		end

		# BigDecimal#to_s defaults to engineering notation ('0.15e1'); 'F' gives plain '1.5'.
		def proxy_to_s
			value.to_s('F')
		end
	end
end
