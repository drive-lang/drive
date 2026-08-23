### Introduction

Every route body gets `request` and `response` for free, no parameter needed -- see learn/web_server.tape first if routes themselves are new. `request.body` is a Dictionary of submitted form fields.
###
@load 'lost/server.tape'

Camp | Server {
	new (;
		self.port = 8081
	)

	post://join (;
		name := request.body[:name]
		"Welcome, `name`"
	)
}


### response.status

Set it to change the HTTP status code of the reply.
###
Camp | Server {
	get://restricted (;
		response.status = 401
		'Not authorized'
	)
}


### response.headers

A Dictionary of outgoing headers -- set one by key.
###
Camp | Server {
	get://manifest (;
		response.headers['Content-Type'] = 'application/json'
		'{"supplies": ["water", "rope"]}'
	)
}


### response.redirect

Sends the client to a different path instead of returning a body directly.
###
Camp | Server {
	post://signal_fire (;
		response.redirect('/camp')
	)
}


### Putting it together

A typical POST handler checks the submitted body, then either redirects on success or sets a status and returns an error body on failure.
###
Camp | Server {
	post://register (;
		name := request.body[:name]

		if name
			response.redirect('/roster')
		else
			response.status = 400
			'Missing name'
		end
	)
}

camp := Camp()
@start_server camp
@stop_server camp
