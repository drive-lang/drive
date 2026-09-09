require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

class Collections_Test < Base_Test
	def test_array_initialize_with_varargs
		# These mimic Ruby's behavior
		out = Backend.interp "Array(4, 8, 15, 16)"
		assert_equal [4, 8, 15, 16], out.values

		out = Backend.interp "Array(23 42)"
		assert_equal [23, 42], out.values
	end

	def test_array_static_initializer_functions
		out = Backend.interp "
		size := 5
		value := 42
		Array.of(value, size)"
		assert_equal [42, 42, 42, 42, 42], out.values

		# This also mimics Ruby's behavior:
		out = Backend.interp "
		size := 4
		value := 8
		Array.new(size, value)"
		assert_equal [8, 8, 8, 8], out.values
	end
end
