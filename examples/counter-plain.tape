# Counter Example (Plain)
# A minimal example of reactive state with server-side re-rendering.

@load 'lost/html.tape'
@load 'lost/server.tape'

# Counter component with in-memory state
Counter | Div {
	html_id := 'counter'  # Target element for DOM updates
	button := Button("Increment Count!")
	count := 0  # State persists between clicks

	# Onclick handler - mutates state, triggers re-render
	increment := (;
		count += 1
	)

	# Called on page load and after each click
	render (;
		button.onclick = increment  # Register handler with runtime
		[H2("The count is: `count`"), Form(button)]
	)
}

# Server with a single route
App | Server {
	counter := Counter()
	get:// home (;
		Html(counter)
	)
}

# Start the server
# @start_server App()
@puts "Uncomment '@start_server App()' above to run this example"
