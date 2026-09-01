Request {
	path,
	method,
	query,
	params,
	headers,
	body,
}

Response {
	status,
	headers,
	body,

	redirect ( location; @ruby )
}


Server {
	port,

	new ( port := 8080;
		self.port = port
	)

	ok200 (;
		response.status = 200
		''
	)

	# note: The following routes prevent 500 errors since we're handling all routes here, nothing is filtered.
	# A literal route beats a `:param` one in #match_route, so these win over an app's own `get://:id`.
	get://favicon.ico ok200

	get://apple-touch-icon.png ok200

	get://apple-touch-icon-precomposed.png ok200
}
