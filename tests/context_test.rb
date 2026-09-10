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

	# ### architecture: one shared function Context, on-demand vitals, no per-scope caching ###

	def interpreter_after code
		Backend::Interpreter.new.tap { |i| i.run(code) }
	end

	def test_there_is_one_shared_function_context
		i = interpreter_after 'x := 1'
		assert_same i.send(:shared_context), i.send(:shared_context)
		assert_equal Prog::Context::FUNCTIONS.sort, i.send(:shared_context).declarations.keys.sort
	end

	def test_no_context_is_cached_on_a_scope
		refute_includes Prog::Scope.instance_methods, :context, '`Scope#context` should be gone -- nothing is cached per scope now'

		i = interpreter_after 'x := 1'
		refute_same i.send(:context_for, i.global), i.send(:context_for, i.global),
			'#context_for builds a fresh transient Context each call -- it is not cached'
	end

	def test_a_vital_is_computed_live_not_snapshotted
		i = interpreter_after 'x := 1'
		assert_equal 'Global', i.send(:context_vital, 'name', i.global)

		i.global.name = 'Renamed'
		assert_equal 'Renamed', i.send(:context_vital, 'name', i.global),
			'a vital reads the scope live on every access -- the old code snapshotted it on first `@` use'
	end

	def test_a_vital_that_does_not_apply_to_the_scope_kind_is_nil
		i = interpreter_after 'x := 1'
		assert_nil i.send(:context_vital, 'keys', i.global)  # `keys` is Enum-only
		assert_nil i.send(:context_vital, 'names', i.global) # `names` is Struct-only
	end

	def test_bind_context_func_hands_out_a_bound_callable_stand_in
		i    = interpreter_after 'x := 1'
		func = i.send(:bind_context_func, 'to_s', i.global)

		assert_equal 'to_s', func.context_function_name
		assert_same i.global, func.enclosing_scope
		refute_same i.send(:shared_context)['to_s'], func, 'the shared stand-in stays subject-free -- bind returns a dup'
	end
end
