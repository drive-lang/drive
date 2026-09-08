### Introduction

`tapes/html.tape` isn't loaded by default -- it needs an explicit `@load`. It declares one generic `Dom` type plus a predefined element for each common tag (`Div`, `P`, `H1`, `A`, ...), each just `Dom` composed with its own `html_element` tag name. Calling `.to_s()` renders an element (and its `children`) straight to an HTML string.
###
@load 'tapes/html.tape'

sign := Div([P('Welcome to the beach')])
@assert sign.to_s() == '<div><p>Welcome to the beach</p></div>', 'to_s() should render the element and its children'


### Nesting and render(;)

A `Dom` type's `render(;)` returns what belongs inside its tag -- by default that's just `children`, but overriding it lets a type build its own inner structure instead of taking children at all.
###
Camp_Sign | Dom {
	message,

	Self ( message;
		self.message = message
	)

	render (; P(message) )
}

@assert Camp_Sign('Do not drink the water').to_s() == '<div><p>Do not drink the water</p></div>', "a custom render(;) should replace children entirely"


### html_* and css_* prefixes

An `html_*` declaration becomes an HTML attribute (`html_class` -> `class`); a `css_*` declaration becomes an inline style property (`css_padding` -> `padding`). Both are just regular declarations underneath, readable like any other -- but they're only actually folded into attribute/style output by the server's own rendering pipeline when a `Dom` instance comes back from a route (see learn/web_servers.tape). Calling `.to_s()` directly, like above, ignores them entirely and only wraps `children` in the tag.
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


### Setting attributes at construction

A Dom element's constructor also accepts `html_*`, `css_*`, `onclick`, and `key` as named arguments (learn/named_arguments.tape) and sets them straight onto the instance -- no subclass and no separate assignment. Only those names are accepted, and only on Dom types; anything else raises `Tape::Unknown_Named_Argument`.
###
tent := Div([P('Shelter')], html_class := 'tent', css_border := '1px solid')
@assert tent.html_class == 'tent', 'a Dom constructor should accept html_* as a named argument'
@assert tent.css_border == '1px solid', 'a Dom constructor should accept css_* as a named argument'
@assert tent.to_s() == '<div><p>Shelter</p></div>', 'to_s() still ignores html_*/css_*, same as when they are declared in the body'

flare := Button('Signal', key := 'flare', onclick := (; 'lit' ))
@assert flare.onclick() == 'lit', 'onclick passed at construction is a real callable function'


### CSS anchor positioning

CSS anchor positioning needs no new Drive-side plumbing at all -- it's plain CSS, expressed with the same `css_*` prefix already covered above. One element (the anchor) names itself; another element (the one being positioned) points back at that name and describes its position relative to it, using the `anchor()` function inside an ordinary property value.

A common pairing is a Popover-API element (`html_popover`) positioned next to whatever triggered it -- the popover shows/hides itself, and anchor positioning places it. Neither needs the other, but they're built for exactly this combination.
###
Trigger | Button {
	css_anchor_name := '--menu-trigger'
	html_popovertarget := 'menu'
}

Menu | Div {
	html_id := 'menu'
	html_popover := 'auto'
	css_position := 'absolute'
	css_position_anchor := '--menu-trigger'
	css_top := 'anchor(bottom)'
	css_left := 'anchor(left)'
}

trigger := Trigger('Open menu')
menu     := Menu()
@assert trigger.css_anchor_name == '--menu-trigger', 'the anchor names itself with a custom-ident value'
@assert menu.css_position_anchor == '--menu-trigger', 'the positioned element points back at that same name'
@assert menu.css_top == 'anchor(bottom)', 'anchor() reads as a plain string -- Drive never needs to parse what is inside it'

Close | Button {
	html_popovertarget := 'menu'
	html_popovertargetaction := 'hide'
}

close := Close('Close')
@assert close.html_popovertarget == 'menu', 'popovertarget names which popover this button controls'
@assert close.html_popovertargetaction == 'hide', 'popovertargetaction picks the action -- "show", "hide", or "toggle"'


### The `:has()` selector

`:has()` is a real CSS selector, not a single element's style property, so it can't go through `css_*` the way `anchor()` did -- a selector rule needs a `<style>` tag of its own, holding plain CSS text. `Dom` is directly usable for that: `html_element` was already settable on any Dom instance (see "Setting attributes at construction" above), and `Dom`'s own constructor already accepts a plain string as its content -- so a `<style>` tag needs no new type, no fence, nothing beyond what this file has already covered.
###
style := Style('li:has(input:checked) { text-decoration: line-through; }')
@assert style.to_s() == '<style>li:has(input:checked) { text-decoration: line-through; }</style>', 'a raw CSS rule, unparsed, wrapped in a real <style> tag'
