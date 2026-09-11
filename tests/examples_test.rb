require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

# Runs every examples/*.prog file end to end and asserts none of them raise -- these are meant to be
# runnable teaching examples (see .claude/CLAUDE.md's examples/ doc style notes), so a file that
# errors out is a broken lesson, not just a broken test. One generated test method per file,
# rather than one test looping over all of them, so a failure names exactly which file broke
# instead of stopping at the first one.
class Examples_Test < Base_Test
	::Dir.glob(::File.join(__dir__, '../examples/*.prog')).sort.each do |filepath|
		name = ::File.basename(filepath, '.prog')

		define_method "test_#{name}" do
			refute_raises do
				Backend.interp_file filepath
			end
		end
	end
end
