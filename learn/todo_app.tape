### Introduction

A whole todo app on one page: SQLite for storage, one `Dom` component for the UI, and click
handlers that change the database and swap the page in place. No client-side framework -- `render(;)`
plus the built-in swap runtime do the work. Read learn/record_orm.tape and learn/html_elements.tape
first if the ORM or `Dom` are new.
###
@load 'lost/database'
@load 'lost/table'
@load 'lost/html'
@load 'lost/server'


### The schema Struct

One row per todo. `done` defaults to `false`; `Primary_Key` auto-increments.
###
Todo <
	id: Primary_Key
	text: String
	done := false
>


### Storage

`Sqlite.local('todos')` opens (creating it if needed) `temp/todos.db` -- a real file, so todos
survive restarts, unlike `Sqlite.memory()`. `find_or_create_table` hands back a table already wired
to the connection and the schema. This walkthrough clears the table on each run so its assertions
stay repeatable; a real app would just keep the data.
###
db := @connect Sqlite.local('todos')
db.delete_table!(:todos) if db.table_exists?(:todos)
todos := db.find_or_create_table(Todo)

todos.create(<text := 'Rebuild the raft'>)
boiled := todos.create(<text := 'Boil the water'>)
todos.update(boiled.id, <done := true>)

@assert todos.all().length() == 2, 'both todos are stored'
@assert todos.find(boiled.id).done == true, 'the second todo is marked done'


### The component

`Todo_App` composes `Div`, so it renders as `<div id="todo-app">`. `render(;)` returns the entire
page every time it runs. `visible(;)` is an ordinary method -- the view split into pieces, the same
way you would reach for components elsewhere.

Every button's `onclick` is a function that changes the database. After it runs, the swap runtime
re-renders `Todo_App` and replaces its `<div id="todo-app">` in place, so the list, the count, and
the filter links all update from one request.

The `map`/`filter` callbacks below are written with their own parens (`.filter(( it; ... ))`). The
spread form (`.filter(it; ...)`, learn/functions.tape) would read the same -- either is fine.
###
Todo_App | Div {
	html_id := 'todo-app'
	todos, filter, pending_delete,

	new ( todos, filter := nil;
		self.todos          = todos
		self.filter         = filter
		self.pending_delete = nil
	)

	visible (;
		if filter == 'active'
			todos.all().filter(( it; !it.done ))
		elif filter == 'completed'
			todos.all().filter(( it; it.done ))
		else
			todos.all()
		end
	)

	render (;
		remaining := todos.all().filter(( it; !it.done )).length()
		new_todo  := Textarea(key := 'new-todo')

		rows := self.visible().map(( todo;
			status := if todo.done 'Done' else 'Not done' end

			Li([
				Span(todo.text, html_title := status),
				Button('Toggle', key := "toggle-`todo.id`", onclick := (;
					todos.update(todo.id, <done := !todo.done>)
				)),
				Button('Delete', key := "delete-`todo.id`", onclick := (;
					self.pending_delete = todo.id
				))
			])
		))

		confirm_dialog := Dialog([
			P('Delete this todo?'),
			Button('Yes, delete', key := 'confirm-delete', onclick := (;
				todos.delete(pending_delete)
				self.pending_delete = nil
			)),
			Button('Cancel', key := 'cancel-delete', onclick := (;
				self.pending_delete = nil
			))
		], html_open := pending_delete != nil)

		[
			H1('Todos'),
			Form([
				new_todo,
				Button('Add', key := 'add', onclick := (;
					todos.create(<text := new_todo.value>)
				))
			]),
			Ul(rows),
			P("`remaining` item(s) left"),
			P([
				A('/', 'All'), Span(' | '),
				A('/?filter=active', 'Active'), Span(' | '),
				A('/?filter=completed', 'Completed')
			]),
			Button('Clear completed', key := 'clear', onclick := (;
				for todos.all().filter(( it; it.done ))
					todos.delete(it.id)
				end
			)),
			confirm_dialog
		]
	)
}


### Confirming a delete with `<dialog>`

"Delete" no longer deletes right away -- it sets `pending_delete` to that todo's own id, then a plain `self.pending_delete = todo.id` reassignment inside the onclick, resolved outward to the enclosing `Todo_App` instance the same way `total += n` already does in learn/html_elements.tape's own map-callback example.

`confirm_dialog`'s `html_open := pending_delete != nil` is the entire mechanism -- no client JS, no `.showModal()` call, just a real attribute driven by ordinary server-side state. The swap runtime does the rest: after any click, `Todo_App` re-renders, and the dialog's `open` attribute is simply whatever `pending_delete` says it should be that time. "Cancel" and "Yes, delete" both just clear `pending_delete`, one of them after actually deleting first.

Worth being precise about what this demonstrates: the plain `open` attribute is the *non-modal* form a `<dialog>` supports. The backdrop-and-focus-trapping modal behavior real `<dialog>` elements also offer only turns on through `.showModal()`, a method call with no attribute equivalent -- reaching that form would need real client-side JavaScript, which is deliberately outside what this walkthrough covers.
###


### A hover hint with `html_title`

Each row's `Span` carries `html_title := status`, where `status` is `'Done'` or `'Not done'`. That
renders as a real `title` attribute, so hovering the todo's text shows its status in the browser's
own native tooltip.

The Popover API (learn/html_elements.tape) can't do this job -- a popover only opens on a click or a
direct JS call, never on hover alone. `title` is the right native mechanism for a plain hover hint
like this one; a hover-triggered popover would need new client-side JavaScript, which is outside
what this walkthrough covers.
###


### key := "..." on the row buttons

Each row's buttons carry `key := "toggle-`todo.id`"`. The key pins that button's swap token to the
todo's own id, so toggling one row never disturbs another row's buttons even as the list is
filtered or reordered. Without a key the token would be positional instead (learn/html_elements.tape).
###
@assert Todo_App(todos).visible().length() == 2, 'with no filter, every todo is visible'
@assert Todo_App(todos, 'completed').visible().length() == 1, 'the completed filter shows only done todos'
@assert Todo_App(todos, 'active').visible().length() == 1, 'the active filter shows only the rest'


### Wiring it to a server

One route. `request.query[:filter]` is the `?filter=` value in the URL, so the filter links are
just ordinary page loads.

`Todo_App` composes `Div`, not `Html` -- its own rendered output is just `<div id="todo-app">...`,
with no `<html>`, `<head>`, or `<body>` anywhere in it. That matters more than it looks: the server
only injects `dom.js` (the click-handling script every onclick/swap in this file depends on) into a
response that already contains one of those three tags (see `interpreter.rb`'s own check for
`<html|<body|<head`). A bare `Div` response never matches, so the page would load, look right, and
silently do nothing on every click -- no error, since the script simply was never there to run.
Wrapping the route's own return value in `Html([Body([...])])` is enough; `Todo_App` itself doesn't
need to change.
###
App | Server {
	new (; self.port = 8090 )
	get:// (;
		Html([Body([Todo_App(todos, request.query[:filter])])])
	)
}

app := App()
@start_server app
@stop_server app


### Running it for real

Delete the `@stop_server` line and run `bin/lost <this-file>.tape`. Open `http://localhost:8090`:
add todos, toggle them done, delete them, filter the list. Edit the file and the server hot-reloads
(learn/web_server.tape). Your todos stay in `temp/todos.db` between runs.
###
