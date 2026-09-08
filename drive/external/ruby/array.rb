module Tape
	# note: Be sure to prefix with Tape:: whenever referencing this Array type to prevent ambiguity with Ruby's ::Array!
	class Array < Instance
		extend Ruby_Proxies
		attr_accessor :values

		def initialize values = []
			super 'Array'
			@values                 = values || []
			@declarations['values'] = @values
			::Array
		end

		proxy_delegate 'values'
		proxy :push
		proxy :pop
		proxy :shift
		proxy :unshift, as: :prepend # tapes/array.tape's `unshift(;)` was renamed to `prepend(;)` (unshift is now just an alias, see #Interpreter#interp_directive's `@ruby` lookup, which resolves by the func's own declared name -- "prepend" -- not whatever alias it was called through)
		proxy :length
		proxy :length, as: :count
		proxy :join
		proxy :empty?
		proxy :index

		def proxy_Self *args
			# `Array(1, 2, 3)` -> those elements; `Array([1, 2, 3])` / `Array(other)` -> a lone
			# collection argument is unwrapped (the historical single-arg contract); `Array(5)` -> `[5]`.
			source =
				if args.length == 1
					case (a = args.first)
					when Tape::Array, Tape::Set then a.values
					when Tape::Range            then a.range.to_a
					when ::Array                then a
					when ::Range                then a.to_a
					else args
					end
				else
					args
				end

			@values                 = source.dup
			@declarations['values'] = @values
			self
		end

		def proxy_new size, value
			@values = ::Array.new(size, value)
			@declarations['values'] = @values
			self
		end

		def proxy_of value,  size
			proxy_new size, value
		end

		# note; To prevent Scope#[] or Scope#get from missing out on the actual location of the array elements. Standard members still call through to [] and get. I'm manually calling these proxy methods in some places.
		def proxy_get index
			values[index]
		end

		def proxy_set index, value
			values[index] = value
		end

		def proxy_random
			values.sample
		end

		def proxy_concat other_array
			values.concat other_array.values
		end

		def proxy_flatten depth = -1
			ruby_array = values.map { |v| v.is_a?(Tape::Array) ? v.values : v }
			Tape::Array.new ruby_array.flatten depth
		end

		def proxy_insert index, *things
			values.insert(index, *things)
			wrap_if_array values
		end

		# first/last/slice can return either a single element or a raw Ruby Array (with a count/range argument) -- only wrap the latter, so `it.first` (no arg) still returns a scalar
		def proxy_first * args
			wrap_if_array values.first(*args)
		end

		def proxy_last * args
			wrap_if_array values.last(*args)
		end

		def proxy_slice * args
			wrap_if_array values.slice(*args)
		end

		def proxy_reverse
			Tape::Array.new values.reverse
		end

		def proxy_sort
			Tape::Array.new values.sort
		end

		def proxy_uniq
			Tape::Array.new values.uniq
		end

		def == other
			# I think there's more to this than a simple evaluation. Tbd...
			values == other&.values
		end

		def + other
			Tape::Array.new(values + other.values)
		end

		private

		def wrap_if_array result
			result.is_a?(::Array) ? Tape::Array.new(result) : result
		end
	end

	class Tuple < Tape::Array
		def initialize values = []
			super values
		end

		def inspect
			"(#{values.map(&:inspect).join(', ')})"
		end
	end
end
