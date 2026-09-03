require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

class ProxiesTest < Base_Test
	def test_invalid_proxy_directive_usage
		assert_raises Tape::Invalid_Ruby_Proxy_Directive_Usage do
			Tape.interp '@ruby'
		end
	end

	def test_string_proxies
		assert_equal 12, Tape.interp("'hello, world'.length")
		assert_equal 104, Tape.interp("'hello, world'.ord")

		assert_equal "HELLO", Tape.interp("'hello'.upcase()")
		assert_equal "world", Tape.interp("'WORLD'.downcase()")

		assert_equal ['he', '', 'o'], Tape.interp("'hello'.split('l')").values
		assert_equal "ORL", Tape.interp("'WORLD'.slice(1, 3)")

		assert_equal "Locke!", Tape.interp("'   Locke!    '.trim()")
		assert_equal "Locke!    ", Tape.interp("'   Locke!    '.trim_left()")
		assert_equal "   Locke!", Tape.interp("'   Locke!    '.trim_right()")

		assert_equal %w(w a l t), Tape.interp("'walt'.chars()").values
		assert_equal 6, Tape.interp("'Enter the numbers'.index('the')")

		assert_equal 123, Tape.interp("'123'.to_i()")
		assert_equal 456.0, Tape.interp("'456'.to_f()")

		assert Tape.interp("''.empty?()")
		refute Tape.interp("'cool'.empty?()")

		assert Tape.interp("'island'.include?('and')")
		refute Tape.interp("'island'.include?('or')")

		assert_equal 'edcba', Tape.interp("'abcde'.reverse()")
		assert_equal 'replaced', Tape.interp("'replace_me'.replace('replaced')")

		assert Tape.interp("'hello world'.start_with?('hello')")
		refute Tape.interp("'hello world'.start_with?('world')")

		assert Tape.interp("'hello world'.end_with?('world')")
		refute Tape.interp("'hello world'.end_with?('hello')")

		assert_equal 'hellu wurld', Tape.interp("'hello world'.gsub('o', 'u')")
		assert_equal 'heyo world', Tape.interp("'hello world'.gsub('hell', 'hey')")
	end

	def test_array_proxies
		out = Tape.interp <<~TAPE
		    x := [1, 2, 3]
		    y := []
		    x.each(( item;
		        y << item * 2
		    ))
		    y
		TAPE
		assert_equal [2, 4, 6], out.values

		out = Tape.interp("arr := [1, 2], arr.push(3), arr")
		assert_equal [1, 2, 3], out.values

		out = Tape.interp("arr := [1, 2, 3], arr.pop(), arr")
		assert_equal [1, 2], out.values

		out = Tape.interp("arr := [1, 2, 3], arr.shift(), arr")
		assert_equal [2, 3], out.values

		out = Tape.interp("arr := [2, 3], arr.unshift(1), arr")
		assert_equal [1, 2, 3], out.values

		assert_equal 3, Tape.interp("[1, 2, 3].length()")
		assert_equal 0, Tape.interp("[].length()")

		assert_equal [1, 2], Tape.interp("[1, 2, 3, 4].first(2)").values
		assert_equal [3, 4], Tape.interp("[1, 2, 3, 4].last(2)").values

		assert_equal [2, 3], Tape.interp("[1, 2, 3, 4].slice(1, 2)").values

		assert_equal [3, 2, 1], Tape.interp("[1, 2, 3].reverse()").values

		assert_equal "1,2,3", Tape.interp("[1, 2, 3].join(',')")

		assert_equal [2, 4, 6], Tape.interp("[1, 2, 3].map(( x, i; x * 2 ))").values
		assert_equal [2, 4], Tape.interp("[1, 2, 3, 4].filter(( x; x % 2 == 0 ))").values
		assert_equal 10, Tape.interp("[1, 2, 3, 4].accumulate(0, ( acc, x; acc + x ))")

		assert_equal [1, 2, 3, 4, 5], Tape.interp("[1, 2, 3].concat([4, 5])")
		assert_equal [1, 2, 3, 4], Tape.interp("[[1, 2], [3, 4]].flatten()").values
		assert_equal [1, 2, 3], Tape.interp("[3, 1, 2].sort()").values
		assert_equal [1, 2, 3], Tape.interp("[1, 2, 2, 3, 1].uniq()").values

		assert Tape.interp("[1, 2, 3].include?(2)")
		refute Tape.interp("[1, 2, 3].include?(5)")

		assert Tape.interp("[].empty?()")
		refute Tape.interp("[1].empty?()")

		assert_equal 2, Tape.interp("[1, 2, 3].find(( x; x > 1 ))")
		assert_nil Tape.interp("[1, 2, 3].find(( x; x > 5 ))")

		assert Tape.interp("[1, 2, 3].any?(( x; x > 2 ))")
		refute Tape.interp("[1, 2, 3].any?(( x; x > 5 ))")

		assert Tape.interp("[1, 2, 3].all?(( x; x > 0 ))")
		refute Tape.interp("[1, 2, 3].all?(( x; x > 2 ))")
	end

	def test_hof_callbacks_keep_their_closure
		# map/filter/find are written in Tape; calling the callback used to rebind its enclosing_scope
		# to the HOF's own frame, so a callback could read its params but not anything from the
		# function it was written in.
		assert_equal [11, 12, 13], Tape.interp(<<~CODE).values
		    f (;
		    	base := 10
		    	[1, 2, 3].map(( n; n + base ))
		    )
		    f()
		CODE

		assert_equal [3, 4], Tape.interp(<<~CODE).values
		    f ( floor;
		    	[1, 2, 3, 4].filter(( n; n > floor ))
		    )
		    f(2)
		CODE

		assert_equal 30, Tape.interp(<<~CODE)
		    Thing {
		    	step := 10
		    	third (; [1, 2, 3].map(( n; n * step )).2 )
		    }
		    Thing().third()
		CODE
	end

	def test_spread_lambda_argument_runs_like_the_wrapped_form
		assert_equal [2, 4, 6], Tape.interp("[1, 2, 3].map(x; x * 2)").values
		assert_equal [2, 4], Tape.interp("[1, 2, 3, 4].filter(n; n % 2 == 0)").values
		assert_equal 2, Tape.interp("[1, 2, 3].find(x; x > 1)")
		assert_equal [4, 6], Tape.interp("[1, 2, 3].map(x; x * 2).filter(n; n > 2)").values
		assert_equal [[10, 20], [30, 40]], Tape.interp("[[1, 2], [3, 4]].map(row; row.map(n; n * 10))").values.map(&:values)
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
		out = Tape.interp src
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
		out = Tape.interp src
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
		assert_equal false, out.values[2]
	end

	def test_dictionary_proxies
		assert Tape.interp("{}.empty?()")
		refute Tape.interp("{x: 1}.empty?()")

		out = Tape.interp("d := {x: 1, y: 2}, d.clear(), d")
		assert_equal({}, out.hash)

		assert_equal 1, Tape.interp("{x: 1}.fetch(:x, 0)")
		assert_equal 0, Tape.interp("{x: 1}.fetch(:y, 0)")

		assert_equal [:x, :y, :z], Tape.interp("{x: 1, y: 2, z: 3}.keys()").values
		assert_equal [1, 2, 3], Tape.interp("{x: 1, y: 2, z: 3}.values()").values

		assert Tape.interp("{x: 1, y: 2}.has_key?(:x)")
		refute Tape.interp("{x: 1, y: 2}.has_key?(:z)")

		out = Tape.interp("d := {x: 1, y: 2, z: 3}, d.delete(:y), d")
		assert_equal({ x: 1, z: 3 }, out.hash)

		assert_equal 3, Tape.interp("{x: 1, y: 2, z: 3}.count()")
		assert_equal 0, Tape.interp("{}.count()")

		out = Tape.interp "{x: 1}.merge({y: 2, z: 3})"
		assert_equal({ x: 1, y: 2, z: 3 }, out.hash)
	end

	def test_number_proxies
		assert Tape.interp("4.even?()")
		refute Tape.interp("5.even?()")

		assert Tape.interp("5.odd?()")
		refute Tape.interp("4.odd?()")

		assert_equal 42, Tape.interp("42.5.to_i()")
		assert_equal 42.0, Tape.interp("42.to_f()")

		assert_equal 5, Tape.interp("3.clamp(5, 10)")
		assert_equal 7, Tape.interp("7.clamp(5, 10)")
		assert_equal 10, Tape.interp("15.clamp(5, 10)")

		assert_equal "42", Tape.interp("42.to_s()")
		assert_equal "3.14", Tape.interp("3.14.to_s()")

		assert_equal 5, Tape.interp("5.abs()")
		assert_equal 5, Tape.interp("-5.abs()")

		assert_equal 3, Tape.interp("3.14.floor()")
		assert_equal(-4, Tape.interp("-3.14.floor()"))

		assert_equal 4, Tape.interp("3.14.ceil()")
		assert_equal(-3, Tape.interp("-3.14.ceil()"))

		assert_equal 3, Tape.interp("3.14.round()")
		assert_equal 4, Tape.interp("3.5.round()")

		assert_equal 3, Tape.interp("9.sqrt()")
		assert_equal 5, Tape.interp("25.sqrt()")
	end

	# Numbers mirror Ruby: an int literal is a Tape::Integer, a float literal a Tape::Float, both
	# composing Number. `value` is the wrapped Ruby Numeric; numerator/denominator delegate to it.
	def test_numeric_family
		assert_equal 4,   Tape.interp("4.value")
		assert_equal 4.5, Tape.interp("4.5.value")
		assert_equal 4,   Tape.interp("Integer(4).value")
		assert_equal 4,   Tape.interp("Integer(4.9).value")           # coerces via to_i
		assert_equal 4.0, Tape.interp("Float(4).value")
		assert_equal "1.5", Tape.interp("Decimal('1.5').to_s()")        # BigDecimal-backed

		assert_equal true,  Tape.interp("4 === Integer")
		assert_equal true,  Tape.interp("4.5 === Float")
		assert_equal false, Tape.interp("4 === Float")
		assert_equal true,  Tape.interp("4 =>= Number")
		assert_equal true,  Tape.interp("4.5 =>= Number")

		assert_equal 4, Tape.interp("4.numerator()")
		assert_equal 1, Tape.interp("4.denominator()")
		assert_equal 5, Tape.interp("2.5.numerator()")
		assert_equal 2, Tape.interp("2.5.denominator()")
	end

	# `Int` / `Flo` / `Dec` are plain aliases in tapes/number.tape (`Int := Integer`, not
	# `Int | Integer {}`), so each *is* its full type -- same type-set, not a narrower one.
	def test_numeric_type_shorthands
		# construction + coercion, identical to the full names
		assert_equal 4,     Tape.interp("Int(4).value")
		assert_equal 4,     Tape.interp("Int(4.9).value")            # to_i, like Integer(4.9)
		assert_equal 4.0,   Tape.interp("Flo(4).value")              # to_f, like Float(4)
		assert_equal "1.5", Tape.interp("Dec('1.5').to_s()")        # BigDecimal, like Decimal('1.5')

		# the alias *is* the type -- a bare literal matches both names exactly
		assert_equal true, Tape.interp("4 === Int")
		assert_equal true, Tape.interp("4 === Integer")
		assert_equal true, Tape.interp("Int === Integer")
		assert_equal true, Tape.interp("4.5 === Flo")
		assert_equal true, Tape.interp("4 =>= Number")

		# they compose Number, so Number's arithmetic just works
		assert_equal 7,   Tape.interp("Int(3) + Int(4)")
		assert_equal 4.0, Tape.interp("Flo(1.5) + Flo(2.5)")
		assert_equal 3,   Tape.interp("Int(10) / Int(3)")           # integer division, still lossy
		assert_equal "0.3", Tape.interp("(Dec('0.1') + Dec('0.2')).to_s()")  # exact, unlike Float
	end

	# A proxy method that builds and returns a fresh Tape:: instance (`Tape::String.new` here) seeds `@types` from its Ruby class name (`"Tape::String"`), so the return value used to fail every type-identity check. `read_file_to_string` itself declares `-> String`, so this raised `Type_Contract_Violation` ("expected String, got String") before it could even return.
	def test_proxy_return_value_satisfies_type_identity
		fixture = "'test/fixtures/hello_read.txt'"

		assert_equal true, Tape.interp("read_file_to_string(#{fixture}) === String")

		wrapped = <<~CODE
		    get_it ( -> String;
		    	read_file_to_string(#{fixture})
		    )
		    get_it()
		CODE
		assert_equal "Hello, Read!\n", Tape.interp(wrapped).value
	end
end
