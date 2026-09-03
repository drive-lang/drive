require 'minitest/autorun'
require 'weakref'
require_relative '../src/tape'
require_relative 'base_test'

class Scopes_Test < Base_Test
	SHARED_VEC2 = "Vec2 { x:=0, y:=0, new ( x,y; self.x=x, self.y=y ) }".freeze

	def test_declaring_new_inside_pushed_scope
		out = Tape.interp <<-CODE
			Vec2 { x := 0, y := 0 }
			# Vec2 intentionally doesn't declare new(;)

			@push_scope Vec2
			new ( x := 0, y := 0;
				self.x=x, self.y=y
			)
			@pop_scope Vec2

			Vec2()
		CODE
		assert_kind_of Tape::Instance, out
		assert_equal 'Vec2', out.name
	end

	def test_basic_pushing_and_popping
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			@push_scope Vec2
			ZERO := Vec2(0,0)
			@pop_scope Vec2

			Vec2.ZERO
		CODE
		assert_kind_of Tape::Instance, out
		assert_equal 'Vec2', out.name
		assert_equal [0, 0], [out.get(:x), out.get(:y)]
	end

	def test_writable_scopes_with_long_form
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			double ( @add_writable_scope v: Vec2 -> Vec2;
				v.x *= 2
				y *= 2
				v
			)

			double(Vec2(4, 8))
		CODE
		assert_equal [8, 16], [out.get(:x), out.get(:y)]
	end

	def test_writable_scopes_with_add_medium_form
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			double ( @add_writable v -> Vec2;
				x *= 2
				v.y *= 2
				v
			)

			double(Vec2(15, 16))
		CODE
		assert_equal [30, 32], [out.get(:x), out.get(:y)]
	end

	def test_writable_scopes_with_add_short_form
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			double ( @writable v -> Vec2;
				x *= 2
				v.y *= 2
				v
			)

			double(Vec2(15, 16))
		CODE
		assert_equal [30, 32], [out.get(:x), out.get(:y)]
	end

	def test_pop_scope_with_nothing_pushed_raises
		# No dedicated Tape:: error -- pop_scope refuses to pop the last remaining scope, so the identity check fails.
		assert_raises RuntimeError do
			Tape.interp <<-CODE
				#{SHARED_VEC2}
				@pop_scope Vec2
			CODE
		end
	end

	def test_pop_scope_without_target_raises_invalid_directive_usage
		assert_raises Tape::Invalid_Directive_Usage do
			Tape.interp <<-CODE
				#{SHARED_VEC2}
				@push_scope Vec2
				@pop_scope
			CODE
		end
	end

	def test_pushing_the_same_scope_twice_requires_popping_twice
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			@push_scope Vec2
			@push_scope Vec2
			@pop_scope Vec2
			STILL_INSIDE := 1   # only one of the two pushes has been undone -- still lands on Vec2, not global

			Vec2.STILL_INSIDE
		CODE
		assert_equal 1, out
	end

	def test_popping_a_doubly_pushed_scope_the_right_number_of_times_fully_exits
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp <<-CODE
				#{SHARED_VEC2}

				@push_scope Vec2
				@push_scope Vec2
				@pop_scope Vec2
				@pop_scope Vec2
				NOW_OUTSIDE := 1   # both pushes undone -- lands on global, not Vec2

				Vec2.NOW_OUTSIDE
			CODE
		end
	end

	def test_adding_the_same_instance_to_readable_scope_twice_does_not_duplicate
		# Delta, not absolute count -- Global's readable_scopes always holds the stdlib's own Scope too.
		interpreter = Tape::Interpreter.new
		interpreter.run <<-CODE
			#{SHARED_VEC2}

			v := Vec2(1, 2)
			@add_readable_scope v
		CODE
		after_one_add = interpreter.stack.last.readable_scopes.size

		interpreter.run '@add_readable_scope v'
		after_two_adds = interpreter.stack.last.readable_scopes.size

		assert_equal after_one_add, after_two_adds
	end

	def test_adding_the_same_instance_to_writable_scope_twice_does_not_duplicate
		interpreter = Tape::Interpreter.new
		interpreter.run <<-CODE
			#{SHARED_VEC2}

			v := Vec2(1, 2)
			@add_writable_scope v
			@add_writable_scope v
		CODE
		assert_equal 1, interpreter.stack.last.writable_scopes.size
	end

	def test_removing_readable_scope_twice_is_a_safe_no_op
		refute_raises do
			Tape.interp <<-CODE
				#{SHARED_VEC2}

				v := Vec2(1, 2)
				@add_readable_scope v
				@remove_readable_scope v
				@remove_readable_scope v
			CODE
		end
	end

	def test_removing_writable_scope_twice_is_a_safe_no_op
		refute_raises do
			Tape.interp <<-CODE
				#{SHARED_VEC2}

				v := Vec2(1, 2)
				@add_writable_scope v
				@remove_writable_scope v
				@remove_writable_scope v
			CODE
		end
	end

	def test_removing_a_never_added_scope_is_a_safe_no_op
		refute_raises do
			Tape.interp <<-CODE
				#{SHARED_VEC2}

				v := Vec2(1, 2)
				@remove_readable_scope v
				@remove_writable_scope v
			CODE
		end
	end

	def test_popping_a_scope_does_not_remove_it_from_readable_or_writable_scopes
		# @push_scope/@pop_scope and @add_readable_scope/@add_writable_scope are independent -- popping doesn't touch readable/writable membership.
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			v := Vec2(9, 9)
			@add_readable_scope v

			@push_scope v
			@pop_scope v

			x
		CODE
		assert_equal 9, out
	end

	def test_readable_scope_membership_does_not_keep_an_instance_alive_on_its_own
		# WeakMap, not Set -- membership alone shouldn't keep an instance alive. `interpreter` is kept alive on purpose so Global dying doesn't confound the result.
		interpreter, ref = _build_interpreter_with_orphaned_readable_instance
		GC.start(full_mark: true, immediate_sweep: true) # a plain GC.start doesn't reliably force an immediate sweep
		GC.start(full_mark: true, immediate_sweep: true)
		refute ref.weakref_alive?, 'expected the instance to be collectible even though readable_scopes alone still "contains" it'
		refute_nil interpreter # keeps interpreter (and Global) reachable through the assertion above
	end

	def test_own_declaration_wins_over_writable_and_readable_collision_on_read
		# The bug that drove [self, writable, readable] ordering -- own declaration must win over both fallbacks.
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			x := 100
			w := Vec2(1, 1)
			r := Vec2(2, 2)
			@add_writable_scope w
			@add_readable_scope r
			x
		CODE
		assert_equal 100, out
	end

	def test_own_declaration_wins_over_writable_and_readable_collision_on_write
		# Write version: must land on the own declaration, never redirect through the writable scope.
		out = Tape.interp <<-CODE
			#{SHARED_VEC2}

			x := 100
			w := Vec2(1, 1)
			r := Vec2(2, 2)
			@add_writable_scope w
			@add_readable_scope r
			x = 999
			(x, w.x)
		CODE
		assert_equal [999, 1], out.values
	end

	def test_add_readable_and_writable_scope_with_non_scope_argument_wraps_arg_with_maybe_instance
		refute_raises Tape::Invalid_Scope_Directive_Argument do
			Tape.interp '@add_readable_scope 4'
		end

		refute_raises Tape::Invalid_Scope_Directive_Argument do
			Tape.interp "@add_writable_scope 'eight'"
		end
	end

	def test_add_readable_scope_with_nil_argument_is_silently_accepted
		# Gap in the falsy-guard: maybe_instance(nil) -> a Tape::Nil instance, Ruby-truthy, so the guard never fires. Documents current behavior, not a verdict.
		refute_raises Tape::Invalid_Directive_Usage do
			Tape.interp '@add_readable_scope nil'
		end
	end

	def test_add_readable_scope_with_false_argument_is_silently_accepted
		# Same gap, for false -- maybe_instance(false) => Bool::FALSE, also Ruby-truthy.
		refute_raises Tape::Invalid_Directive_Usage do
			Tape.interp '@add_readable_scope false'
		end
	end

	def test_add_writable_scope_with_nil_and_false_arguments_are_silently_accepted
		refute_raises Tape::Invalid_Directive_Usage do
			Tape.interp '@add_writable_scope nil'
		end

		refute_raises Tape::Invalid_Directive_Usage do
			Tape.interp '@add_writable_scope false'
		end
	end

	def test_an_undeclared_identifier_argument_still_raises_undeclared_identifier
		# Contrast: a real typo still raises -- that check happens in #interpret, before maybe_instance ever runs.
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp '@add_readable_scope this_was_never_declared'
		end
	end

	def test_writable_scope_membership_does_not_keep_an_instance_alive_on_its_own
		# Mirrors the readable-scope version -- separate WeakMap, needs its own proof, not provable by symmetry.
		interpreter, ref = _build_interpreter_with_orphaned_writable_instance
		GC.start(full_mark: true, immediate_sweep: true)
		GC.start(full_mark: true, immediate_sweep: true)
		refute ref.weakref_alive?, 'expected the instance to be collectible even though writable_scopes alone still "contains" it'
		refute_nil interpreter # keeps interpreter (and Global) reachable through the assertion above
	end

	def test_readable_short_form_as_bare_manual_directive
		# @readable/@writable also work as bare directives, not just inside a param list.
		out = Tape.interp <<-CODE
			Island { name := 'unknown', }
			island := Island()
			island.name = 'The Island'
			@readable island
			name
		CODE
		assert_equal 'The Island', out
	end

	def test_writable_short_form_as_bare_manual_directive
		out = Tape.interp <<-CODE
			Raft { length := 0 }
			r := Raft()
			r.length = 12
			@writable r
			length = 99
			r.length
		CODE
		assert_equal 99, out
	end

	def test_standard_library_is_reachable_but_not_a_global_own_declaration
		interpreter = Tape::Interpreter.new
		interpreter.run 'nil'
		global = interpreter.stack.first

		refute global.declarations.key?('Array'), 'expected Array to not be one of Global\'s own declarations'
		assert global.has?('Array'), 'expected Array to still resolve, via the readable-scope fallback'
	end

	def test_standard_library_scope_is_named_standard_library_and_is_globals_only_readable_scope_entry_by_default
		interpreter = Tape::Interpreter.new
		interpreter.run 'nil'
		global = interpreter.stack.first

		assert_equal 1, global.readable_scopes.size
		assert_equal 'Standard_Library', global.readable_scopes.keys.first.name
	end

	def test_composing_a_builtin_type_still_works
		out = Tape.interp <<-CODE
			Mine | Array { extra := true }
			m := Mine([1, 2, 3])
			(m.length(), m.extra)
		CODE
		assert_equal [3, true], out.values
	end

	def test_deliberately_reopening_a_builtin_type_via_push_scope_still_mutates_the_real_shared_type
		out = Tape.interp <<-CODE
			@push_scope Array
			greet (; 'hi from array' )
			@pop_scope Array

			[1, 2, 3].greet()
		CODE
		assert_equal 'hi from array', out
	end

	def test_nested_scopes_readable_scope_shadows_an_outer_readable_scope_when_both_have_the_name
		# Resolution continues outward through the stack when a level's own chain is empty. Both levels have it here, so inner wins first.
		out = Tape.interp <<-CODE
			Marker { val := 0 }

			outer (;
				o := Marker()
				o.val = 1
				@add_readable_scope o

				inner (;
					i := Marker()
					i.val = 2
					@add_readable_scope i
					val
				)

				inner()
			)
			outer()
		CODE
		assert_equal 2, out
	end

	def test_nested_scopes_fall_through_an_inner_readable_scope_that_has_unrelated_content
		# Sharper case: inner scope's chain has *something*, just not this name -- proves the search doesn't stop early.
		out = Tape.interp <<-CODE
			Marker { val := 0 }
			Other { unrelated := 99 }

			outer (;
				o := Marker()
				o.val = 5
				@add_readable_scope o

				inner (;
					x := Other()
					@add_readable_scope x
					val
				)

				inner()
			)
			outer()
		CODE
		assert_equal 5, out
	end

	def test_nested_scopes_fall_through_an_inner_writable_scope_that_has_unrelated_content
		# Same as above, but the inner scope's non-matching addition is writable instead of readable.
		out = Tape.interp <<-CODE
			Marker { val := 0 }
			Other { unrelated := 99 }

			outer (;
				o := Marker()
				o.val = 7
				@add_readable_scope o

				inner (;
					x := Other()
					@add_writable_scope x
					val
				)

				inner()
			)
			outer()
		CODE
		assert_equal 7, out
	end

	def test_push_scope_a_function_is_rejected_at_push_time
		# Used to succeed silently, then fail confusingly on pop -- Func is duped on every lookup (#rebind_func_to_scope), so identity can never match. Now rejected immediately, on push.
		assert_raises Tape::Invalid_Scope_Directive_Argument do
			Tape.interp <<-CODE
				funk (; 1 )
				@push_scope funk
			CODE
		end
	end

	def test_push_scope_a_bare_literal_is_rejected_at_push_time
		# Number passes the Func-rejecting Type check, but maybe_instance builds a fresh object every call -- identity can never match. Target must now be a bare identifier naming something already bound.
		assert_raises Tape::Invalid_Scope_Directive_Argument do
			Tape.interp '@push_scope 4'
		end
	end

	def test_push_scope_an_explicit_constructor_call_is_rejected_at_push_time
		# Same fix, different freshness source: a constructor call builds a new instance every run too.
		assert_raises Tape::Invalid_Scope_Directive_Argument do
			Tape.interp '@push_scope Number(4)'
		end
	end

	private

	# Isolates readable_scopes as the only thing keeping the instance alive. Trailing `nil` matters -- otherwise `wm[x] = x`'s return value would land in Interpreter#last_output, a stray strong reference.
	def _build_interpreter_with_orphaned_readable_instance
		interpreter = Tape::Interpreter.new
		interpreter.run <<-CODE
			#{SHARED_VEC2}

			v := Vec2(1, 2)
			@add_readable_scope v
			nil
		CODE
		# `.keys.first` (not `v` directly) -- Global's readable_scopes also holds the stdlib's own Scope, which #Interpreter now deliberately keeps alive with a real strong reference of its own (see #run), so it's always present here too. Read `v`'s value straight out of `declarations` instead of trusting WeakMap key order to land on the right one.
		instance = interpreter.stack.last.declarations['v']
		ref      = WeakRef.new(instance)
		interpreter.stack.last.declarations.delete('v')
		instance = nil
		[interpreter, ref]
	end

	# Same as the readable-scope version above, for writable_scopes.
	def _build_interpreter_with_orphaned_writable_instance
		interpreter = Tape::Interpreter.new
		interpreter.run <<-CODE
			#{SHARED_VEC2}

			v := Vec2(1, 2)
			@add_writable_scope v
			nil
		CODE
		instance = interpreter.stack.last.writable_scopes.keys.first
		ref      = WeakRef.new(instance)
		interpreter.stack.last.declarations.delete('v')
		instance = nil
		[interpreter, ref]
	end
end
