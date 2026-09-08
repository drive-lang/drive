require 'objspace'

module Tape
	class Context < Struct
		attr_accessor :subject

		# The single source of truth for every `@` member. `tapes/context.tape` is the human-readable
		# mirror -- its member list is asserted to match MEMBERS.keys (tests/context_test.rb).
		#   {}                 -- a reflective vital (computed onto each Context, not callable)
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
			super()
			@name    = 'Context'
			@subject = subject
		end
	end
end
