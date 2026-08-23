### Introduction

`lost/html.tape` isn't part of the default preload -- it needs an explicit `@load`. It declares one generic `Dom` type plus a predefined element for each common tag (`Div`, `P`, `H1`, `A`, ...), each just `Dom` composed with its own `html_element` tag name. Calling `.to_s()` renders an element (and its `children`) straight to an HTML string.
###
@load 'lost/html.tape'

sign := Div([P('Welcome to the beach')])
@assert sign.to_s() == '<div><p>Welcome to the beach</p></div>', 'to_s() should render the element and its children'


### Nesting and render(;)

A `Dom` type's `render(;)` returns what belongs inside its tag -- by default that's just `children`, but overriding it lets a type build its own inner structure instead of taking children at all.
###
Camp_Sign | Dom {
	message,

	new ( message;
		self.message = message
	)

	render (; P(message) )
}

@assert Camp_Sign('Do not drink the water').to_s() == '<div><p>Do not drink the water</p></div>', "a custom render(;) should replace children entirely"


### html_* and css_* prefixes

An `html_*` declaration becomes an HTML attribute (`html_class` -> `class`); a `css_*` declaration becomes an inline style property (`css_padding` -> `padding`). Both are just regular declarations underneath, readable like any other -- but they're only actually folded into attribute/style output by the server's own rendering pipeline when a `Dom` instance comes back from a route (see learn/web_server.tape). Calling `.to_s()` directly, like above, ignores them entirely and only wraps `children` in the tag.
###
Card | Div {
	css_padding := '1rem'
	css_background_color := '#f5deb3'
	html_class := 'card'
}

card := Card(P('Found supplies'))
@assert card.css_padding == '1rem', 'a css_* declaration should be readable directly, like any other member'
@assert card.html_class == 'card', 'an html_* declaration should be readable directly, like any other member'
@assert card.to_s() == '<div><p>Found supplies</p></div>', "to_s() should ignore html_*/css_* -- no class or style attribute here"
