require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

class ProxiesTest < Base_Test
	def test_invalid_proxy_directive_usage
		assert_raises Prog::Invalid_Ruby_Proxy_Usage do
			Backend.interp '@ruby'
		end
	end

	def test_string_proxies
		assert_equal 12, Backend.interp("'hello, world'.length")
		assert_equal 104, Backend.interp("'hello, world'.ord")

		assert_equal "HELLO", Backend.interp("'hello'.upcase()")
		assert_equal "world", Backend.interp("'WORLD'.downcase()")

		assert_equal ['he', '', 'o'], Backend.interp("'hello'.split('l')").values
		assert_equal "ORL", Backend.interp("'WORLD'.slice(1, 3)")

		assert_equal "Locke!", Backend.interp("'   Locke!    '.trim()")
		assert_equal "Locke!    ", Backend.interp("'   Locke!    '.trim_left()")
		assert_equal "   Locke!", Backend.interp("'   Locke!    '.trim_right()")

		assert_equal %w(w a l t), Backend.interp("'walt'.chars()").values
		assert_equal 6, Backend.interp("'Enter the numbers'.index('the')")

		assert_equal 123, Backend.interp("'123'.to_i()")
		assert_equal 456.0, Backend.interp("'456'.to_f()")

		assert Backend.interp("''.empty?()")
		refute Backend.interp("'cool'.empty?()")

		assert Backend.interp("'island'.include?('and')")
		refute Backend.interp("'island'.include?('or')")

		assert_equal 'edcba', Backend.interp("'abcde'.reverse()")
		assert_equal 'replaced', Backend.interp("'replace_me'.replace('replaced')")

		assert Backend.interp("'hello world'.start_with?('hello')")
		refute Backend.interp("'hello world'.start_with?('world')")

		assert Backend.interp("'hello world'.end_with?('world')")
		refute Backend.interp("'hello world'.end_with?('hello')")

		assert_equal 'hellu wurld', Backend.interp("'hello world'.gsub('o', 'u')")
		assert_equal 'heyo world', Backend.interp("'hello world'.gsub('hell', 'hey')")
	end

	def test_array_proxies
		out = Backend.interp <<~CODE
		    x := [1, 2, 3]
		    y := []
		    x.each(( item;
		        y << item * 2
		    ))
		    y
		CODE
		assert_equal [2, 4, 6], out.values

		out = Backend.interp("arr := [1, 2], arr.push(3), arr")
		assert_equal [1, 2, 3], out.values

		out = Backend.interp("arr := [1, 2, 3], arr.pop(), arr")
		assert_equal [1, 2], out.values

		out = Backend.interp("arr := [1, 2, 3], arr.shift(), arr")
		assert_equal [2, 3], out.values

		out = Backend.interp("arr := [2, 3], arr.unshift(1), arr")
		assert_equal [1, 2, 3], out.values

		assert_equal 3, Backend.interp("[1, 2, 3].length()")
		assert_equal 0, Backend.interp("[].length()")

		assert_equal [1, 2], Backend.interp("[1, 2, 3, 4].first(2)").values
		assert_equal [3, 4], Backend.interp("[1, 2, 3, 4].last(2)").values

		assert_equal [2, 3], Backend.interp("[1, 2, 3, 4].slice(1, 2)").values

		assert_equal [3, 2, 1], Backend.interp("[1, 2, 3].reverse()").values

		assert_equal "1,2,3", Backend.interp("[1, 2, 3].join(',')")

		assert_equal [2, 4, 6], Backend.interp("[1, 2, 3].map(( x, i; x * 2 ))").values
		assert_equal [2, 4], Backend.interp("[1, 2, 3, 4].filter(( x; x % 2 == 0 ))").values
		assert_equal 10, Backend.interp("[1, 2, 3, 4].accumulate(0, ( acc, x; acc + x ))")

		assert_equal [1, 2, 3, 4, 5], Backend.interp("[1, 2, 3].concat([4, 5])")
		assert_equal [1, 2, 3, 4], Backend.interp("[[1, 2], [3, 4]].flatten()").values
		assert_equal [1, 2, 3], Backend.interp("[3, 1, 2].sort()").values
		assert_equal [1, 2, 3], Backend.interp("[1, 2, 2, 3, 1].uniq()").values

		assert Backend.interp("[1, 2, 3].include?(2)")
		refute Backend.interp("[1, 2, 3].include?(5)")

		assert Backend.interp("[].empty?()")
		refute Backend.interp("[1].empty?()")

		assert_equal 2, Backend.interp("[1, 2, 3].find(( x; x > 1 ))")
		assert_nil Backend.interp("[1, 2, 3].find(( x; x > 5 ))")

		assert Backend.interp("[1, 2, 3].any?(( x; x > 2 ))")
		refute Backend.interp("[1, 2, 3].any?(( x; x > 5 ))")

		assert Backend.interp("[1, 2, 3].all?(( x; x > 0 ))")
		refute Backend.interp("[1, 2, 3].all?(( x; x > 2 ))")
	end

	def test_hof_callbacks_keep_their_closure
		# map/filter/find are written in Backend; calling the callback used to rebind its enclosing_scope
		# to the HOF's own frame, so a callback could read its params but not anything from the
		# function it was written in.
		assert_equal [11, 12, 13], Backend.interp(<<~CODE).values
		    f (;
		    	base := 10
		    	[1, 2, 3].map(( n; n + base ))
		    )
		    f()
		CODE

		assert_equal [3, 4], Backend.interp(<<~CODE).values
		    f ( floor;
		    	[1, 2, 3, 4].filter(( n; n > floor ))
		    )
		    f(2)
		CODE

		assert_equal 30, Backend.interp(<<~CODE)
		    Thing {
		    	step := 10
		    	third (; [1, 2, 3].map(( n; n * step )).2 )
		    }
		    Thing().third()
		CODE
	end

	def test_spread_lambda_argument_runs_like_the_wrapped_form
		assert_equal [2, 4, 6], Backend.interp("[1, 2, 3].map(x; x * 2)").values
		assert_equal [2, 4], Backend.interp("[1, 2, 3, 4].filter(n; n % 2 == 0)").values
		assert_equal 2, Backend.interp("[1, 2, 3].find(x; x > 1)")
		assert_equal [4, 6], Backend.interp("[1, 2, 3].map(x; x * 2).filter(n; n > 2)").values
		assert_equal [[10, 20], [30, 40]], Backend.interp("[[1, 2], [3, 4]].map(row; row.map(n; n * 10))").values.map(&:values)
	end

	def test_include_respects_custom_equality_overload
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	Self ( x, y;
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
		out = Backend.interp src
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
	end

	def test_array_equality_respects_custom_equality_overload
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	Self ( x, y;
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
		out = Backend.interp src
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
		assert_equal false, out.values[2]
	end

	def test_dictionary_proxies
		assert Backend.interp("{}.empty?()")
		refute Backend.interp("{x: 1}.empty?()")

		out = Backend.interp("d := {x: 1, y: 2}, d.clear(), d")
		assert_equal({}, out.hash)

		assert_equal 1, Backend.interp("{x: 1}.fetch(:x, 0)")
		assert_equal 0, Backend.interp("{x: 1}.fetch(:y, 0)")

		assert_equal [:x, :y, :z], Backend.interp("{x: 1, y: 2, z: 3}.keys()").values
		assert_equal [1, 2, 3], Backend.interp("{x: 1, y: 2, z: 3}.values()").values

		assert Backend.interp("{x: 1, y: 2}.has_key?(:x)")
		refute Backend.interp("{x: 1, y: 2}.has_key?(:z)")

		out = Backend.interp("d := {x: 1, y: 2, z: 3}, d.delete(:y), d")
		assert_equal({ x: 1, z: 3 }, out.hash)

		assert_equal 3, Backend.interp("{x: 1, y: 2, z: 3}.count()")
		assert_equal 0, Backend.interp("{}.count()")

		out = Backend.interp "{x: 1}.merge({y: 2, z: 3})"
		assert_equal({ x: 1, y: 2, z: 3 }, out.hash)
	end

	# Range is an Instance wrapping a Ruby ::Range now (not a ::Range subclass) -- it has real Backend
	# methods, type identity, and satisfies a `: Range` contract, none of which worked before.
	def test_range_proxies
		assert_equal 2, Backend.interp("(2...4).start()")
		assert_equal 4, Backend.interp("(2...4).finish()")
		assert_equal 3, Backend.interp("(2>..4).start()") # `>..` bumps the start
		assert Backend.interp("(1..<5).excludes_end?()")
		refute Backend.interp("(1...5).excludes_end?()")

		assert_equal 5, Backend.interp("(1...5).length()")
		assert_equal 0, Backend.interp("(0>.<0).length()")
		assert Backend.interp("(0>.<0).empty?()")

		assert Backend.interp("(1...5).include?(3)")
		refute Backend.interp("(1...5).include?(9)")

		assert_equal [1, 2, 3, 4, 5], Backend.interp("(1...5).to_a()").values
		assert_equal 15, Backend.interp("(1...5).sum()")
		assert_equal 1, Backend.interp("(1...5).min()")
		assert_equal 5, Backend.interp("(1...5).max()")
		assert_equal '1..<5', Backend.interp("(1..<5).to_s()")

		# prog-level higher-order methods iterate the range directly (`for self`)
		assert_equal [1, 4, 9], Backend.interp("(1...3).map((n; n * n))").values
		assert_equal [2, 4], Backend.interp("(1...5).filter((n; n % 2 == 0))").values
		assert_equal 15, Backend.interp("(1...5).reduce(0, (acc, n; acc + n))")
		assert Backend.interp("(1...5).any?((n; n == 3))")
		refute Backend.interp("(1...5).all?((n; n > 3))")

		# type identity + contract, both broken while it was a ::Range subclass
		assert Backend.interp("(1...5) === Range")
		assert Backend.interp("(1...5) =>= Range")
		assert_equal 5, Backend.interp("x: Range = 1...5\nx.length()")
	end

	# Set has no literal syntax and no Ruby-stdlib behavior worth re-verifying here -- these cover
	# only the seams our layer adds: `@ruby` proxy dispatch, `Set(...)` construction + dedup,
	# operator dispatch (#interp_logical_infix / #interp_arithmetic_infix) with #maybe_instance
	# re-linking the result, `for` iteration, and the prog-level methods in backend/set.prog.
	def test_set_proxies
		# construction dedups; values() is an Array snapshot
		assert_equal [1, 2, 3], Backend.interp("Set([1, 2, 2, 3, 1]).values()").values
		assert_equal [1, 2, 3], Backend.interp("Set(1...3).values()").values
		assert_equal [1, 2], Backend.interp("Set(Set([1, 2, 2])).values()").values

		assert_equal 3, Backend.interp("Set([1, 2, 3]).length()")
		assert Backend.interp("Set([]).empty?()")
		refute Backend.interp("Set([1]).empty?()")

		assert Backend.interp("Set([1, 2, 3]).include?(2)")
		refute Backend.interp("Set([1, 2, 3]).include?(9)")

		# add/delete/merge/clear mutate in place
		assert_equal [1, 2, 3], Backend.interp("s := Set([1, 2]), s.add(2), s.add(3), s.values()").values
		assert_equal [1, 3], Backend.interp("s := Set([1, 2, 3]), s.delete(2), s.values()").values
		assert_equal [1, 2, 3], Backend.interp("s := Set([1]), s.merge([2, 2, 3]), s.values()").values
		assert Backend.interp("s := Set([1, 2, 3]), s.clear(), s.empty?()")

		# operator dispatch + chaining a method off the (re-linked) result
		assert_equal [1, 2, 3, 4], Backend.interp("(Set([1, 2, 3]) | Set([3, 4])).values()").values
		assert_equal [2, 3], Backend.interp("(Set([1, 2, 3]) & Set([2, 3, 4])).values()").values
		assert_equal [1], Backend.interp("(Set([1, 2, 3]) - Set([2, 3, 4])).values()").values
		assert_equal [1, 4], Backend.interp("(Set([1, 2, 3]) ^ Set([2, 3, 4])).values()").values.sort
		assert_equal [2, 3, 4, 5], Backend.interp("Set([1, 2, 3]).union([4, 5]).difference([1]).values()").values

		assert Backend.interp("Set([1, 2]).subset?(Set([1, 2, 3]))")
		assert Backend.interp("Set([1, 2, 3]).superset?(Set([1, 2]))")
		assert Backend.interp("Set([1, 2]).disjoint?(Set([3, 4]))")
		refute Backend.interp("Set([1, 2]).disjoint?(Set([2, 3]))")

		# for-loop iterates the members
		assert_equal 60, Backend.interp("t := 0\nfor Set([10, 20, 30, 10])\n\tt += it\nend\nt")

		# prog-level higher-order methods
		assert_equal [2, 4, 6], Backend.interp("Set([1, 2, 3]).map((n; n * 2))").values
		assert_equal [2, 4], Backend.interp("Set([1, 2, 3, 4]).filter((n; n % 2 == 0)).values()").values
		assert Backend.interp("Set([1, 2, 3]).any?((n; n > 2))")
		refute Backend.interp("Set([1, 2, 3]).all?((n; n > 2))")
	end

	# `@operator ==` in backend/set.prog compares elements through the interpreter, so a custom
	# element type's own `==` overload is honored (a bare Ruby Set#== would miss it).
	def test_set_equality_respects_custom_equality_overload
		src = <<~CODE
		    Point {
		    	x,
		    	y,

		    	Self ( x, y;
		    		self.x = x
		    		self.y = y
		    	)

		    	@operator == @infix 500 ( left, right;
		    		left.x == right.x and left.y == right.y
		    	)
		    }

		    a := Set([Point(1, 2), Point(3, 4)])
		    (a.include?(Point(1, 2)), a == Set([Point(1, 2), Point(3, 4)]), a == Set([Point(1, 2)]))
		CODE
		out = Backend.interp src
		assert_equal true, out.values[0]
		assert_equal true, out.values[1]
		assert_equal false, out.values[2]
	end

	def test_number_proxies
		assert Backend.interp("4.even?()")
		refute Backend.interp("5.even?()")

		assert Backend.interp("5.odd?()")
		refute Backend.interp("4.odd?()")

		assert_equal 42, Backend.interp("42.5.to_i()")
		assert_equal 42.0, Backend.interp("42.to_f()")

		assert_equal 5, Backend.interp("3.clamp(5, 10)")
		assert_equal 7, Backend.interp("7.clamp(5, 10)")
		assert_equal 10, Backend.interp("15.clamp(5, 10)")

		assert_equal "42", Backend.interp("42.to_s()")
		assert_equal "3.14", Backend.interp("3.14.to_s()")

		assert_equal 5, Backend.interp("5.abs()")
		assert_equal 5, Backend.interp("-5.abs()")

		assert_equal 3, Backend.interp("3.14.floor()")
		assert_equal(-4, Backend.interp("-3.14.floor()"))

		assert_equal 4, Backend.interp("3.14.ceil()")
		assert_equal(-3, Backend.interp("-3.14.ceil()"))

		assert_equal 3, Backend.interp("3.14.round()")
		assert_equal 4, Backend.interp("3.5.round()")

		assert_equal 3, Backend.interp("9.sqrt()")
		assert_equal 5, Backend.interp("25.sqrt()")
	end

	# Numbers mirror Ruby: an int literal is a Prog::Integer, a float literal a Prog::Float, both
	# composing Number. `value` is the wrapped Ruby Numeric; numerator/denominator delegate to it.
	def test_numeric_family
		assert_equal 4,   Backend.interp("4.value")
		assert_equal 4.5, Backend.interp("4.5.value")
		assert_equal 4,   Backend.interp("Integer(4).value")
		assert_equal 4,   Backend.interp("Integer(4.9).value")           # coerces via to_i
		assert_equal 4.0, Backend.interp("Float(4).value")
		assert_equal "1.5", Backend.interp("Decimal('1.5').to_s()")        # BigDecimal-backed

		assert_equal true,  Backend.interp("4 === Integer")
		assert_equal true,  Backend.interp("4.5 === Float")
		assert_equal false, Backend.interp("4 === Float")
		assert_equal true,  Backend.interp("4 =>= Number")
		assert_equal true,  Backend.interp("4.5 =>= Number")

		assert_equal 4, Backend.interp("4.numerator()")
		assert_equal 1, Backend.interp("4.denominator()")
		assert_equal 5, Backend.interp("2.5.numerator()")
		assert_equal 2, Backend.interp("2.5.denominator()")
	end

	# `Int` / `Flo` / `Dec` are plain aliases in backend/number.prog (`Int := Integer`, not
	# `Int | Integer {}`), so each *is* its full type -- same type-set, not a narrower one.
	def test_numeric_type_shorthands
		# construction + coercion, identical to the full names
		assert_equal 4,     Backend.interp("Int(4).value")
		assert_equal 4,     Backend.interp("Int(4.9).value")            # to_i, like Integer(4.9)
		assert_equal 4.0,   Backend.interp("Flo(4).value")              # to_f, like Float(4)
		assert_equal "1.5", Backend.interp("Dec('1.5').to_s()")        # BigDecimal, like Decimal('1.5')

		# the alias *is* the type -- a bare literal matches both names exactly
		assert_equal true, Backend.interp("4 === Int")
		assert_equal true, Backend.interp("4 === Integer")
		assert_equal true, Backend.interp("Int === Integer")
		assert_equal true, Backend.interp("4.5 === Flo")
		assert_equal true, Backend.interp("4 =>= Number")

		# they compose Number, so Number's arithmetic just works
		assert_equal 7,   Backend.interp("Int(3) + Int(4)")
		assert_equal 4.0, Backend.interp("Flo(1.5) + Flo(2.5)")
		assert_equal 3,   Backend.interp("Int(10) / Int(3)")           # integer division, still lossy
		assert_equal "0.3", Backend.interp("(Dec('0.1') + Dec('0.2')).to_s()")  # exact, unlike Float
	end

	# A proxy method that builds and returns a fresh Prog:: instance (`Prog::String.new` here) seeds `@types` from its Ruby class name (`"Prog::String"`), so the return value used to fail every type-identity check. `read_file_to_string` itself declares `-> String`, so this raised `Type_Contract_Violation` ("expected String, got String") before it could even return.
	def test_proxy_return_value_satisfies_type_identity
		fixture = "'tests/fixtures/hello_read.txt'"

		assert_equal true, Backend.interp("read_file_to_string(#{fixture}) === String")

		wrapped = <<~CODE
		    get_it ( -> String;
		    	read_file_to_string(#{fixture})
		    )
		    get_it()
		CODE
		assert_equal "Hello, Read!\n", Backend.interp(wrapped).value
	end
end
