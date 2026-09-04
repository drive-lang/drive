### Generic Dom element, set `html_element=` to the element you want to render ###
Dom {
	html_element := 'div'
	children,
	onclick,
	key,   # optional stable id for this element's handler/input token

	Self ( children := [];
		self.children = children
	)

	render (; children )

	# Renders this element, and its children, to a string.
	to_s (;
		inner   := render()
		content := if inner.?uniq # Checking whether inner responds to uniq(;), without actually calling it.
			final := ''
			for inner
				final += it.?to_s() or it
			end
			final
		else
			inner.?to_s() or inner
		end

		"<`html_element`>`content`</`html_element`>"
	)
}

### Predefined Dom elements ###
Html | Dom {
	html_element := 'html'
}

Head | Dom {
	html_element := 'head'
}

Body | Dom {
	html_element := 'body'
}

Title | Dom {
	html_element := 'title'
	title,

	Self ( title;
		self.title = title
	)

	render (; title )
}

# Headings
H1 | Dom {
	html_element := 'h1'
}

H2 | Dom {
	html_element := 'h2'
}

H3 | Dom {
	html_element := 'h3'
}

H4 | Dom {
	html_element := 'h4'
}

H5 | Dom {
	html_element := 'h5'
}

H6 | Dom {
	html_element := 'h6'
}

# Text and inline elements
P | Dom {
	html_element := 'p'
}

Small | Dom {
	html_element := 'small'
}

Span | Dom {
	html_element := 'span'
}

A | Dom {
	html_element := 'a'
	html_href,
	title,

	Self ( href, title;
		html_href = href
		self.title = title
	)

	render (; title )
}
Href := A

Strong | Dom {
	html_element := 'strong'
}

Em | Dom {
	html_element := 'em'
}

Code | Dom {
	html_element := 'code'
}

Pre | Dom {
	html_element := 'pre'
}

# Lists
Ul | Dom {
	html_element := 'ul'
}

Ol | Dom {
	html_element := 'ol'
}

Li | Dom {
	html_element := 'li'
}

# Forms
Form | Dom {
	html_element := 'form'
}

Input | Dom {
	html_element := 'input'
}

Button | Dom {
	html_element := 'button'
}

Textarea | Dom {
	html_element := 'textarea'
}

Label | Dom {
	html_element := 'label'
}

Select | Dom {
	html_element := 'select'
}

Option | Dom {
	html_element := 'option'
}

# Containers
Section | Dom {
	html_element := 'section'
}

Article | Dom {
	html_element := 'article'
}

Nav | Dom {
	html_element := 'nav'
}

Header | Dom {
	html_element := 'header'
}

Footer | Dom {
	html_element := 'footer'
}

Main | Dom {
	html_element := 'main'
}

Aside | Dom {
	html_element := 'aside'
}

Div | Dom {
	html_element := 'div'
}

# Media
Img | Dom {
	html_element := 'img'
}

# Tables
# To avoid collision with database Table, this is called Html_Table, since both are likely to be used together.
Html_Table | Dom {
	html_element := 'table'
}

Thead | Dom {
	html_element := 'thead'
}

Tbody | Dom {
	html_element := 'tbody'
}

Tr | Dom {
	html_element := 'tr'
}

Th | Dom {
	html_element := 'th'
}

Td | Dom {
	html_element := 'td'
}

# Other
Br | Dom {
	html_element := 'br'
}

Hr | Dom {
	html_element := 'hr'
}

Dialog | Dom {
	html_element := 'dialog'
}

Style | Dom {
	html_element := 'style'
}

###
Fieldset + Legend: Native solution for bordered boxes with a title breaking the top border line. Browsers render legend directly inside the top border path of a fieldset without requiring custom border-rebuilding hacks.
Pre + Code: Essential for exact character-grid alignment, block art (▓▒░), and multi-line ASCII/ANSI-style layouts where whitespace and monospaced font geometry must be preserved.
Kbd & Samp: Semantic elements ideal for rendering keybindings (e.g., [CTRL+C]) and terminal execution output.
Link: Needed in Head to pull in custom retro webfonts (like VT323, IBM Plex Mono, or Fixedsys).
###

Fieldset | Dom {
	html_element := 'fieldset'
}

Legend | Dom {
	html_element := 'legend'
}

Kbd | Dom {
	html_element := 'kbd'
}

Samp | Dom {
	html_element := 'samp'
}

Meta | Dom {
	html_element := 'meta'
}

Utf8_Meta | Meta {
    html_charset := 'utf-8'
}

Link | Dom {
	html_element := 'link'
}

Script | Dom {
	html_element := 'script'
}

Canvas | Dom {
	html_element := 'canvas'
}
