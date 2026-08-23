# This app demonstrates using html fences (```html\n...```) to render html as opposed to Dom compositions. (see examples/todo_app.tape)
@load 'lost/server.tape'

App | Server {
	get:// home (;
		name := 'Cooper'
		```html
		<h1>Welcome to |name|'s webpage</h1>
		```
	)
}

# @start_server App()
@puts "Uncomment '@start_server App()' above to run this example"
