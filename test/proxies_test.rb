require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class ProxiesTest < Base_Test
	def test_invalid_proxy_directive_usage
		assert_raises Lost::Invalid_Ruby_Proxy_Directive_Usage do
			Lost.interp '@ruby'
		end
	end

	def test_string_proxies
		assert_equal 12, Lost.interp("'hello, world'.length")
		assert_equal 104, Lost.interp("'hello, world'.ord")

		assert_equal "HELLO", Lost.interp("'hello'.upcase()")
		assert_equal "world", Lost.interp("'WORLD'.downcase()")

		assert_equal ['he', '', 'o'], Lost.interp("'hello'.split('l')").values
		assert_equal "ORL", Lost.interp("'WORLD'.slice('ORL')")

		assert_equal "Locke!", Lost.interp("'   Locke!    '.trim()")
		assert_equal "Locke!    ", Lost.interp("'   Locke!    '.trim_left()")
		assert_equal "   Locke!", Lost.interp("'   Locke!    '.trim_right()")

		assert_equal %w(w a l t), Lost.interp("'walt'.chars()").values
		assert_equal 6, Lost.interp("'Enter the numbers'.index('the')")

		assert_equal 123, Lost.interp("'123'.to_i()")
		assert_equal 456.0, Lost.interp("'456'.to_f()")

		assert Lost.interp("''.empty?()")
		refute Lost.interp("'cool'.empty?()")

		assert Lost.interp("'island'.include?('and')")
		refute Lost.interp("'island'.include?('or')")

		assert_equal 'edcba', Lost.interp("'abcde'.reverse()")
		assert_equal 'replaced', Lost.interp("'replace_me'.replace('replaced')")

		assert Lost.interp("'hello world'.start_with?('hello')")
		refute Lost.interp("'hello world'.start_with?('world')")

		assert Lost.interp("'hello world'.end_with?('world')")
		refute Lost.interp("'hello world'.end_with?('hello')")

		assert_equal 'hellu wurld', Lost.interp("'hello world'.gsub('o', 'u')")
		assert_equal 'heyo world', Lost.interp("'hello world'.gsub('hell', 'hey')")
	end

	def test_array_proxies
		out = Lost.interp <<~TAPE
		    x := [1, 2, 3]
		    y := []
		    x.each(( item;
		        y << item * 2
		    ))
		    y
		TAPE
		assert_equal [2, 4, 6], out.values

		out = Lost.interp("arr := [1, 2], arr.push(3), arr")
		assert_equal [1, 2, 3], out.values

		out = Lost.interp("arr := [1, 2, 3], arr.pop(), arr")
		assert_equal [1, 2], out.values

		out = Lost.interp("arr := [1, 2, 3], arr.shift(), arr")
		assert_equal [2, 3], out.values

		out = Lost.interp("arr := [2, 3], arr.unshift(1), arr")
		assert_equal [1, 2, 3], out.values

		assert_equal 3, Lost.interp("[1, 2, 3].length()")
		assert_equal 0, Lost.interp("[].length()")

		assert_equal [1, 2], Lost.interp("[1, 2, 3, 4].first(2)").values
		assert_equal [3, 4], Lost.interp("[1, 2, 3, 4].last(2)").values

		assert_equal [2, 3], Lost.interp("[1, 2, 3, 4].slice(1, 2)").values

		assert_equal [3, 2, 1], Lost.interp("[1, 2, 3].reverse()").values

		assert_equal "1,2,3", Lost.interp("[1, 2, 3].join(',')")

		assert_equal [2, 4, 6], Lost.interp("[1, 2, 3].map(( x, i; x * 2 ))").values
		assert_equal [2, 4], Lost.interp("[1, 2, 3, 4].filter(( x; x % 2 == 0 ))").values
		assert_equal 10, Lost.interp("[1, 2, 3, 4].accumulate(0, ( acc, x; acc + x ))")

		assert_equal [1, 2, 3, 4, 5], Lost.interp("[1, 2, 3].concat([4, 5])")
		assert_equal [1, 2, 3, 4], Lost.interp("[[1, 2], [3, 4]].flatten()").values
		assert_equal [1, 2, 3], Lost.interp("[3, 1, 2].sort()").values
		assert_equal [1, 2, 3], Lost.interp("[1, 2, 2, 3, 1].uniq()").values

		assert Lost.interp("[1, 2, 3].include?(2)")
		refute Lost.interp("[1, 2, 3].include?(5)")

		assert Lost.interp("[].empty?()")
		refute Lost.interp("[1].empty?()")

		assert_equal 2, Lost.interp("[1, 2, 3].find(( x; x > 1 ))")
		assert_nil Lost.interp("[1, 2, 3].find(( x; x > 5 ))")

		assert Lost.interp("[1, 2, 3].any?(( x; x > 2 ))")
		refute Lost.interp("[1, 2, 3].any?(( x; x > 5 ))")

		assert Lost.interp("[1, 2, 3].all?(( x; x > 0 ))")
		refute Lost.interp("[1, 2, 3].all?(( x; x > 2 ))")
	end

	def test_include_respects_custom_equality_overload
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	new ( x, y;
		    		self.x = x
		    		self.y = y
		    	)

		    	@operator == @infix 500 ( left, right;
		    		left.x == right.x and left.y == right.y
		    	)
		    }

		    a := [Point(1, 2), Point(3, 4)]
		    (a.include?(Point(1, 2)), a.include?(Point(9, 9)))
		CODE
		out = Lost.interp src
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
	end

	def test_array_equality_respects_custom_equality_overload
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	new ( x, y;
		    		self.x = x
		    		self.y = y
		    	)

		    	@operator == @infix 500 ( left, right;
		    		left.x == right.x and left.y == right.y
		    	)
		    }

		    a := [Point(1, 2), Point(3, 4)]
		    b := [Point(1, 2), Point(3, 4)]
		    c := [Point(1, 2), Point(9, 9)]
		    (a == b, a == c, a == [Point(1, 2)])
		CODE
		out = Lost.interp src
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
		assert_equal false, out.values[2]
	end

	def test_dictionary_proxies
		assert Lost.interp("{}.empty?()")
		refute Lost.interp("{x: 1}.empty?()")

		out = Lost.interp("d := {x: 1, y: 2}, d.clear(), d")
		assert_equal({}, out.hash)

		assert_equal 1, Lost.interp("{x: 1}.fetch(:x, 0)")
		assert_equal 0, Lost.interp("{x: 1}.fetch(:y, 0)")

		assert_equal [:x, :y, :z], Lost.interp("{x: 1, y: 2, z: 3}.keys()").values
		assert_equal [1, 2, 3], Lost.interp("{x: 1, y: 2, z: 3}.values()").values

		assert Lost.interp("{x: 1, y: 2}.has_key?(:x)")
		refute Lost.interp("{x: 1, y: 2}.has_key?(:z)")

		out = Lost.interp("d := {x: 1, y: 2, z: 3}, d.delete(:y), d")
		assert_equal({ x: 1, z: 3 }, out.hash)

		assert_equal 3, Lost.interp("{x: 1, y: 2, z: 3}.count()")
		assert_equal 0, Lost.interp("{}.count()")

		out = Lost.interp "{x: 1}.merge({y: 2, z: 3})"
		assert_equal({ x: 1, y: 2, z: 3 }, out.hash)
	end

	def test_number_proxies
		assert Lost.interp("4.even?()")
		refute Lost.interp("5.even?()")

		assert Lost.interp("5.odd?()")
		refute Lost.interp("4.odd?()")

		assert_equal 42, Lost.interp("42.5.to_i()")
		assert_equal 42.0, Lost.interp("42.to_f()")

		assert_equal 5, Lost.interp("3.clamp(5, 10)")
		assert_equal 7, Lost.interp("7.clamp(5, 10)")
		assert_equal 10, Lost.interp("15.clamp(5, 10)")

		assert_equal "42", Lost.interp("42.to_s()")
		assert_equal "3.14", Lost.interp("3.14.to_s()")

		assert_equal 5, Lost.interp("5.abs()")
		assert_equal 5, Lost.interp("-5.abs()")

		assert_equal 3, Lost.interp("3.14.floor()")
		assert_equal(-4, Lost.interp("-3.14.floor()"))

		assert_equal 4, Lost.interp("3.14.ceil()")
		assert_equal(-3, Lost.interp("-3.14.ceil()"))

		assert_equal 3, Lost.interp("3.14.round()")
		assert_equal 4, Lost.interp("3.5.round()")

		assert_equal 3, Lost.interp("9.sqrt()")
		assert_equal 5, Lost.interp("25.sqrt()")
	end
end
