require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

# `backend/context.prog` is the human-readable mirror of Prog::Context::MEMBERS (see the note there).
# The two drift apart the moment someone adds a member to one and forgets the other -- exactly the
# bug that shipped `splatr`/`splatw` half-wired. Keep them locked together.
class Context_Test < Base_Test
	def context_CODE_member_names
		path   = File.join(Backend::ROOT_PATH, 'frontend', 'context.prog')
		struct = Backend.parse_file(path).find { |expr| expr.is_a?(Prog::Struct_Expr) }
		refute_nil struct, 'expected a `Context <...>` struct declaration in backend/context.prog'
		struct.names.compact
	end

	def test_context_CODE_lists_exactly_the_members_in_the_constant
		assert_equal Prog::Context::MEMBERS.keys.sort, context_CODE_member_names.sort
	end

	def test_derived_lists_are_consistent
		# STACK_FUNCTIONS is a subset of FUNCTIONS.
		assert_empty Prog::Context::STACK_FUNCTIONS - Prog::Context::FUNCTIONS

		# A vital and a function are mutually exclusive; together they are every member.
		assert_empty Prog::Context::VITALS & Prog::Context::FUNCTIONS
		assert_equal Prog::Context::MEMBERS.keys.sort, (Prog::Context::VITALS + Prog::Context::FUNCTIONS).sort
	end
end
