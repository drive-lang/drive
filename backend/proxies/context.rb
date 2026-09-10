require 'objspace'

module Prog
	# `@` resolves to a Context. There is one shared Context (Interpreter#shared_context) holding the
	# `@` *functions* as real callable stand-ins -- built once, referenced everywhere. Its reflective
	# *vitals* (`@name`, `@types`, ...) are never stored: they're computed on demand against whatever
	# scope the `@` is reached from (Interpreter#context_vital). A transient Context is built only for a
	# bare `@` (alone, or `@.foo`), carrying that scope as its `subject`.
	#
	# Still an Instance (not a bare Scope) so `@ === Context` and `x.@` keep their type identity.
	class Context < Instance
		attr_accessor :subject

		# The single source of truth for every `@` member. `frontend/context.prog` is the human-readable
		# mirror -- its member list is asserted to match MEMBERS.keys (tests/context_test.rb).
		#   {}                 -- a reflective vital (computed on demand, never stored)
		#   { fn: :intrinsic } -- a function dispatched via Interpreter#interp_intrinsic
		#   { fn: :stack }     -- a function that runs in the caller's frame (#interp_context_stack_function)
		MEMBERS = {
			'name'          => {}, 'display_name' => {}, 'composed_types'      => {},
			'types'         => {}, 'type'         => {}, 'object_id'           => {},
			'size_in_bytes' => {}, 'root_path'    => {}, 'static_declarations' => {},
			'parameters'    => {}, 'arguments'    => {}, 'func_signature'      => {},
			'names'         => {}, 'type_names'   => {}, 'values'              => {},
			'members'       => {}, 'keys'         => {}, 'count'               => {},

			'to_s'         => { fn: :intrinsic }, 'puts'        => { fn: :intrinsic },
			'sleep'        => { fn: :intrinsic }, 'assert'      => { fn: :intrinsic },
			'refute'       => { fn: :intrinsic }, 'connect'     => { fn: :intrinsic },
			'start_server' => { fn: :intrinsic }, 'stop_server' => { fn: :intrinsic },

			'load'       => { fn: :stack }, 'declare'   => { fn: :stack },
			'push_scope' => { fn: :stack }, 'pop_scope' => { fn: :stack },

			# Unpack a scope's members into identifier lookup -- `@splat` also as a write target,
			# `@splatr` read-only, `@unsplat` removes it. (`Scope#add_{readable,writable}_scope`.)
			'splat'   => { fn: :stack },
			'splatr'  => { fn: :stack },
			'unsplat' => { fn: :stack },
		}.freeze

		FUNCTIONS       = MEMBERS.select { |_, m| m[:fn] }.keys.freeze
		STACK_FUNCTIONS = MEMBERS.select { |_, m| m[:fn] == :stack }.keys.freeze
		VITALS          = MEMBERS.reject { |_, m| m[:fn] }.keys.freeze

		def initialize subject = nil
			super('Context')
			@subject = subject
		end
	end
end
