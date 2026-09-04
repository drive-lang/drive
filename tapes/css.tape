@load 'tapes/visitor'

# 1. AST Node Definitions
Property <name: String, value: Any, important: Bool = false>
Variable_Declaration <name: String, value: Any>
Css_Function <name: String, args: Array>
Keyframe <values: Array\String, declarations: Array\Property>
Color <hex: String>

Style_Rule <selectors: Array, declarations: Array, rules: Array = []>
At_Rule <name: String, prelude: String = "", body: Any = nil>
Scope_Rule <root: String, limit: String = "", rules: Array = []>
Custom_Property_Rule <name: String, syntax: String, inherits: Bool = false, initial_value: Any = nil>
Layer_Order <names: Array\String>
Stylesheet <rules: Array\Css>

# Composed Sum Type Union for All Rules
Css | Style_Rule | At_Rule | Scope_Rule | Custom_Property_Rule | Layer_Order <>


Css_Formatter_Visitor {
	DEFAULT_INDENT := 4
	indent_size := DEFAULT_INDENT
	minify := false

	Self ( indent_size := DEFAULT_INDENT, minify := false;
		self.indent_size = indent_size
		self.minify = minify
	)

	# `nested_in_rule` is only ever passed (true) from #format_style_rule's own recursive call over
	# `rule.rules` -- real CSS nesting, where a synthesized `&` prefix (#format_nested_selector) makes
	# sense because there genuinely is a parent selector to combine with. Every other caller (a
	# Stylesheet's top-level rules, an At_Rule's or Scope_Rule's own body) leaves it false, even
	# though those also increment `depth` -- `depth > 0` alone can't tell "really nested inside
	# another selector" apart from "just indented because something else wraps it".
	format ( node, depth := 0, nested_in_rule := false;
		if node === Stylesheet
			format_stylesheet(node, depth)
		elif node === Style_Rule
			format_style_rule(node, depth, nested_in_rule)
		elif node === At_Rule
			format_at_rule(node, depth)
		elif node === Scope_Rule
			format_scope_rule(node, depth)
		elif node === Custom_Property_Rule
			format_custom_property(node, depth)
		elif node === Layer_Order
			format_layer_order(node, depth)
		elif node === Keyframe
			format_keyframe(node, depth)
		elif node === Property
			format_property(node, depth)
		elif node === Variable_Declaration
			format_variable(node, depth)
		elif node === Css_Function
			format_function(node)
		elif node === Color
			if node.hex.has_all_same_characters?()
				node.hex.0 * 3
			else
				node.hex
			end
		else
			node.to_s()
		end
	)

	format_stylesheet ( stylesheet, depth;
		lines := for stylesheet.rules map
			format(it, depth)
		end
		sep := if self.minify "" else "\n\n" end
		lines.join(sep)
	)

	format_style_rule ( rule, depth, nested_in_rule := false;
		pad := indent_str(depth)

		# Only a selector genuinely nested inside another Style_Rule gets the synthesized `&` --
		# not merely being at some `depth` because an At_Rule/Scope_Rule wraps it (see `format`'s note).
		formatted_selectors := for rule.selectors map
			if nested_in_rule format_nested_selector(it) else it end
		end

		sel_sep := if self.minify "," else ", " end
		sel := formatted_selectors.join(sel_sep)

		decls := for rule.declarations map
			format(it, depth + 1)
		end

		sub_rules := for rule.rules map
			format(it, depth + 1, true)
		end

		if self.minify
			decls_str := decls.join("")
			sub_str := sub_rules.join("")
			"`sel`{`decls_str``sub_str`}"
		else
			decls_str := decls.join("\n")
			sub_str := sub_rules.join("\n")

			body := if sub_rules.empty?()
				decls_str
			elif decls.empty?()
				sub_str
			else
				"`decls_str`\n`sub_str`"
			end

			"`pad``sel` {\n`body`\n`pad`}"
		end
	)

	format_nested_selector ( sel;
		if sel.starts_with?("&") or sel.starts_with?(":")
			sel
		else
			"& `sel`"
		end
	)

	format_at_rule ( rule, depth;
		pad := indent_str(depth)
		pre := if rule.prelude.empty?() "" else " `rule.prelude`" end

		if rule.body == nil
			"`pad`@`rule.name``pre`;"
		elif rule.body === Array
			inner := for rule.body map
			 format(it, depth + 1)
			end

			if self.minify
			 pre_mini := if rule.prelude.empty?() "" else "`rule.prelude`" end
			 pre_space := if rule.prelude.empty?() "" else " " end
			 "`pad`@`rule.name``pre_space``pre_mini`{`inner.join(\"\")`}"
			else
			 "`pad`@`rule.name``pre` {\n`inner.join(\"\n\")`\n`pad`}"
			end
		else
			"`pad`@`rule.name``pre`;"
		end
	)

	format_scope_rule ( scope_node, depth;
		pad := indent_str(depth)
		limit_str := if scope_node.limit.empty?() "" else " to (`scope_node.limit`)" end

		inner := for scope_node.rules map
			format(it, depth + 1)
		end

		if self.minify
			"`pad`@scope(`scope_node.root`)`limit_str`{`inner.join(\"\")`}"
		else
			"`pad`@scope (`scope_node.root`)`limit_str` {\n`inner.join(\"\n\")`\n`pad`}"
		end
	)

	format_custom_property ( prop_node, depth;
		pad := indent_str(depth)
		pad_inner := indent_str(depth + 1)
		var_name := normalize_var_name(prop_node.name)
		init_val := format_value(prop_node.initial_value)

		if self.minify
			"@property `var_name`{syntax:\"`prop_node.syntax`\";inherits:`prop_node.inherits`;initial-value:`init_val`;}"
		else
			"`pad`@property `var_name` {\n`pad_inner`syntax: \"`prop_node.syntax`\";\n`pad_inner`inherits: `prop_node.inherits`;\n`pad_inner`initial-value: `init_val`;\n`pad`}"
		end
	)

	format_layer_order ( layer_node, depth;
		pad := indent_str(depth)
		names_list := if layer_node.names === Array
			layer_node.names
		else
			[layer_node.names]
		end
		sep := if self.minify "," else ", " end

		"`pad`@layer `names_list.join(sep)`;"
	)

	format_keyframe ( kf, depth;
		pad := indent_str(depth)
		vals_sep := if self.minify "," else ", " end
		vals := kf.values.join(vals_sep)
		decls := for kf.declarations map
			format(it, depth + 1)
		end

		if self.minify
			"`vals`{`decls.join(\"\")`}"
		else
			"`pad``vals` {\n`decls.join(\"\n\")`\n`pad`}"
		end
	)

	format_property ( prop, depth;
		pad := indent_str(depth)
		val := format_value(prop.value)
		imp := if prop.important " !important" else "" end

		if self.minify
			"`prop.name`:`val``imp`;"
		else
			"`pad``prop.name`: `val``imp`;"
		end
	)

	format_variable ( var_decl, depth;
		pad := indent_str(depth)
		var_name := normalize_var_name(var_decl.name)
		val := format_value(var_decl.value)

		if self.minify
			"`var_name`:`val`;"
		else
			"`pad``var_name`: `val`;"
		end
	)

	format_function ( fn;
		sep := if self.minify "," else ", " end
		formatted_args := for fn.args map
			format_value(it)
		end
		"`fn.name`(`formatted_args.join(sep)`)"
	)

	format_value ( val;
		if val === Css_Function
			format_function(val)
		elif val === Color
			val.hex
		else
			val.to_s()
		end
	)

	normalize_var_name ( name;
		if name.starts_with?("--")
			name
		else
			"--`name`"
		end
	)

	indent_str ( depth;
		if self.minify
			""
		else
			" " * (depth * self.indent_size)
		end
	)
}

# Duplicate properties, hardcoded vendor prefixes, and redundant zero-units (e.g. "0px" -> "0").
Css_Lint_Visitor | Warnings_Visitor {
	VENDOR_PREFIXES := %string(-webkit- -moz- -ms- -o-)
	ZERO_UNITS := %string(px em rem % vh vw pt)

	lint ( node;
		self.warnings = []
		visit(node)
		self.warnings
	)

	visit ( node;
		if node === Stylesheet
			for node.rules
				visit(it)
			end
		elif node === Style_Rule
			seen_props := []
			for node.declarations
				check_declaration(it, seen_props)
			end
			for node.rules
				visit(it)
			end
		elif node === Scope_Rule
			for node.rules
				visit(it)
			end
		elif node === At_Rule
			if node.body === Array
				for node.body
					visit(it)
				end
			end
		end
	)

	check_declaration ( prop, seen_props;
		if prop === Property
			if seen_props.include?(prop.name)
				warn("Duplicate property '`prop.name`'")
			end
			seen_props.push(prop.name)

			for self.VENDOR_PREFIXES
				if prop.name.start_with?(it)
					warn("Avoid hardcoded vendor prefix in '`prop.name`'")
				end
			end

			check_zero_units(prop)
		end
	)

	check_zero_units ( prop;
		if prop.value === String
			for prop.value.split(" ")
				token := it
				if token.start_with?("0") and self.ZERO_UNITS.any?(unit; token.end_with?(unit))
					warn("Unit unneeded for zero value in '`prop.name`: `prop.value`'")
				end
			end
		end
	)
}
