require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

# Runs every learn/*.tape file end to end and asserts none of them raise -- these are meant to be
# runnable teaching examples (see .claude/CLAUDE.md's learn/ doc style notes), so a file that
# errors out is a broken lesson, not just a broken test. One generated test method per file,
# rather than one test looping over all of them, so a failure names exactly which file broke
# instead of stopping at the first one.
class Learn_Test < Base_Test
	Dir.glob(File.join(__dir__, '../learn/*.tape')).sort.each do |filepath|
		name = File.basename(filepath, '.tape')

		define_method "test_#{name}" do
			refute_raises do
				Tape.interp_file filepath
			end
		end
	end
end
