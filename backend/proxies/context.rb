require 'objspace'

module Prog
	# `@` resolves to a Context. Functions live on one shared Context (Interpreter#shared_context);
	# vitals are computed on demand (Interpreter#context_vital), never stored. A transient Context with
	# a `subject` is built only for a bare `@` / `@.foo`. Stays an Instance so `@ === Context` holds.
	class Context < Instance
		attr_accessor :subject

		# Source of truth for every `@` member; `frontend/context.prog` mirrors it (tests/context_test.rb).
		#   {} vital  |  { fn: :intrinsic } #interp_intrinsic  |  { fn: :stack } caller's-frame dispatch
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
