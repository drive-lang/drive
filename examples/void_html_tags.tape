@load 'lost/html.tape'
@load 'lost/server.tape'

Inverted_Html | Html {
	css_filter := 'invert()'
}

App | Server {
	get:// (;
		Inverted_Html([P("Example with void HTML tags"), Hr(), Small('Expect that they don\'t have a closing /tag'), Br()])
	)
}

# @start_server App()
@puts "Uncomment '@start_server App()' above to run this example"
