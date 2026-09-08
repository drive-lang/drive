require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Dom_Test < Base_Test
	# Runs `src`, returns [interpreter, rendered-html-of-the-result].
	def render src
		interp   = Drive::Interpreter.new
		instance = interp.run src
		[interp, interp.render_dom_to_html(instance)]
	end

	# Invokes a registered onclick handler the way a POST /onclick/<token> does, minus the HTTP layer.
	def fire interp, token
		route             = Disk::Route.new
		route.handler     = interp.dom_onclick_function_handlers.fetch(token)[:handler]
		route.param_names = []
		req = interp.build_disk_request "/onclick/#{token}", 'post', {}, {}, {}, {}
		res = interp.build_disk_response Struct.new(:status, :body).new
		interp.interp_route_body route, req, res
	end

	# --- #2  stable handler / input tokens ---

	def test_re_rendering_a_component_reuses_the_same_tokens
		interp, html1 = render <<~DISK
		    @load 'disks/html'
		    Panel | Div {
		    	html_id := 'panel'
		    	n := 0
		    	render (;
		    		b := Button("+")
		    		b.onclick = (; n += 1 )
		    		[b, Textarea()]
		    	)
		    }
		    Panel()
		DISK
		panel = interp.last_output
		html2 = interp.render_dom_to_html panel
		html3 = interp.render_dom_to_html panel

		assert_equal html1, html2
		assert_equal html2, html3
		assert_includes html1, 'data-drive-onclick="panel-0"'
		assert_includes html1, 'data-drive-id="panel-1"'
		assert_equal 1, interp.dom_onclick_function_handlers.size, 'handler map must not grow across re-renders'
		assert_equal 1, interp.dom_input_elements.size
	end

	def test_token_namespace_is_anchored_by_the_nearest_html_id
		_, html = render <<~DISK
		    @load 'disks/html'
		    Outer | Div {
		    	html_id := 'outer'
		    	render (; [Button("x", onclick := (; 1 )), Inner()] )
		    }
		    Inner | Div {
		    	html_id := 'inner'
		    	render (; [Button("y", onclick := (; 2 ))] )
		    }
		    Outer()
		DISK
		assert_includes html, 'data-drive-onclick="outer-0"'
		assert_includes html, 'data-drive-onclick="inner-0"'
	end

	def test_handler_defined_in_render_still_works_after_re_render
		interp, _ = render <<~DISK
		    @load 'disks/html'
		    Counter | Div {
		    	html_id := 'c'
		    	count := 0
		    	render (;
		    		plus := Button("+")
		    		plus.onclick = (; count += 1 )
		    		[H3("count: `count`"), plus]
		    	)
		    }
		    Counter()
		DISK
		counter = interp.last_output
		token   = interp.dom_onclick_function_handlers.keys.first

		3.times do
			fire interp, token
			interp.render_dom_to_html counter # re-render rebuilds the handler under the same token
		end

		assert_includes interp.render_dom_to_html(counter), 'count: 3'
	end

	def test_handler_in_a_map_callback_binds_to_the_component_and_keeps_its_closure
		# Two things this exercises: the component to re-render is recorded during the render walk (not
		# reconstructed from the handler's scope chain), and the callback keeps its closure through
		# `.map`, so its onclick can still reach a member of the enclosing component.
		interp, _ = render <<~DISK
		    @load 'disks/html'
		    List | Div {
		    	html_id := 'list'
		    	items := [1, 2, 3]
		    	total := 0
		    	render (;
		    		rows := items.map(( n;
		    			Li([Span("row `n`"), Button("x", key := "hit-`n`", onclick := (; total += n ))])
		    		))
		    		[Ul(rows), P("total: `total`")]
		    	)
		    }
		    List()
		DISK
		list  = interp.last_output
		entry = interp.dom_onclick_function_handlers.fetch('list-hit-2')

		assert_equal list.object_id, entry[:component].object_id, 'recorded component is the html_id-bearing List, not the Li and not nil'

		fire interp, 'list-hit-2'
		assert_includes interp.render_dom_to_html(list), 'total: 2', 'the handler reached `total` on the enclosing component through the map callback'
	end

	# --- key: ---

	def test_key_pins_the_token_and_does_not_consume_a_slot
		_, html = render <<~DISK
		    @load 'disks/html'
		    Page | Div {
		    	html_id := 'page'
		    	render (;
		    		[
		    			Button("a", key := 'first', onclick := (; 1 )),
		    			Button("b", onclick := (; 2 ))
		    		]
		    	)
		    }
		    Page()
		DISK
		assert_includes html, 'data-drive-onclick="page-first"'
		assert_includes html, 'data-drive-onclick="page-0"', 'the unkeyed sibling keeps slot 0 -- a key must not advance the counter'
	end

	# --- #3  Dom constructor named arguments (whitelisted) ---

	def test_constructor_sets_whitelisted_html_and_css_attrs
		_, html = render <<~DISK
		    @load 'disks/html'
		    Button("Save", html_id := 'save', html_class := 'primary', css_color := 'red')
		DISK
		assert_includes html, 'id="save"'
		assert_includes html, 'class="primary"'
		assert_includes html, 'style="color:red"'
		assert_includes html, '>Save<'
	end

	def test_constructor_onclick_registers_a_handler
		interp, html = render <<~DISK
		    @load 'disks/html'
		    Page | Div {
		    	html_id := 'p'
		    	n := 0
		    	render (; [Button("go", key := 'go', onclick := (; n += 1 ))] )
		    }
		    Page()
		DISK
		assert_includes html, 'data-drive-onclick="p-go"'
		refute_nil interp.dom_onclick_function_handlers['p-go']
	end

	def test_non_whitelisted_named_arg_on_a_dom_type_still_raises
		assert_raises Disk::Unknown_Named_Argument do
			Drive.interp "@load 'disks/html'\nButton(\"x\", bogus := 1)"
		end
	end

	def test_whitelisted_named_arg_on_a_non_dom_type_still_raises
		assert_raises Disk::Unknown_Named_Argument do
			Drive.interp "Widget { Self (; ) }\nWidget(html_id := 'x')"
		end
	end

	def test_a_declared_param_wins_over_the_prop_shortcut
		out = Drive.interp <<~DISK
		    @load 'disks/html'
		    Tag | Div {
		    	seen,
		    	Self ( key := nil; self.seen = key )
		    }
		    Tag(key := 'bound-to-param').seen
		DISK
		assert_equal 'bound-to-param', out
	end

	# --- renderer: nil/false attrs dropped, boolean attrs bare ---

	def test_unset_boolean_attr_is_not_rendered
		_, html = render <<~DISK
		    @load 'disks/html'
		    O | Option { html_selected: Bool }
		    O()
		DISK
		refute_includes html, 'selected'
	end

	def test_true_boolean_attr_renders_bare
		_, html = render <<~DISK
		    @load 'disks/html'
		    O | Option {
		    	html_selected: Bool
		    	Self (; self.html_selected = true )
		    }
		    O()
		DISK
		assert_includes html, '<option selected>'
		refute_includes html, 'selected="true"'
		refute_includes html, 'selected=""'
	end

	def test_false_and_nil_html_attrs_are_dropped
		_, html = render <<~DISK
		    @load 'disks/html'
		    D | Div {
		    	html_hidden := false
		    	html_title,
		    }
		    D()
		DISK
		refute_includes html, 'hidden'
		refute_includes html, 'title'
	end

	# --- Dialog / Popover ---

	def test_dialog_renders_with_a_closing_tag
		_, html = render <<~DISK
		    @load 'disks/html'
		    Dialog()
		DISK
		assert_includes html, '<dialog>'
		assert_includes html, '</dialog>'
	end

	def test_dialog_open_renders_bare
		_, html = render <<~DISK
		    @load 'disks/html'
		    Dialog(html_open := true)
		DISK
		assert_includes html, '<dialog open>'
		refute_includes html, 'open="true"'
	end

	def test_dialog_without_open_has_no_open_attr
		_, html = render <<~DISK
		    @load 'disks/html'
		    Dialog()
		DISK
		refute_includes html, 'open'
	end

	def test_popover_true_renders_bare_not_as_the_string_true
		_, html = render <<~DISK
		    @load 'disks/html'
		    Div(html_popover := true)
		DISK
		assert_includes html, '<div popover>'
		refute_includes html, 'popover="true"'
	end

	def test_popover_with_a_real_value_keeps_that_value
		_, html = render <<~DISK
		    @load 'disks/html'
		    Div(html_popover := 'manual')
		DISK
		assert_includes html, 'popover="manual"'
	end

	def test_popovertarget_has_no_hyphen
		_, html = render <<~DISK
		    @load 'disks/html'
		    Button("Open", html_popovertarget := 'my-dialog')
		DISK
		assert_includes html, 'popovertarget="my-dialog"'
		refute_includes html, 'popover-target'
	end

	def test_popovertargetaction_has_no_hyphen
		_, html = render <<~DISK
		    @load 'disks/html'
		    Button("Close", html_popovertargetaction := 'hide')
		DISK
		assert_includes html, 'popovertargetaction="hide"'
		refute_includes html, 'popover-target-action'
		refute_includes html, 'popovertarget-action'
	end
end
