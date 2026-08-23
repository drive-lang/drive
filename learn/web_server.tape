### Introduction

`lost/server.tape` isn't part of the default preload -- it needs an explicit `@load`. Compose a type with `Server` and give it a `port`; a route is a lowercase HTTP method followed by `://` and a path, and its body runs on every request to that path.
###
@load 'lost/server.tape'

Camp | Server {
	new (;
		self.port = 8080 # port is declared by Server, you're only setting it here
		# Even this initializer is declared on Server, and takes the port as input. This is just to illustrate.
	)

	get:// (;
		'Beach camp'
	)
}


### Every HTTP method is a route prefix

`get://`, `post://`, `put://`, `delete://`, `patch://` -- same shape, different verb.
###
Camp | Server {
	post://survivors (;
		'Recorded a new survivor'
	)

	put://survivors/:name ( name;
		"Updated `name`"
	)

	delete://survivors/:name ( name;
		"Removed `name`"
	)

	patch://survivors/:name ( name;
		"Patched `name`"
	)
}


### URL parameters

A `:name` segment in the path is bound to a same-named parameter in the route's own argument list.
###
Camp | Server {
	get://survivors/:name ( name;
		"Survivor: `name`"
	)
}


### Query strings

`request.query` is a Dictionary of everything after the `?` in the URL -- `/search?q=flare` makes `request.query[:q]` equal `'flare'`.
###
Camp | Server {
	get://search (;
		term := request.query[:q]
		"Searching supplies for `term`"
	)
}


### @start_server

`@start_server` boots the server on a background thread and returns immediately, so the rest of the file keeps running right after it -- it's the interpreter itself that then waits on that thread once the whole file finishes, which is why a real Lost program just ends with `@start_server app` and leaves it running until interrupted. This walkthrough calls `@stop_server` right after so the file terminates on its own instead of waiting for a Ctrl+C.
###
camp := Camp()
@start_server camp
@stop_server camp
