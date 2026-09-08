require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# `tapes/context.tape` is the human-readable mirror of Tape::Context::MEMBERS (see the note there).
# The two drift apart the moment someone adds a member to one and forgets the other -- exactly the
# bug that shipped `splatr`/`splatw` half-wired. Keep them locked together.
class Context_Test < Base_Test
	def context_tape_member_names
		path   = File.join(Drive::ROOT_PATH, 'tapes', 'context.tape')
		struct = Drive.parse_file(path).find { |expr| expr.is_a?(Tape::Struct_Expr) }
		refute_nil struct, 'expected a `Context <...>` struct declaration in tapes/context.tape'
		struct.names.compact
	end

	def test_context_tape_lists_exactly_the_members_in_the_constant
		assert_equal Tape::Context::MEMBERS.keys.sort, context_tape_member_names.sort
	end

	def test_derived_lists_are_consistent
		# STACK_FUNCTIONS is a subset of FUNCTIONS.
		assert_empty Tape::Context::STACK_FUNCTIONS - Tape::Context::FUNCTIONS

		# A vital and a function are mutually exclusive; together they are every member.
		assert_empty Tape::Context::VITALS & Tape::Context::FUNCTIONS
		assert_equal Tape::Context::MEMBERS.keys.sort, (Tape::Context::VITALS + Tape::Context::FUNCTIONS).sort
	end
end
