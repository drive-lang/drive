require 'minitest/autorun'
require 'tmpdir'
require_relative '../backend/backend'
require_relative 'base_test'

class File_Test < Base_Test
	def test_file_has_type_identity
		assert_equal true, Backend.interp('File =>= File')
	end

	def test_read
		out = Backend.interp "File.read('tests/fixtures/hello_read.txt')"
		assert_equal "Hello, Read!\n", out.value

		out = Backend.interp "File.read_file_to_string('tests/fixtures/hello_read.txt')"
		assert_equal "Hello, Read!\n", out.value
	end

	def test_read_chains
		assert_equal 'HELLO, READ!', Backend.interp("File.read('tests/fixtures/hello_read.txt').trim().upcase()")
	end

	def test_list_directory
		names = Backend.interp("Dir('tests/fixtures').names()").values
		assert_includes names, 'hello_read.txt'
		assert_equal names, names.sort
	end

	def test_write_round_trips
		path = File.join(Dir.mktmpdir, 'written.txt')
		Backend.interp "File.write_string_to_file('#{path}', 'round trip')"
		assert_equal 'round trip', File.read(path)
	end
end
