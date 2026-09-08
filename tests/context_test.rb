require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# `disks/context.disk` is the human-readable mirror of Disk::Context::MEMBERS (see the note there).
# The two drift apart the moment someone adds a member to one and forgets the other -- exactly the
# bug that shipped `splatr`/`splatw` half-wired. Keep them locked together.
class Context_Test < Base_Test
	def context_disk_member_names
		path   = File.join(Drive::ROOT_PATH, 'disks', 'context.disk')
		struct = Drive.parse_file(path).find { |expr| expr.is_a?(Disk::Struct_Expr) }
		refute_nil struct, 'expected a `Context <...>` struct declaration in disks/context.disk'
		struct.names.compact
	end

	def test_context_disk_lists_exactly_the_members_in_the_constant
		assert_equal Disk::Context::MEMBERS.keys.sort, context_disk_member_names.sort
	end

	def test_derived_lists_are_consistent
		# STACK_FUNCTIONS is a subset of FUNCTIONS.
		assert_empty Disk::Context::STACK_FUNCTIONS - Disk::Context::FUNCTIONS

		# A vital and a function are mutually exclusive; together they are every member.
		assert_empty Disk::Context::VITALS & Disk::Context::FUNCTIONS
		assert_equal Disk::Context::MEMBERS.keys.sort, (Disk::Context::VITALS + Disk::Context::FUNCTIONS).sort
	end
end
