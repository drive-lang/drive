require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

# tests/fixtures/dir_tree/
#   a.txt        3 bytes
#   b.txt        5 bytes
#   sub/c.txt   10 bytes
class Dir_Test < Base_Test
	TREE = 'tests/fixtures/dir_tree'

	def interp(code) = Backend.interp(code)

	def test_a_dir_has_type_identity
		assert_equal true, interp("Dir('#{TREE}') === Dir")
		assert_equal true, interp("Dir('#{TREE}') =>= Directory")
		assert_equal true, interp("x: Dir = Dir('#{TREE}')\nx.exists?()")
	end

	def test_name_and_existence
		assert_equal 'dir_tree', interp("Dir('#{TREE}').name()").value
		assert_equal true,  interp("Dir('#{TREE}').exists?()")
		assert_equal false, interp("Dir('#{TREE}/nope').exists?()")
		assert_equal false, interp("Dir('#{TREE}').empty?()")
		assert_equal true,  interp("Dir('#{TREE}/sub').empty?() == false")
	end

	def test_listing
		assert_equal ['a.txt', 'b.txt', 'sub'], interp("Dir('#{TREE}').names()").values
		assert_includes interp("Dir('#{TREE}').entries()").values, '.'

		children = interp("Dir('#{TREE}').children()").values
		assert_equal ["#{TREE}/a.txt", "#{TREE}/b.txt", "#{TREE}/sub"], children

		assert_equal ["#{TREE}/sub"],                     interp("Dir('#{TREE}').subdirs()").values
		assert_equal ["#{TREE}/a.txt", "#{TREE}/b.txt"],  interp("Dir('#{TREE}').files()").values
	end

	def test_size_is_recursive
		assert_equal 18, interp("Dir('#{TREE}').size()")            # 3 + 5 + 10
		assert_equal 10, interp("Dir('#{TREE}').size_of('#{TREE}/sub')")
		assert_equal 3,  interp("Dir('#{TREE}').size_of('#{TREE}/a.txt')")
		assert_equal 0,  interp("Dir('#{TREE}').size_of('#{TREE}/missing')")
	end

	def test_path_predicates
		out = interp("d := Dir('#{TREE}')\n(d.is_dir?('#{TREE}/sub'), d.is_file?('#{TREE}/a.txt'), d.is_dir?('#{TREE}/a.txt'))")
		assert_equal [true, true, false], out.values
	end

	def test_pwd_and_home_are_dirs
		assert_equal true, interp('Dir.pwd() === Dir')
		assert_equal true, interp('Dir.home() === Dir')
	end

	def test_to_s
		assert_equal "Dir(#{TREE})", interp("Dir('#{TREE}').to_s()").value
	end

	# A squarified treemap needs a {name, size, children} tree -- the two building blocks are
	# `.files()` + `.size_of` for leaves and `.subdirs()` for recursion.
	def test_builds_a_weighted_tree
		out = interp <<~CODE
		    weigh ( d: Dir;
		    	total := 0
		    	for d.files()    total += d.size_of(it)  end
		    	for d.subdirs()  total += weigh(Dir(it)) end
		    	total
		    )
		    weigh(Dir('#{TREE}'))
		CODE
		assert_equal 18, out
	end
end
