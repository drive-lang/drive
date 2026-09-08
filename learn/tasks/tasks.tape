@load 'tapes/database'
@load 'tapes/table'
@load 'tapes/html'
@load 'tapes/server'

Task_Type [TODO BUG DESIGN]

# This struct represents the table columns for a single Task
Task <
	id: Primary_Key
	type: Task_Type
	done := false
	text: String
>


All_Tasks_Page | Div {
	tasks_table: Table

	html_id := 'tasks'
	input := Textarea()
	button := Button("Add Task")

	Self (tasks_table;
		self.tasks_table = tasks_table

		button.onclick = (;
			new_task := Task(text := input.value)
			tasks_table.create(new_task)
		)
	)


	render (;
		list := tasks_table.all().map((it;
			# An unset `type`/`done` reads back as its own declared type (Task_Type/Bool), not nil --
			# guard against that placeholder before displaying it.
			type_display := if it.type == Task_Type
				''
			else
				" -- `it.type`"
			end
			status := if it.done == true
				' (done)'
			else
				''
			end
			Li([A("/`it.id`", it.text), type_display, status])
		))

		Form([
			input,
			button,
			list
		])
	)
}


# `Option` has no `html_selected` of its own -- it needs a real declared member before it can be
# written from outside (Member Creation Is Strict), so this composes one and sets it during
# construction only when actually selected. Leaving it undeclared for the other options (rather than
# declaring it `false`) matters: a boolean HTML attribute is "on" just by being present, regardless of
# its string value, so a stray `selected="false"` would still mark that option selected.
Task_Type_Option | Option {
	Self ( label, selected := false;
		self.children = [label]
		self.html_selected := true if selected
	)
}

Single_Task_Page | Div {
	tasks_table: Table
	task: Task

	html_id := 'task' # without this, X-Drive-Target-Id never gets set and the client falls back to
		   # replacing the whole <html> document, which the browser refuses

	type_select: Select
	text_input: Textarea
	done_button := Button()
	save_button := Button("Save")

	Self (tasks_table, task_id: Number;
		self.tasks_table = tasks_table
		self.task   = tasks_table.find(task_id)

		# Both constructed here, not as bare fields above -- both need `task`, which only exists once
		# Self(;)'s own params are bound. Task_Type.keys (a plain Array value, not a method -- no `()`)
		# stays in sync with the enum's own declared members automatically, unlike a hardcoded list.
		self.type_select = Select(Task_Type.keys.map(( it; Task_Type_Option(it, it == task.type) )))

		# Passing task.text as the constructor arg renders it as the textarea's own inner text,
		# pre-filling it visibly (`.value` is a separate, browser-only thing the client JS reads at
		# submit time -- unrelated to what actually renders).
		self.text_input = Textarea(task.text)

		# `task.done` reads back as the plain Bool type itself (truthy!) for any task where `done` was
		# never explicitly set -- never check it bare, always normalize to a real true/false first.
		task.done = task.done == true
		done_button.children = [if task.done "Mark Not Done" else "Mark Done" end]

		done_button.onclick = (;
			task.done = !task.done
			tasks_table.update(task.id, <done := task.done>)
			done_button.children = [if task.done "Mark Not Done" else "Mark Done" end]
		)

		save_button.onclick = (;
			# type_select.value is the plain String the dropdown shows ("BUG"). Array has no
			# index-of-a-value method, so this walks Task_Type.keys/.values (parallel Arrays, same
			# order) with the loop's own `at` to recover the enum's actual member value.
			new_type := nil
			for Task_Type.keys
				if it == type_select.value
					new_type = Task_Type.values.get(at)
					stop
				end
			end

			# `new_type` stays a local, not `task.type` -- `type` is a Task_Type-typed struct member,
			# and assigning a mismatched value straight onto it trips the runtime type contract
			# (`task.type = new_type` raised "Type contract violation: expected Task_Type, got Symbol").
			# `task.text` has no such mismatch (both String), so that one's safe to update directly.
			task.text = text_input.value
			tasks_table.update(task.id, <type := new_type, text := task.text>)

			# type_select/text_input were built once, in Self(;), from the task as it was on page load --
			# updating the database alone doesn't change what they already rendered. Without rebuilding
			# them here too, the response sent back after Save would still show the old selection/text
			# for half a second, until the next full reload caught up.
			self.type_select = Select(Task_Type.keys.map(( it; Task_Type_Option(it, it == type_select.value) )))
			self.text_input  = Textarea(task.text)
		)
	)

	render (;
		[
			H1(task.text),
			Br(),
			type_select,
			text_input,
			Br(),
			done_button,
			save_button,
			A('/', 'Back to all')
		]
	)
}

Inverted_Html | Html {
	css_filter := 'invert()'
}

App | Server {
	DB := @connect Sqlite.local()
	tasks := DB.find_or_create_table(Task)

	# root path /
	get:// (;
		Inverted_Html(All_Tasks_Page(tasks))
	)

	get://:id (id;
		Inverted_Html(Single_Task_Page(tasks, id))
	)

	get://terminal (;
		Terminal_Canvas_Page() # the Html is in the component
	)
}


app := App()
@start_server app

My_Canvas | Canvas {
	html_id     := 'crt-screen'
	html_width  := '640'
	html_height := '480'
}

Cascadia_Font_Link | Link {
    html_rel  := 'stylesheet'
    html_href := 'https://cdn.jsdelivr.net/npm/@fontsource/cascadia-mono@5.0.1/index.css'
}

Terminal_Canvas_Page | Html {
    canvas := My_Canvas()
    draw_script := Script()

    html_id := 'canvas-container'
	css_background_color := '#051308'
    css_color := '#fff'

    Self (;
       draw_script.children = ["
          const canvas = document.getElementById('crt-screen');
          const ctx = canvas.getContext('2d');

          let inputBuffer = 'SYSTEM READY> ';
          let mouseX = 0, mouseY = 0;
          let cursorVisible = true;

          setInterval(() => { cursorVisible = !cursorVisible; draw(); }, 500);

          function draw() {
             ctx.fillStyle = '#051308';
             ctx.fillRect(0, 0, 640, 480);

             // Specified Cascadia Mono here
             ctx.fillStyle = '#33ff66';
             ctx.font = '20px \"Cascadia Mono\" monospace';

             const textToRender = inputBuffer + (cursorVisible ? '_' : ' ');
             ctx.fillText(textToRender, 30, 60);

             // Mouse Block Tracer
             ctx.fillStyle = 'rgba(51, 255, 102, 0.4)';
             ctx.fillRect(mouseX - 10, mouseY - 10, 20, 20);

             // Scanlines
             ctx.fillStyle = 'rgba(0, 0, 0, 0.25)';
             for (let y = 0; y < 480; y += 4) {
                ctx.fillRect(0, y, 640, 2);
             }
          }

          canvas.addEventListener('mousemove', (e) => {
             const rect = canvas.getBoundingClientRect();
             mouseX = e.clientX - rect.left;
             mouseY = e.clientY - rect.top;
             draw();
          });

          window.addEventListener('keydown', (e) => {
             if (e.key === 'Backspace') {
                inputBuffer = inputBuffer.slice(0, -1);
             } else if (e.key.length === 1) {
                inputBuffer += e.key;
             }
             draw();
          });

          // Wait for custom font payload to settle before rendering to canvas
          document.fonts.ready.then(() => {
             draw();
          });
       "]
    )

    render (;
        [Utf8_Meta(), Cascadia_Font_Link(), canvas, draw_script]
    )
}
