### Introduction

`tapes/server.tape` isn't loaded by default -- it needs an explicit `@load`. Compose a type with `Server` and give it a `port`; a route is a lowercase HTTP method followed by `://` and a path, and its body runs on every request to that path.
###
@load 'tapes/server.tape'

Camp | Server {
	Self (;
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

`@start_server` boots the server on a background thread and returns immediately, so the rest of the file keeps running right after it -- it's the interpreter itself that then waits on that thread once the whole file finishes, which is why a real Drive program just ends with `@start_server app` and leaves it running until interrupted. This walkthrough calls `@stop_server` right after so the file terminates on its own instead of waiting for a Ctrl+C.
###
camp := Camp()
@start_server camp
@stop_server camp


### Hot reload

Run a server file with `bin/drive <file>` and it keeps watching. Editing that file, or any `.tape` it loads, tears the server down, re-runs the whole program, and restarts it on the same port -- just refresh the page. Ctrl+C stops it. There is nothing to enable; it is how `bin/drive` runs any file that starts a server.
###


### request.body

Every route body gets `request` and `response` for free, no parameter needed. `request.body` is a Dictionary of submitted form fields.
###
Camp2 | Server {
	Self (; self.port = 8081 )

	post://join (;
		joiner_name := request.body[:name]
		"Welcome, `joiner_name`"
	)
}


### response.status

Set it to change the HTTP status code of the reply.
###
Camp2 | Server {
	get://restricted (;
		response.status = 401
		'Not authorized'
	)
}


### response.headers

A Dictionary of outgoing headers -- set one by key.
###
Camp2 | Server {
	get://manifest (;
		response.headers['Content-Type'] = 'application/json'
		'{"supplies": ["water", "rope"]}'
	)
}


### response.redirect

Sends the client to a different path instead of returning a body directly.
###
Camp2 | Server {
	post://signal_fire (;
		response.redirect('/camp')
	)
}


### Putting it together

A typical POST handler checks the submitted body, then either redirects on success or sets a status and returns an error body on failure.
###
Camp2 | Server {
	post://register (;
		registrant_name := request.body[:name]

		if registrant_name
			response.redirect('/roster')
		else
			response.status = 400
			'Missing name'
		end
	)
}

camp2 := Camp2()
@start_server camp2
@stop_server camp2
