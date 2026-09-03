# Builtin types I'm experimenting with, very much incomplete. Each of these should have an equivalent Lost::Type in ./src/runtime/scopes.rb

Any {
	to_s (; 'Any' )
}

# @load 'lost/table.tape' # lost/ is the stdlib found in ./lost/
# @load './this.tape'    # relative to wherever you ran bin/lost from (cwd)
# @load 'that.tape'      # relative to wherever you ran bin/lost from (cwd)
# @load 'and_this'      # no .tape extension required

@load 'lost/nil'
@load 'lost/file_system'
@load 'lost/date'
@load 'lost/time'
@load 'lost/date_time'
@load 'lost/number'
@load 'lost/array'
@load 'lost/dictionary'
@load 'lost/string'
@load 'lost/fence'
@load 'lost/struct'
@load 'lost/statement'
@load 'lost/enum'

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
