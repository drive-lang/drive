require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# tapes/css.tape: the AST node structs, Css_Formatter_Visitor (format + minify), and
# Css_Lint_Visitor (duplicate properties, vendor prefixes, redundant zero-units).
class Css_Test < Base_Test
	CSS = "@load 'tapes/css.tape'"

	# --- Css_Formatter_Visitor -------------------------------------------------

	def test_format_property_pretty
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Property('color', 'red'))"
		assert_equal 'color: red;', out
	end

	def test_format_property_minify
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor(minify := true).format(Property('color', 'red'))"
		assert_equal 'color:red;', out
	end

	def test_format_property_important
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Property('color', 'red', true))"
		assert_equal 'color: red !important;', out
	end

	def test_format_style_rule_pretty
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('color', 'red'), Property('padding', '0')])
		    Css_Formatter_Visitor().format(rule)
		CODE
		assert_equal ".box {\n    color: red;\n    padding: 0;\n}", out
	end

	def test_format_style_rule_minify
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('color', 'red'), Property('padding', '0')])
		    Css_Formatter_Visitor(minify := true).format(rule)
		CODE
		assert_equal '.box{color:red;padding:0;}', out
	end

	# depth > 0 selectors get a synthesized `&` prefix (#format_nested_selector) unless they
	# already start with `&`/`:`.
	def test_format_style_rule_synthesizes_nesting_ampersand
		out = Drive.interp <<~CODE
		    #{CSS}
		    outer := Style_Rule(['.box'], [], [Style_Rule(['&:hover'], [Property('color', 'blue')])])
		    Css_Formatter_Visitor().format(outer)
		CODE
		assert_equal ".box {\n    &:hover {\n        color: blue;\n    }\n}", out
	end

	def test_format_at_rule_with_no_body
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(At_Rule('charset', '\"utf-8\"'))"
		assert_equal '@charset "utf-8";', out
	end

	def test_format_at_rule_with_array_body_pretty
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := At_Rule('media', '(min-width: 100px)', [Style_Rule(['.a'], [Property('color', 'red')])])
		    Css_Formatter_Visitor().format(rule)
		CODE
		assert_equal "@media (min-width: 100px) {\n    .a {\n        color: red;\n    }\n}", out
	end

	def test_format_at_rule_with_array_body_minify
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := At_Rule('media', '(min-width: 100px)', [Style_Rule(['.a'], [Property('color', 'red')])])
		    Css_Formatter_Visitor(minify := true).format(rule)
		CODE
		assert_equal '@media (min-width: 100px){.a{color:red;}}', out
	end

	# format_scope_rule's own non-minify branch is what exposed the #interp_string /m regex bug
	# (bugs.md) -- a nested `"\n"` inside a backtick-interpolated `.join("\n")` used to be left as
	# literal, un-interpolated text.
	def test_format_scope_rule_pretty
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Scope_Rule('.widget', '', [Style_Rule(['p'], [Property('margin', '0')])])
		    Css_Formatter_Visitor().format(rule)
		CODE
		assert_equal "@scope (.widget) {\n    p {\n        margin: 0;\n    }\n}", out
	end

	def test_format_scope_rule_with_limit
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Scope_Rule('.widget', '.limit', [Style_Rule(['p'], [Property('margin', '0')])])
		    Css_Formatter_Visitor().format(rule)
		CODE
		assert_equal "@scope (.widget) to (.limit) {\n    p {\n        margin: 0;\n    }\n}", out
	end

	def test_format_scope_rule_minify
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Scope_Rule('.widget', '', [Style_Rule(['p'], [Property('margin', '0')])])
		    Css_Formatter_Visitor(minify := true).format(rule)
		CODE
		assert_equal '@scope(.widget){p{margin:0;}}', out
	end

	# A rule genuinely nested inside another Style_Rule's own `.rules` still gets the synthesized
	# `&` (unlike the At_Rule/Scope_Rule cases above, which don't establish a nesting context) --
	# regression coverage for #format_style_rule's `nested_in_rule` param, keyed off which caller it
	# came from rather than `depth` alone.
	def test_format_style_rule_nested_inside_at_rule_body_does_not_get_ampersand_even_though_a_style_rule_nested_inside_a_style_rule_still_does
		out = Drive.interp <<~CODE
		    #{CSS}
		    at_rule := At_Rule('media', '(min-width: 100px)', [Style_Rule(['.a'], [], [Style_Rule(['.b'], [Property('color', 'red')])])])
		    Css_Formatter_Visitor().format(at_rule)
		CODE
		assert_equal "@media (min-width: 100px) {\n    .a {\n        & .b {\n            color: red;\n        }\n    }\n}", out
	end

	def test_format_custom_property_rule
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Custom_Property_Rule('main-color', '<color>', true, 'blue')
		    Css_Formatter_Visitor().format(rule)
		CODE
		assert_equal "@property --main-color {\n    syntax: \"<color>\";\n    inherits: true;\n    initial-value: blue;\n}", out
	end

	def test_format_layer_order
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Layer_Order(['reset', 'base', 'components']))"
		assert_equal '@layer reset, base, components;', out
	end

	def test_format_keyframe
		out = Drive.interp <<~CODE
		    #{CSS}
		    kf := Keyframe(['0%', '100%'], [Property('opacity', '0')])
		    Css_Formatter_Visitor().format(kf)
		CODE
		assert_equal "0%, 100% {\n    opacity: 0;\n}", out
	end

	def test_format_variable_declaration
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Variable_Declaration('main-color', 'blue'))"
		assert_equal '--main-color: blue;', out
	end

	def test_format_css_function
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Css_Function('rgba', [1, 2, 3, 0.5]))"
		assert_equal 'rgba(1, 2, 3, 0.5)', out
	end

	def test_format_color
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Color('ff0000'))"
		assert_equal 'ff0000', out
	end

	# The shorthand branch (`node.hex.has_all_same_characters?()` true) relies on String positional
	# dot-index (`node.hex.0`) -- regression coverage from the css.tape side, now that #interp_dot_string
	# makes `.N` on a String work (see test/interpreter_test.rb for the interpreter-level tests).
	def test_format_color_single_repeated_character_shorthand
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Color('f'))"
		assert_equal 'fff', out
	end

	def test_format_color_already_three_of_the_same_character
		out = Drive.interp "#{CSS}\nCss_Formatter_Visitor().format(Color('aaa'))"
		assert_equal 'aaa', out
	end

	def test_format_stylesheet_joins_rules_with_blank_line_pretty
		out = Drive.interp <<~CODE
		    #{CSS}
		    sheet := Stylesheet([Style_Rule(['.a'], [Property('color', 'red')]), Style_Rule(['.b'], [Property('color', 'blue')])])
		    Css_Formatter_Visitor().format(sheet)
		CODE
		assert_equal ".a {\n    color: red;\n}\n\n.b {\n    color: blue;\n}", out
	end

	def test_format_stylesheet_minify_has_no_separator
		out = Drive.interp <<~CODE
		    #{CSS}
		    sheet := Stylesheet([Style_Rule(['.a'], [Property('color', 'red')]), Style_Rule(['.b'], [Property('color', 'blue')])])
		    Css_Formatter_Visitor(minify := true).format(sheet)
		CODE
		assert_equal '.a{color:red;}.b{color:blue;}', out
	end

	def test_custom_indent_size_is_honored
		out = Drive.interp <<~CODE
		    #{CSS}
		    Css_Formatter_Visitor(2).format(Style_Rule(['.box'], [Property('color', 'red')]))
		CODE
		assert_equal ".box {\n  color: red;\n}", out
	end

	# --- Css_Lint_Visitor -------------------------------------------------------

	def test_lint_flags_duplicate_property
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('color', 'red'), Property('color', 'blue')])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal ["Duplicate property 'color'"], out.values
	end

	def test_lint_flags_vendor_prefix
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('-webkit-transform', 'none')])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal ["Avoid hardcoded vendor prefix in '-webkit-transform'"], out.values
	end

	def test_lint_flags_redundant_zero_unit
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('margin', '0px 10px')])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal ["Unit unneeded for zero value in 'margin: 0px 10px'"], out.values
	end

	def test_lint_clean_rule_has_no_warnings
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Style_Rule(['.box'], [Property('color', 'red'), Property('padding', '10px')])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal [], out.values
	end

	def test_lint_recurses_into_nested_style_rules
		out = Drive.interp <<~CODE
		    #{CSS}
		    outer := Style_Rule(['.box'], [], [Style_Rule(['.inner'], [Property('color', 'red'), Property('color', 'blue')])])
		    Css_Lint_Visitor().lint(outer)
		CODE
		assert_equal ["Duplicate property 'color'"], out.values
	end

	def test_lint_recurses_into_at_rule_array_body
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := At_Rule('media', '(min-width: 100px)', [Style_Rule(['.a'], [Property('color', 'red'), Property('color', 'blue')])])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal ["Duplicate property 'color'"], out.values
	end

	def test_lint_recurses_into_scope_rule
		out = Drive.interp <<~CODE
		    #{CSS}
		    rule := Scope_Rule('.widget', '', [Style_Rule(['p'], [Property('color', 'red'), Property('color', 'blue')])])
		    Css_Lint_Visitor().lint(rule)
		CODE
		assert_equal ["Duplicate property 'color'"], out.values
	end

	def test_lint_recurses_into_stylesheet
		out = Drive.interp <<~CODE
		    #{CSS}
		    sheet := Stylesheet([Style_Rule(['.a'], [Property('color', 'red'), Property('color', 'blue')])])
		    Css_Lint_Visitor().lint(sheet)
		CODE
		assert_equal ["Duplicate property 'color'"], out.values
	end

	# A running keyframe animation on `transform` overrides a `:hover { transform }` every frame --
	# only checked at Stylesheet level, where both the @keyframes and the rules are visible.
	def test_lint_flags_hover_transform_overridden_by_running_animation
		out = Drive.interp <<~CODE
		    #{CSS}
		    kf := At_Rule('keyframes', 'float', [Keyframe(['0%'], [Property('transform', 'translateY(0)')]), Keyframe(['100%'], [Property('transform', 'translateY(-10px)')])])
		    base := Style_Rule(['.card'], [Property('animation', 'float 3s infinite')])
		    hover := Style_Rule(['.card:hover'], [Property('transform', 'scale(1.05)')])
		    Css_Lint_Visitor().lint(Stylesheet([kf, base, hover]))
		CODE
		assert_equal(
			[".card:hover sets transform, but .card runs a keyframe animation on transform -- the animation overrides it every frame"],
			out.values
		)
	end

	def test_lint_no_clash_when_keyframes_do_not_touch_transform
		out = Drive.interp <<~CODE
		    #{CSS}
		    kf := At_Rule('keyframes', 'fade', [Keyframe(['0%'], [Property('opacity', '0')]), Keyframe(['100%'], [Property('opacity', '1')])])
		    base := Style_Rule(['.card'], [Property('animation', 'fade 3s infinite')])
		    hover := Style_Rule(['.card:hover'], [Property('transform', 'scale(1.05)')])
		    Css_Lint_Visitor().lint(Stylesheet([kf, base, hover]))
		CODE
		assert_equal [], out.values
	end

	# `lint` resets `warnings` at the start, same as Html_Lint_Visitor's own `lint` -- reusing one
	# instance across calls does not accumulate.
	def test_lint_resets_between_calls_on_the_same_instance
		out = Drive.interp <<~CODE
		    #{CSS}
		    linter := Css_Lint_Visitor()
		    linter.lint(Style_Rule(['.a'], [Property('color', 'red'), Property('color', 'blue')]))
		    linter.lint(Style_Rule(['.b'], [Property('padding', '0')]))
		CODE
		assert_equal [], out.values
	end
end
