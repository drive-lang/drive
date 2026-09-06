# Struct-and-render take on tapes/html.tape, same spirit as tapes/css.tape: markup is plain,
# immutable data (one struct shape for every element), and a single Renderer walks it -- no per-tag
# Type, no `| Dom` composition, no method-override polymorphism. The two coexist; this one doesn't
# hook into the server-side rendering pipeline (route responses, onclick wiring, dom.js) the way
# tapes/html.tape's Dom types do -- it only builds an HTML string.

@load 'tapes/visitor'
@load 'tapes/css'

# -----------------------------------------------------------------------------
# 1. The one node shape
# -----------------------------------------------------------------------------

# One HTML attribute -- mirrors css.tape's `Property <name, value>` exactly, same reason: a plain
# name/value struct instead of a Dictionary entry, so attributes list/reorder/duplicate the same way
# css declarations do (see Html_Lint_Visitor's duplicate-attribute check below, impossible on a
# Dictionary but a real risk now that attributes are an ordered Array).
Attribute <name: String, value: Any>

# `children` holds a mix of Element structs and plain Strings (text nodes) -- Html_Renderer tells
# them apart by `=== Element`, same as css.tape's visitors tell rule kinds apart by `=== Style_Rule`.
# `attributes` is an ordered Array\Attribute, not a Dictionary -- same reasoning as `css` below: build
# it with the same struct-literal style css.tape declarations already use (`Attribute("class", "card")`).
# `css` is a real css.tape rule tree (`Css`'s own union -- Style_Css/At_Css/Scope_Css/...), not a
# flat Dictionary of properties -- see Html_Formatter_Visitor#render_element, which renders it as an
# embedded <style> child wherever it's attached, so `@scope`-based rules work the way you'd expect.
Element <tag: String, attributes: Array\Attribute = [], css: Css = nil, children: Array = []>

# -----------------------------------------------------------------------------
# 2. Formatter (render + minify + pretty-print, same "one type, a mode flag" shape as
#	 tapes/css.tape's Css_Formatter_Visitor)
# -----------------------------------------------------------------------------

Html_Formatter_Visitor {
	DEFAULT_INDENT := 2
	indent_size := DEFAULT_INDENT
	minify := false

	# Never given a closing tag, regardless of mode -- matches how tapes/html.tape's own generic
	# Dom#to_s already never self-closes anything either (no new inconsistency introduced there),
	# it just means these never emit an *empty* `</tag>` at all, in either mode.
	VOID_TAGS := %string(area base br col command embed hr img input keygen link meta param source track wbr)

	Self ( indent_size := DEFAULT_INDENT, minify := false;
		self.indent_size = indent_size
		self.minify = minify
	)

	render ( node, depth := 0;
		if node === Element
			render_element(node, depth)
		else
			node.to_s()
		end
	)

	# Prefixes every line of a block of text with `depth`'s padding -- used to line an embedded
	# stylesheet's formatted CSS up inside a pretty-printed page.
	indent_block ( text, depth;
		pad := indent_str(depth)
		text.split("\n").map(line; "`pad``line`").join("\n")
	)

	render_element ( el, depth;
		pad := indent_str(depth)
		attrs := render_attributes(el)
		# `css`, if attached, renders as one more child (an embedded <style> block) rather than
		# folding into `attrs` -- a real Css tree (selectors, nesting, @scope, ...) has no equivalent
		# as a flat attribute the way a simple property:value Dictionary would have.
		# note; `.concat` mutates its receiver (Ruby's own destructive Array#concat, under the hood) --
		# `el.children` is the struct's own array, so `.concat` would silently and permanently corrupt
		# it (double-appending the css child on a second render). `.flatten()` builds a fresh array instead.
		full_children := if el.css == nil
			el.children
		elif el.tag == "style"
			# css set directly on a <style> -- format it in place, no second <style> wrapper
			[Css_Formatter_Visitor(indent_size := self.indent_size, minify := self.minify).format(el.css)]
		else
			[el.children, [css_child(el.css)]].flatten()
		end

		if self.VOID_TAGS.include?(el.tag)
			if self.minify "<`el.tag``attrs`>" else "`pad`<`el.tag``attrs`>" end
		elif self.minify
			inner := full_children.map(c; render(c)).join("")
			"<`el.tag``attrs`>`inner`</`el.tag`>"
		elif el.tag == "style" and full_children.length() == 1 and !(full_children.0 === Element)
			# An embedded stylesheet -- block layout, its formatted CSS indented one level past the tag.
			# The lone child is either already-formatted CSS text or a raw css.tape node to format now.
			css_text := if full_children.0 === String
				full_children.0
			else
				Css_Formatter_Visitor(indent_size := self.indent_size, minify := self.minify).format(full_children.0)
			end
			"`pad`<style`attrs`>\n`indent_block(css_text, depth + 1)`\n`pad`</style>"
		elif full_children.length() == 1 and !(full_children.0 === Element)
			# A single bare-text child stays on one line ("<p>Hello</p>"), rather than always
			# expanding to block style -- keeps the common "leaf text element" case readable.
			"`pad`<`el.tag``attrs`>`render(full_children.0)`</`el.tag`>"
		else
			inner := full_children.map(c; render(c, depth + 1)).join("\n")
			"`pad`<`el.tag``attrs`>\n`inner`\n`pad`</`el.tag`>"
		end
	)

	render_attributes ( el;
		parts := []

		for el.attributes
			parts.push("`it.name`=\"`it.value`\"")
		end

		if parts.length() == 0
			""
		else
			" `parts.join(' ')`"
		end
	)

	# Shares this visitor's own indent/minify settings so a css tree nested inside a pretty-printed
	# page comes out pretty-printed too (and minified inside a minified one).
	css_child ( rule;
		Element("style", {}, nil, [Css_Formatter_Visitor(indent_size := self.indent_size, minify := self.minify).format(rule)])
	)

	indent_str ( depth;
		if self.minify "" else " " * (depth * self.indent_size) end
	)
}

# Two shared instances: compact (the original Html_Renderer's own default behaviour, kept as-is for
# anything already calling Html_Render.render(...)) and pretty/indented.
Html_Render := Html_Formatter_Visitor(minify := true)
Html_Format := Html_Formatter_Visitor()

# -----------------------------------------------------------------------------
# 2b. Stats (node counts, depth, unique tags, estimated raw vs minified size)
# -----------------------------------------------------------------------------

Html_Stats_Visitor {
	node_count := 0
	max_depth := 0
	tag_counts := {}

	# Resets and walks -- call this first, then read the members below or call
	# minified_size/pretty_size (which just re-render, no walk state needed).
	analyze ( node;
		self.node_count = 0
		self.max_depth = 0
		self.tag_counts = {}
		visit(node, 0)
		self
	)

	visit ( node, depth;
		if node === Element
			self.node_count += 1

			if depth > self.max_depth
				self.max_depth = depth
			end

			seen := self.tag_counts.fetch(node.tag, 0)
			self.tag_counts[node.tag] = seen + 1

			for node.children
				visit(it, depth + 1)
			end
		end
	)

	unique_tags (;
		self.tag_counts.keys()
	)

	minified_size ( node;
		Html_Render.render(node).length
	)

	pretty_size ( node;
		Html_Format.render(node).length
	)
}

# -----------------------------------------------------------------------------
# 2c. Sanitizer (strips script/iframe/object/embed tags, and on*/javascript: attributes)
# -----------------------------------------------------------------------------

Html_Sanitizer_Visitor {
	DANGEROUS_TAGS := %string(script iframe object embed)

	# Returns a cleaned tree -- source is untouched (structs are plain data), a dangerous
	# node (and everything under it) is dropped entirely rather than emptied out.
	sanitize ( node;
		if node === Element
			if self.DANGEROUS_TAGS.include?(node.tag)
				nil
			else
				clean_children := []
				for node.children
					cleaned := sanitize(it)
					if cleaned != nil
						clean_children.push(cleaned)
					end
				end
				Element(node.tag, sanitize_attributes(node.attributes), node.css, clean_children)
			end
		else
			node
		end
	)

	sanitize_attributes ( attributes;
		attributes.filter(a; !dangerous_attribute?(a))
	)

	dangerous_attribute? ( attr;
		if attr.name.start_with?("on")
			true
		elif (attr.name == "href" or attr.name == "src") and attr.value === String and attr.value.trim().start_with?("javascript:")
			true
		else
			false
		end
	)
}

# -----------------------------------------------------------------------------
# 2d. Lint (void element given children, <img> missing alt, empty containers, duplicate
#	  attribute names -- attributes are now an ordered Array\Attribute, not a Dictionary, so a
#	  duplicate name is a real possibility here now, same as Css_Lint_Visitor's duplicate-property
#	  check on an Array\Property)
# -----------------------------------------------------------------------------

Html_Lint_Visitor | Warnings_Visitor {
	VOID_TAGS := %string(area base br col command embed hr img input keygen link meta param source track wbr)

	lint ( node;
		self.warnings = []
		visit(node)
		self.warnings
	)

	visit ( node;
		if node === Element
			if self.VOID_TAGS.include?(node.tag) and node.children.length() > 0
				warn("<`node.tag`> is a void element but was given children")
			end

			if node.tag == "img" and !node.attributes.any?(a; a.name == "alt")
				warn("<img> is missing an alt attribute")
			end

			if !self.VOID_TAGS.include?(node.tag) and node.children.length() == 0
				warn("<`node.tag`> is empty")
			end

			check_duplicate_attributes(node)

			for node.children
				visit(it)
			end
		end
	)

	check_duplicate_attributes ( node;
		seen_names := []
		for node.attributes
			if seen_names.include?(it.name)
				warn("<`node.tag`> has a duplicate '`it.name`' attribute")
			end
			seen_names.push(it.name)
		end
	)
}

# -----------------------------------------------------------------------------
# 3. Element constructors (recovers the ergonomics tapes/html.tape gets from per-tag Types)
# note; lowercase, not capitalized like tapes/html.tape's Div/Title/etc -- these are ordinary
# functions, and a capitalized name before `(` routes to type-reference parsing instead of a
# function declaration (found the hard way writing this file).
# -----------------------------------------------------------------------------

# A single child (a bare String, or one Element) doesn't need its own `[...]` at every call site --
# wrapped here so `li("one")` and `li(["one", "two"])` both just work, same as `li(["one"])` always did.
as_children ( children;
	if children === Array
		children
	else
		[children]
	end
)

# Same override-in-place-or-append semantics as Dictionary#merge (used to build `href`/`utf8_meta`'s
# own forced attribute before attributes became an Array) -- only needed where a constructor forces
# one attribute of its own alongside whatever the caller already passed in.
merge_attribute ( attributes, attr;
	replaced := false
	merged := for attributes map
		if it.name == attr.name
			replaced = true
			attr
		else
			it
		end
	end
	if replaced merged else [merged, [attr]].flatten() end
)

html ( children := [];
	Element("html", {}, nil, as_children(children))
)

head ( children := [];
	Element("head", {}, nil, as_children(children))
)

body ( children := [], attributes := [], css := nil;
	Element("body", attributes, css, as_children(children))
)

title ( text;
	Element("title", {}, nil, [text])
)

h1 ( text, attributes := [], css := nil;
	Element("h1", attributes, css, [text])
)

h2 ( text, attributes := [], css := nil;
	Element("h2", attributes, css, [text])
)

h3 ( text, attributes := [], css := nil;
	Element("h3", attributes, css, [text])
)

h4 ( text, attributes := [], css := nil;
	Element("h4", attributes, css, [text])
)

h5 ( text, attributes := [], css := nil;
	Element("h5", attributes, css, [text])
)

h6 ( text, attributes := [], css := nil;
	Element("h6", attributes, css, [text])
)

# Text and inline elements
p ( children := [], attributes := [], css := nil;
	Element("p", attributes, css, as_children(children))
)

small ( children := [], attributes := [], css := nil;
	Element("small", attributes, css, as_children(children))
)

span ( children := [], attributes := [], css := nil;
	Element("span", attributes, css, as_children(children))
)

href ( href, children := [], attributes := [], css := nil;
	Element("a", merge_attribute(attributes, Attribute("href", href)), css, as_children(children))
)

strong ( children := [], attributes := [], css := nil;
	Element("strong", attributes, css, as_children(children))
)

em ( children := [], attributes := [], css := nil;
	Element("em", attributes, css, as_children(children))
)

code ( children := [], attributes := [], css := nil;
	Element("code", attributes, css, as_children(children))
)

pre ( children := [], attributes := [], css := nil;
	Element("pre", attributes, css, as_children(children))
)

# Lists
ul ( children := [], attributes := [], css := nil;
	Element("ul", attributes, css, as_children(children))
)

ol ( children := [], attributes := [], css := nil;
	Element("ol", attributes, css, as_children(children))
)

li ( children := [], attributes := [], css := nil;
	Element("li", attributes, css, as_children(children))
)

# Forms
form ( children := [], attributes := [], css := nil;
	Element("form", attributes, css, as_children(children))
)

input ( attributes := [], css := nil;
	Element("input", attributes, css, [])
)

button ( children := [], attributes := [], css := nil;
	Element("button", attributes, css, as_children(children))
)

textarea ( children := [], attributes := [], css := nil;
	Element("textarea", attributes, css, as_children(children))
)

label ( children := [], attributes := [], css := nil;
	Element("label", attributes, css, as_children(children))
)

select ( children := [], attributes := [], css := nil;
	Element("select", attributes, css, as_children(children))
)

option ( children := [], attributes := [], css := nil;
	Element("option", attributes, css, as_children(children))
)

# Containers
section ( children := [], attributes := [], css := nil;
	Element("section", attributes, css, as_children(children))
)

article ( children := [], attributes := [], css := nil;
	Element("article", attributes, css, as_children(children))
)

nav ( children := [], attributes := [], css := nil;
	Element("nav", attributes, css, as_children(children))
)

header ( children := [], attributes := [], css := nil;
	Element("header", attributes, css, as_children(children))
)

footer ( children := [], attributes := [], css := nil;
	Element("footer", attributes, css, as_children(children))
)

main ( children := [], attributes := [], css := nil;
	Element("main", attributes, css, as_children(children))
)

aside ( children := [], attributes := [], css := nil;
	Element("aside", attributes, css, as_children(children))
)

div ( children := [], attributes := [], css := nil;
	Element("div", attributes, css, as_children(children))
)

# Media
img ( attributes := [], css := nil;
	Element("img", attributes, css, [])
)

# Tables
table ( children := [], attributes := [], css := nil;
	Element("table", attributes, css, as_children(children))
)

thead ( children := [], attributes := [], css := nil;
	Element("thead", attributes, css, as_children(children))
)

tbody ( children := [], attributes := [], css := nil;
	Element("tbody", attributes, css, as_children(children))
)

tr ( children := [], attributes := [], css := nil;
	Element("tr", attributes, css, as_children(children))
)

th ( children := [], attributes := [], css := nil;
	Element("th", attributes, css, as_children(children))
)

td ( children := [], attributes := [], css := nil;
	Element("td", attributes, css, as_children(children))
)

# Other
br ( attributes := [], css := nil;
	Element("br", attributes, css, [])
)

hr ( attributes := [], css := nil;
	Element("hr", attributes, css, [])
)

dialog ( children := [], attributes := [], css := nil;
	Element("dialog", attributes, css, as_children(children))
)

style ( children := [], attributes := [], css := nil;
	Element("style", attributes, css, as_children(children))
)

fieldset ( children := [], attributes := [], css := nil;
	Element("fieldset", attributes, css, as_children(children))
)

legend ( children := [], attributes := [], css := nil;
	Element("legend", attributes, css, as_children(children))
)

kbd ( children := [], attributes := [], css := nil;
	Element("kbd", attributes, css, as_children(children))
)

samp ( children := [], attributes := [], css := nil;
	Element("samp", attributes, css, as_children(children))
)

meta ( attributes := [], css := nil;
	Element("meta", attributes, css, [])
)

utf8_meta ( attributes := [], css := nil;
	Element("meta", merge_attribute(attributes, Attribute("charset", "utf-8")), css, [])
)

link ( attributes := [], css := nil;
	Element("link", attributes, css, [])
)

script ( children := [], attributes := [], css := nil;
	Element("script", attributes, css, as_children(children))
)

canvas ( children := [], attributes := [], css := nil;
	Element("canvas", attributes, css, as_children(children))
)
