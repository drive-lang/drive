# Builtin types I'm experimenting with, very much incomplete. Each of these should have an equivalent Tape::Type in ./src/runtime/scopes.rb

Any {
	to_s (; 'Any' )
}

# @load 'tapes/table.tape' # tapes/ is the stdlib found in ./tapes/
# @load './this.tape'    # relative to wherever you ran bin/tape from (cwd)
# @load 'that.tape'      # relative to wherever you ran bin/tape from (cwd)
# @load 'and_this'      # no .tape extension required

@load 'tapes/nil'
@load 'tapes/file_system'
@load 'tapes/date'
@load 'tapes/time'
@load 'tapes/date_time'
@load 'tapes/number'
@load 'tapes/array'
@load 'tapes/dictionary'
@load 'tapes/string'
@load 'tapes/fence'
@load 'tapes/struct'
@load 'tapes/statement'
@load 'tapes/enum'

Range {}

Tuple {
	values,

	to_s (;
		pieces := values.map((it; if it === String
			it.pretty_print()
		else
			"`it`"
		end ))
		"(`pieces.join(', ')`)"
	)
}

Bool {
	truthiness,

	# todo: Think about what else might make a boolean true
	new ( value := true;
		self.truthiness = value != false and value != nil and value != 0 and value != 0.0
	)

	# note; Not `"`truthiness`"` because interpolating truthiness (a raw Ruby true/false) wouldre-wrap it via maybe_instance back into this exact Bool singleton and call .to_s again,infinitely. Branching avoids ever stringifying truthiness itself.
	# todo;
	to_s (;
		if truthiness
			"true"
		else
			"false"
		end
	)
}
