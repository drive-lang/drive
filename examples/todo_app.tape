@load 'lost/html.tape'
@load 'lost/database.tape'
@load 'lost/Table.tape'
@load 'lost/server.tape'

### Page components ###
Page_Layout | Html {
	css_filter := 'invert()'
	css_font_size := '1.6em'
	css_font_family := 'monospace'
	css_padding := '3.2em'

	render (;
		[Head(Title("Tasks")), Body(children)]
	)
}

Single_Task | Div {
	task,

	new ( task := 'New Task';
		self.task = task
	)

	render (;
		[A('/', 'Back to all'), P("`id`: `task[:text]`")]
	)
}

Task_Item | Li {
	id,
	text,

	new ( task;
		self.text = task[:text]
		self.id   = task.id
	)

	render (;
		A("/`id`", "`id`: `text`")
	)
}

List_Of_Tasks | Ul {
	tasks,

	new ( tasks := [];
		self.tasks = tasks
	)

	render (;
		tasks.map(( it, at;
			Task_Item(it)
		))
	)
}

New_Task_Form | Form {
	html_action := '/new'
	html_method := 'POST'

	render (;
		[
			Label('Add a new task:'),
			Br(),
			Input_Field(),
			Br(),
			Submit_Button()
		]
	)
}

Input_Field | Textarea {
	html_type := 'text'
	html_name := 'task'
	html_placeholder := 'Enter task text...'
}

Submit_Button | Button {
	html_type := 'submit'

	render (; 'Add Task' )
}

### Database ###
db := Sqlite('./temp/task_app.db') # Sqlite composes with Database

# db = @connect Sqlite(...) is also valid
@connect db  # => calls Database#create_connection!

Task | Table {
	Self.database := ~/db # Must set the database in order for Task query methods to work
	table_name := 'tasks'
}

Tasks_Schema <
	id: Primary_Key
	text: String
>

if db.table_exists?('tasks')
	db.delete_table('tasks')
	db.create_table('tasks', Tasks_Schema)
else
	db.create_table('tasks', Tasks_Schema)
end

Task.create({text: "Make Databases work"})
Task.create({text: "Allow reading and writing Tables"})
Task.create({text: "Show Tasks in this app"})
Task.create({text: "Implement user authentication"})
Task.create({text: "Add dark mode toggle"})
Task.create({text: "Write comprehensive documentation"})
Task.create({text: "Optimize database queries"})
Task.create({text: "Add file upload feature"})
Task.create({text: "Create RESTful API endpoints"})
Task.create({text: "Build admin dashboard"})

### Server ###
Tasks_Controller {
	Self.home (;
		tasks := Task.all()
		Page_Layout([
			H2('My Tasks'),
			New_Task_Form(),
			Hr(),
			List_Of_Tasks(tasks)
		])
	)

	Self.create_task (;
		created := Task.create({text: request.body.task })
		# You can call response.redirect("/") to manually set the destination, or call the named route functions:
		# home()
		get_task(created.id)
	)

	get_task ( id;
		task := Task.find(id.to_i())
		Page_Layout(Single_Task(task))
	)
}

App | Server | Tasks_Controller {
	port := 8080

	controller := Tasks_Controller()

	get:// controller.home # to controller instance

	get://:id get_task # to composed get_task

	post://new Tasks_Controller.create_task # to static controller

	# note: The following routes prevent 500 errors since we're handling all routes here, nothing is filtered.
	get://favicon.ico (;
		response.status = 404
		''
	)

	get://apple-touch-icon-precomposed.png (;
		response.status = 404
		''
	)
}

app := App()

# @start_server app
@puts "Uncomment '@start_server app' above to run this example"
