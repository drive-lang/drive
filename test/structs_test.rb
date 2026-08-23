require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class Structs_Test < Base_Test
	def test_parses_standalone_struct_literal
		out = Lost.parse '<String, Number>'
		assert_kind_of Lost::Struct_Expr, out.first
		assert_equal %w(String Number), out.first.types.map(&:value)
	end

	def test_parses_standalone_struct_literal_with_single_type
		out = Lost.parse '<String>'
		assert_kind_of Lost::Struct_Expr, out.first
		assert_equal %w(String), out.first.types.map(&:value)
	end

	def test_parses_type_declaration_with_struct
		out = Lost.parse 'Array\\<String> {}'
		assert_kind_of Lost::Type_Expr, out.first
		assert_equal 'Array', out.first.name
		assert_kind_of Lost::Struct_Expr, out.first.tag
		assert_equal %w(String), out.first.tag.types.map(&:value)
	end

	def test_parses_type_declaration_with_multiple_members
		out = Lost.parse 'Dictionary\\<String, Number> {}'
		assert_equal %w(String Number), out.first.tag.types.map(&:value)
	end

	def test_type_declaration_without_struct_has_nil_struct
		out = Lost.parse 'String {}'
		assert_nil out.first.tag
	end

	def test_struct_members_can_be_arbitrary_expressions
		out = Lost.parse 'Abc\\<1+2+3/123>'
		assert_kind_of Lost::Infix_Expr, out.first.tag.types.first

		result = Lost.interp "Abc {}
		Abc\\<Number> {}
		Abc\\<1+2+3/123>.tag.types.first()"
		assert_equal 3, result
	end

	def test_interprets_standalone_struct_literal_to_struct_instance
		out = Lost.interp '<String, Number>'
		assert_kind_of Lost::Struct, out
		assert_equal 'String', out.type_objects[0].name
		assert_equal 'Number', out.type_objects[1].name
	end

	def test_struct_instance_types_accessible_from_lost
		out = Lost.interp "g := <String, Number>
		g.types"
		assert_equal 'String', out.values[0].name
		assert_equal 'Number', out.values[1].name
	end

	def test_bare_struct_assignable_and_storable
		# A bare annotation alone on its own line (no `=` on the same expression) is undeclared, same as any other annotation (`x: Number` alone behaves identically) — combine the annotation and assignment into one expression, which is how self-declaring annotations actually work today.
		out = Lost.interp 'thing: <String, Number> = <String, Number>
		thing.types.count'
		assert_equal 2, out
	end

	def test_type_with_struct_still_composes_normally
		refute_raises do
			out = Lost.interp 'Array\\<String> {}'
			assert_kind_of Lost::Type, out
			assert_equal 'Array', out.name
		end
	end

	def test_composing_builtin_type_with_struct_does_not_break_it
		out = Lost.interp <<~CODE
		    String\\<Dictionary> {}
		    s := String('hello')
		    s.upcase()
		CODE
		assert_equal 'HELLO', out
	end

	def test_struct_does_not_interfere_with_plain_type_declarations
		out = Lost.interp <<~CODE
		    Point {
		    	x, y,
		    	new ( x, y;
		    		self.x = x
		    		self.y = y
		    	)
		    }
		    p := Point(3, 4)
		    (p.x, p.y)
		CODE
		assert_equal [3, 4], out.values
	end

	def test_annotation_form_captures_struct
		out = Lost.parse 'x: Abc\\<Number>'
		assert_kind_of Lost::Struct_Expr, out.first.type_struct
		assert_equal %w(Number), out.first.type_struct.types.map(&:value)
	end

	def test_bare_struct_annotation_with_no_type_name
		out = Lost.parse 'thing: <String, Number>'
		assert_kind_of Lost::Struct_Expr, out.first.type_struct
		assert_equal %w(String Number), out.first.type_struct.types.map(&:value)
	end

	def test_type_reference_with_struct_does_not_mutate_shared_type
		out = Lost.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    x := Abc\\<Number>
		    y := Abc\\<String>
		    (x.tag.types.first(), y.tag.types.first())
		CODE
		assert_equal 'Number', out.values[0].name
		assert_equal 'String', out.values[1].name
	end

	def test_type_reference_works_with_constants_too
		out = Lost.interp <<~CODE
		    Abc {
		    	val,
		    	new ( v; self.val = v )
		    }
		    Abc\\<Number> {}
		    Y := Abc\\<Number>
		    Y(9).val
		CODE
		assert_equal 9, out
	end

	def test_type_reference_can_be_reassigned_before_calling
		out = Lost.interp <<~CODE
		    Abc {
		    	val,
		    	new ( v; self.val = v )
		    }
		    Abc\\<Number> {}
		    y := Abc\\<Number>
		    z := y
		    z(5).val
		CODE
		assert_equal 5, out
	end

	def test_struct_bound_onto_instance_before_new_runs
		out = Lost.interp <<~CODE
		    Abc\\<Number> {
		    	new (;)
		    }
		    z := Abc\\<4815>
		    zz := z()
		    zz.tag.types.first()
		CODE
		assert_equal 4815, out
	end

	def test_struct_members_are_not_forwarded_as_constructor_arguments
		out = Lost.interp <<~CODE
		    Abc {
		    	val,
		    	new ( v := -1; self.val = v )
		    }
		    Abc\\<Number> {}
		    zz := Abc\\<4815>()
		    zz.val
		CODE
		assert_equal(-1, out)
	end

	def test_named_member_schema_parses_and_resolves_declared_type
		out = Lost.parse 'Type\\<some_string: String, num: Number> {}'
		assert_equal ['some_string', 'num'], out.first.tag.names

		type = Lost.interp 'Type\\<some_string: String, num: Number> {}'
		assert_equal 'String', type.tag_declaration.declarations['some_string'].name
		assert_equal 'Number', type.tag_declaration.declarations['num'].name
	end

	def test_tag_declaration_captures_default_values
		type = Lost.interp 'Widget\\<indent: Number = 2> {}'
		assert_equal ['indent'], type.tag_declaration.names
		assert_equal [2], type.tag_declaration.values
	end

	def test_untagged_declaration_has_no_tag_declaration
		type = Lost.interp 'Plain { x, }'
		assert_nil type.tag_declaration
	end

	def test_tag_declaration_is_independent_per_variant
		out = Lost.interp <<~CODE
		    dict_variant := String\\<dict: Dictionary> {}
		    num_variant := String\\<num: Number> {}
		    (dict_variant, num_variant)
		CODE
		dict_variant, num_variant = out.values

		assert_equal ['dict'], dict_variant.tag_declaration.names
		assert_equal 'Dictionary', dict_variant.tag_declaration.type_objects.first.name

		assert_equal ['num'], num_variant.tag_declaration.names
		assert_equal 'Number', num_variant.tag_declaration.type_objects.first.name
	end

	def test_structure_declaration_equal_compares_names_and_types
		dict_a = Lost::Struct.new(['dict'], ['Dictionary'], [nil])
		dict_b = Lost::Struct.new(['dict'], ['Dictionary'], [nil])
		other  = Lost::Struct.new(['other'], ['Dictionary'], [nil]) # same type, different name
		number = Lost::Struct.new(['dict'], ['Number'], [nil]) # same name, different type

		assert dict_a.structure_declaration_equal?(dict_b)
		refute dict_a.structure_declaration_equal?(other)
		refute dict_a.structure_declaration_equal?(number)
	end

	# Reference matching (`String<{x=1}>()`) never supplies member names, so it only ever compares
	# against `type_names` -- names exist purely to keep declarations distinct from each other.
	def test_tag_satisfied_by_candidates_ignores_names
		declared = Lost::Struct.new(['dict'], ['Dictionary'], [nil])

		assert declared.satisfied_by_candidates?([['Dictionary']])
		refute declared.satisfied_by_candidates?([['Number']])
	end

	def test_differently_named_same_typed_members_are_distinct_variants_regression
		out = Lost.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<{x=1}>()
		    a.to_s()
		CODE
		assert_equal 'dict-named', out

		out = Lost.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<other := {x=1}>()
		    a.to_s()
		CODE
		assert_equal 'other-named', out

		out = Lost.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<dict := {x=1}>()
		    a.to_s()
		CODE
		assert_equal 'dict-named', out
	end

	def test_reference_to_never_declared_type_name_builds_a_bare_named_struct
		# `Ident<...>` with a base name that's never been declared as anything at all (no bare Type, no tagged variant, no alias) isn't an error -- it's a bare named struct, same shape as `<...>` but with `.name` set from the identifier. Only collides with something else declared -- a real Type with a mismatched tag, or an alias to a non-Type value -- does it still raise (see test_reference_to_mismatched_declared_tag_raises).
		out = Lost.interp <<~CODE
		    n := Named\\<Number>
		    n.name
		CODE
		assert_equal 'Named', out

		out = Lost.interp <<~CODE
		    n := Named\\<Number>
		    n.types.values.map((it; it.name)).join(', ')
		CODE
		assert_equal 'Number', out
	end

	# Re-declaring the exact same bare named struct a second time used to raise Undeclared_Type_Structure -- `aliased` (the struct from the first declaration) being non-nil blocked the bare-named-struct fallback, even though the shape hadn't actually changed.
	def test_redeclaring_same_bare_named_struct_is_a_no_op
		refute_raises do
			out = Lost.interp <<~CODE
			    Task <
			    	id: Number
			    	done := false
			    >
			    Task <
			    	id: Number
			    	done := false
			    >
			    Task.name
			CODE
			assert_equal 'Task', out
		end
	end

	# A genuinely different shape under the same name still raises, unchanged.
	def test_redeclaring_bare_named_struct_with_a_different_shape_still_raises
		assert_raises Lost::Undeclared_Tagged_Type do
			Lost.interp <<~CODE
			    Task <id: Number>
			    Task <id: String>
			CODE
		end
	end

	# A name, not position, identifies a named member everywhere it's actually used -- reordering named members is still the same declaration, not a different one.
	def test_redeclaring_bare_named_struct_with_reordered_members_is_a_no_op
		out = Lost.interp <<~CODE
		    Task <id: Number, done: Bool>
		    Task <done: Bool, id: Number>
		    Task.name
		CODE
		assert_equal 'Task', out
	end

	# Not just "doesn't raise" -- the actual member set is unchanged by the reorder, before and after.
	def test_redeclaring_bare_named_struct_with_reordered_members_keeps_the_same_members
		out = Lost.interp <<~CODE
		    before := Task <id: Number, done: Bool>
		    after := Task <done: Bool, id: Number>
		    (before.names, before.type_names, after.names, after.type_names)
		CODE
		before_members = out.values[0].values.zip(out.values[1].values).sort
		after_members  = out.values[2].values.zip(out.values[3].values).sort

		assert_equal [%w(done Bool), %w(id Number)], before_members
		assert_equal before_members, after_members
	end

	# Unnamed members have no such identity besides position -- reordering those still counts as a different tag and raises, same as any other shape mismatch.
	def test_redeclaring_unnamed_tagged_type_with_reordered_members_still_raises
		assert_raises Lost::Undeclared_Tagged_Type do
			Lost.interp <<~CODE
			    Abc\\<Number, String> {}
			    Abc\\<String, Number>
			CODE
		end
	end

	def test_reference_to_mismatched_declared_tag_raises
		assert_raises Lost::Undeclared_Tagged_Type do
			Lost.interp <<~CODE
			    Abc\\<Number> {}
			    Abc\\<String>
			CODE
		end
	end

	# Undeclared_Type_Structure's own message-rendering used to crash (NoMethodError inside Struct_Expr#to_s) when the mismatched struct had a named member with no `: Type` annotation (`done := false` -- `.type` is nil, unlike `.type.value` this code blindly read). assert_raises here would surface that NoMethodError instead of the real error if this regressed.
	def test_mismatched_structure_error_message_renders_untyped_member_without_crashing
		error = assert_raises Lost::Undeclared_Tagged_Type do
			Lost.interp <<~CODE
			    Task <id: String>
			    Task <
			    	id: Number
			    	done := false
			    >
			CODE
		end
		assert_includes error.message, 'done: false'
	end

	def test_reference_matches_tag_by_composed_type_not_just_own_name
		out = Lost.interp <<~CODE
		    Flying { can_fly := true }
		    Duck | Flying { name := 'duck' }

		    String\\<val: Flying> {
		    	to_s (; "yes" )
		    }

		    d := Duck()
		    String\\<d>().to_s()
		CODE
		assert_equal 'yes', out
	end

	def test_tagged_type_can_be_aliased_and_retagged_through_the_alias
		out = Lost.interp <<~CODE
		    Flying { can_fly := true }
		    Duck | Flying { name := 'duck' }

		    String\\<val: Flying> {
		    	to_s (; "yes" )
		    }

		    duck := Duck()
		    Does_It_Fly := String\\<Flying>
		    Does_It_Fly\\<duck>().to_s()
		CODE
		assert_equal 'yes', out
	end

	def test_multi_member_reference_matches_via_composed_types_in_combination
		out = Lost.interp <<~CODE
		    Alpha { }
		    Beta { }
		    Combo_Alpha | Alpha { }
		    Combo_Beta | Beta { }

		    Thing\\<x: Alpha, y: Beta> {
		    	to_s (; "matched" )
		    }

		    Thing\\<Combo_Alpha(), Combo_Beta()>().to_s()
		CODE
		assert_equal 'matched', out
	end

	def test_unnamed_member_value_that_is_a_struct_spreads_into_the_struct
		type = Lost.interp <<~CODE
		    DEFAULT_COLUMNS := <id: Number, created_at: Number>
		    Thing\\<DEFAULT_COLUMNS> {}
		CODE
		assert_equal %w(id created_at), type.tag_declaration.names
		assert_equal %w(Number Number), type.tag_declaration.type_objects.map(&:name)
	end

	def test_spread_struct_members_bind_correctly_at_construction
		out = Lost.interp <<~CODE
		    DEFAULT_COLUMNS := <id: Number, created_at: Number>
		    Thing\\<DEFAULT_COLUMNS> {}

		    t := Thing\\<5, 1234>()
		    (t.tag.id, t.tag.created_at)
		CODE
		assert_equal [5, 1234], out.values
	end

	def test_reference_to_struct_valued_identifier_does_not_spread_regression
		out = Lost.interp <<~CODE
		    Options := <table_name: String, columns: Number>

		    Thing\\<opts: Options = Options> {
		    	new (;)
		    }

		    a := Thing\\<opts: Options>()
		    b := Thing\\<Options>()
		    (a.tag.opts, b.tag.opts)
		CODE
		refute_nil out.values[0]
		refute_nil out.values[1]
	end

	# Regression: a reference member named via the bare `:=` idiom (used to disambiguate an
	# otherwise-ambiguous match, e.g. `String<other := {x=1}>()`) bound the member's own *resolved
	# type* onto `.tag` instead of the real supplied value -- `interp_type`'s reference-resolution
	# read `supplied.type_objects` (identity-only, used for the "did they just restate the type"
	# check) where it should have read `supplied.values` for the actual result.
	def test_named_reference_member_preserves_the_real_supplied_value_regression
		out = Lost.interp <<~CODE
		    Data_Conn { name, new ( name; self.name = name ) }
		    Table\\<columns: Struct, database: Data_Conn> {}

		    cols := <name: String, age: Number>
		    db := Data_Conn('primary')

		    t := Table\\<columns := cols, database := db>
		    (t.tag.columns.names, t.tag.database.name)
		CODE
		assert_equal %w(name age), out.values[0].values
		assert_equal 'primary', out.values[1]
	end

	def test_redeclaring_same_tag_extends_the_same_variant
		out = Lost.interp <<~CODE
		    Abc\\<Number> {
		    	first (; 'first' )
		    }
		    Abc\\<Number> {
		    	second (; 'second' )
		    }

		    a := Abc\\<Number>()
		    (a.first(), a.second())
		CODE
		assert_equal %w(first second), out.values
	end

	# A tagged type declaration never bound its own bare name in @declarations the way a bare `Type { }` does -- only `Abc<Number>()` (a full reference) resolved it. When exactly one variant is declared under a name, the bare name is unambiguous, so it's reachable too now.
	def test_tagged_type_reachable_by_bare_name_when_unambiguous
		out = Lost.interp <<~CODE
		    Abc\\<Number> {
		    	greet (; 'hi' )
		    }
		    x := Abc()
		    x.greet()
		CODE
		assert_equal 'hi', out
	end

	# A genuinely ambiguous name (2+ declared variants) still can't resolve on its own -- there'd be no way to know which variant a bare `X()` should build.
	def test_tagged_type_bare_name_stays_unreachable_when_ambiguous
		assert_raises Lost::Undeclared_Identifier do
			Lost.interp <<~CODE
			    X\\<a: Number> {}
			    X\\<b: String> {}
			    X()
			CODE
		end
	end

	def test_string_tagged_with_a_dictionary
		src = <<~CODE
		    String\\<dict: Dictionary> {
		    	new ( str: String = "";
		    		value = str
		    	)
		    	to_s (;
		    		final := value
		    		final += "{"
		    		for tag.dict
		    			final += "`key`::`value`, "
		    		end
		    		final += "}"
		    	)
		    }
		    a := String\\<{x=0, y=1, z=2}>()
		    b := String\\<{x=0, y=1, z=2}>("My dict: ")
		    (a.to_s(), b.to_s())
		CODE
		out = Lost.interp src
		assert_equal '{x::0, y::1, z::2, }', out.values[0]
		assert_equal 'My dict: {x::0, y::1, z::2, }', out.values[1]
	end

	# Member#to_s used to check `if value`/`elif not value` (truthy) to mean "has a value" -- `false` is a legitimate value that's also falsy in Lost, so a member holding it looked exactly like one holding nothing at all (`<done: Bool>` instead of `<done: Bool = false>`).
	def test_member_display_shows_a_real_false_value_not_as_unset
		out = Lost.interp '<done := false>.to_s()'
		assert_equal '<done: Bool = false>', out
	end

	def test_bare_default_member_infers_type_from_value
		out = Lost.interp '<id := 4815>'
		assert_equal ['id'], out.names
		assert_equal ['Number'], out.type_names
		assert_equal [4815], out.values
	end

	def test_tagged_reference_has_members_populated
		out = Lost.interp <<~CODE
		    @load 'lost/struct.tape'
		    Abc\\<dict: Dictionary> {
		    	new (;)
		    }
		    z := Abc\\<{x=1}>
		    zz := z()
		    zz.tag.members
		CODE
		assert_equal 1, out.values.length
		assert_equal 'dict', out.values.first.name
	end

	def test_members_array_stays_positionally_aligned_with_unnamed_members
		out = Lost.interp <<~CODE
		    @load 'lost/struct.tape'
		    s := <name: String, Number>('Alice', 42)
		    s.members
		CODE
		assert_equal 2, out.values.length
		assert_equal 'name', out.values[0].name
		# .value is wrapped (Lost::String, carrying quotation_style) -- .value.value unwraps to the raw content.
		assert_equal 'Alice', out.values[0].value.value
		assert_nil out.values[1].name
		assert_equal 42, out.values[1].value
	end

	def test_bare_struct_literal_with_computed_value_parses
		assert_kind_of Lost::Struct, Lost.interp('<123>')
		assert_equal [3], Lost.interp('<1+2+3/123>').values
		assert_equal [3], Lost.interp('x := <1+2+3/123>
			x').values
	end

	# `for` over a Struct iterates its `.members` (Lost::Member instances, populated via `lost/struct.tape`, loaded by default) -- regression: used to call a nonexistent method and raise NoMethodError unconditionally.
	def test_for_loop_over_struct_iterates_members
		out = Lost.interp <<~CODE
		    s := <name: String, age: Number>('Alice', 30)
		    names := for s map
		        it.name
		    end
			names
		CODE
		assert_equal ['name', 'age'], out.values

		# With the standard library not loaded at all, a bare Struct has no `.members` to read (`lost/struct.tape` never ran) -- iterates zero elements rather than raising.
		refute_raises do
			out = Lost.interp(<<~CODE, load_standard_library: false)
			    s := <1, 2, 3>
			    count := 0
			    for s
			    	count += 1
			    end
				count
			CODE
			assert_equal 0, out
		end
	end

	# A struct member's only two named forms are `name: Type` and `name := value` -- there's no general `name: value` the way Dictionaries have. A lowercase value right after `:` used to be silently accepted: #parse_identifier_expr's own `: Type` lookahead declined to consume the `:` (since a lowercase identifier can never be a type), leaving it for the next loop iteration to reparse as an unrelated `:symbol` prefix literal -- `<columns: cols>` silently became the two elements `columns, :cols` instead of raising anywhere.
	def test_lowercase_value_after_colon_in_struct_raises
		assert_raises Lost::Invalid_Struct_Member_Annotation do
			Lost.interp 'columns := 99
				<columns: cols>'
		end
	end

	# The two legitimate ways to read as "two elements" instead: an explicit comma, or `:=` to actually give a member a value.
	def test_struct_still_supports_the_forms_that_look_similar
		out = Lost.interp 'columns := 99
			<columns, :cols>'
		assert_equal [99, :cols], out.values

		out = Lost.interp 'cols := <name: String>
			<columns := cols>'
		assert_kind_of Lost::Struct, out.values.first
	end

	def test_struct_typed_param_parses
		out   = Lost.parse 'f ( right: <name: String, type: Any, value: Any>; right )'
		param = out.first.parameters.first
		assert_kind_of Lost::Struct_Expr, param.type_struct
		assert_equal %w(name type value), param.type_struct.names
		assert_equal %w(String Any Any), param.type_struct.types.map { |member| member.type.value }
	end

	def test_struct_typed_param_accepts_structurally_compatible_argument
		refute_raises do
			out = Lost.interp "@load 'lost/member.tape'
				f ( right: <name: String, type: Any, value: Any>; right.name )
				m := Member('x', String, 4)
				f(m)"
			assert_equal 'x', out
		end
	end

	def test_struct_typed_param_raises_for_missing_member
		error = assert_raises Lost::Type_Contract_Violation do
			Lost.interp 'f ( right: <name: String, type: Any, value: Any>; right )
				f(nil)'
		end
		assert_equal '<name, type, value>', error.contract
	end

	def test_struct_typed_param_raises_for_wrong_member_type
		error = assert_raises Lost::Type_Contract_Violation do
			Lost.interp 'Thing { name := 4 }
				f ( right: <name: String>; right )
				f(Thing())'
		end
		assert_equal 'String', error.contract
		assert_equal 'Number', error.actual
	end

	def test_struct_typed_param_any_matches_anything
		refute_raises do
			out = Lost.interp "f ( right: <value: Any>; right.value )
				Thing { value := 4815 }
				f(Thing())"
			assert_equal 4815, out
		end
	end

	def test_struct_typed_param_works_on_operator_overloads
		refute_raises do
			out = Lost.interp "@load 'lost/member.tape'
				Thing {
					@operator ~ @infix ( left, right: <name: String>; right.name )
				}
				t := Thing()
				t ~ Member('x', String, 4)"
			assert_equal 'x', out
		end

		assert_raises Lost::Type_Contract_Violation do
			Lost.interp "Thing {
				@operator ~ @infix ( left, right: <name: String>; right.name )
			}
			t := Thing()
			t ~ nil"
		end
	end

	# A struct annotation with only unnamed members (`<String, Number>`, no names to check anything by) enforces nothing at all on a param -- there's no name on the argument to look up. Documenting the current, if surprising, behavior rather than letting it go unnoticed.
	def test_struct_typed_param_with_only_unnamed_members_enforces_nothing
		refute_raises do
			out = Lost.interp 'f ( x: <String, Number>; x )
				f(nil)'
			assert_nil out
		end
	end

	# `x: Abc\<Number>` (a named type plus a tag) parses the same way it already does for plain identifiers/variables.
	def test_named_type_plus_struct_param_parses
		out   = Lost.parse 'f ( x: Abc\\<Number>; x )'
		param = out.first.parameters.first
		assert_equal 'Abc', param.type.value
		assert_kind_of Lost::Struct_Expr, param.type_struct
		assert_equal 'Abc', param.type_struct.name
	end

	# --- `<>` immediately followed by `;`/`,` (no space) -- lexer regression ---

	def test_struct_close_immediately_followed_by_semicolon_lexes_correctly
		out    = Lost.lex '<String>;'
		values = out.map(&:value)
		assert_includes values, '>'
		assert_includes values, ';'
		refute_includes values, '>;'
	end

	def test_struct_close_immediately_followed_by_comma_lexes_correctly
		out    = Lost.lex '<String>,X'
		values = out.map(&:value)
		assert_includes values, '>'
		assert_includes values, ','
		refute_includes values, '>,'
	end

	# --- `\` named-reference tagged types (`Type\Struct`, no `<...>` at all) ---

	def test_named_reference_tagged_type_declaration
		type = Lost.interp <<~CODE
		    Task_Schema <a: Number, b: String>
		    Array\\Task_Schema {}
		CODE
		assert_equal ['a', 'b'], type.tag_declaration.names
	end

	# Regression: dispatch used to require a trailing `{`, which left the bare (no-body) reference form -- the "Reference: Type::Struct" your own spec called for -- unreachable.
	def test_named_reference_tagged_type_used_as_a_bare_value_regression
		out = Lost.interp <<~CODE
		    Task_Schema <a: Number, b: String>
		    Array\\Task_Schema {}
		    x := Array\\Task_Schema
		    x.tag.names
		CODE
		assert_equal ['a', 'b'], out.values
	end

	# `\Name` accepts a Struct or a Type (wrapped like `\<Type>` would build) -- a plain value isn't a valid target for either.
	def test_named_reference_must_resolve_to_a_type_or_struct
		assert_raises Lost::Tag_Reference_Must_Be_Type_Or_Struct do
			Lost.interp <<~CODE
			    X := 5
			    Array\\X {}
			CODE
		end
	end

	# Regression: `\Name` used to require Name to already be a Struct -- a bare Type reference
	# (`Array\String`) raised even though it's exactly equivalent to `Array\<String>`.
	def test_named_reference_to_a_type_behaves_like_the_equivalent_inline_literal
		out = Lost.interp <<~CODE
		    Array\\String {}
		    x := Array\\String
		    x.tag.types.first().name
		CODE
		assert_equal 'String', out
	end

	# --- Unifying declare/reference spread behavior ---

	# Regression: declaring spreads a lone unnamed Struct-valued member, but a reference to that same shape used to never spread -- so a reference/composition site could never reach a variant declared this way.
	def test_reference_matches_a_spread_declared_variant_regression
		out = Lost.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<Connection> {}
		    x := Container\\<Connection>
		    x.tag.names
		CODE
		assert_equal ['db', 'name'], out.values
	end

	# Same shape, reached through a composition operand (`X | Y\<...> {}`) rather than a plain
	# reference -- a separate parser code path (#parse_composition_expr) that needed its own fix.
	def test_composition_operand_with_named_reference_propagates_tag_regression
		out = Lost.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<Connection> {}
		    Tasks | Container\\<Connection> {}
		    Tasks.tag.names
		CODE
		assert_equal ['db', 'name'], out.values
	end

	# A composition chain can mix plain operands with both tagged-reference forms; ordinary `|` "leftmost wins" conflict rules still apply to the composed `tag` member itself.
	def test_composition_chain_mixes_plain_and_both_tagged_reference_forms
		out = Lost.interp <<~CODE
		    This { a := 1 }
		    That { b := 2 }
		    Here\\<> {}
		    Info <c: Number>
		    There\\Info {}

		    Combo | This | That | There\\Info | Here\\<> {}
		    x := Combo()
		    (x.a, x.b, Combo.tag.names)
		CODE
		a, b, tag_names = out.values
		assert_equal 1, a
		assert_equal 2, b
		assert_equal ['c'], tag_names.values
	end

	# An unspread reference that already matches (a real named member never spreads) should win outright -- spreading is only ever a fallback.
	def test_reference_prefers_unspread_match_before_retrying_with_spread
		out = Lost.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<conn: Connection> {}
		    Container\\<Connection> {}
		    x := Container\\<Connection>
		    x.tag.names
		CODE
		assert_equal ['conn'], out.values
	end

	# --- Bare Named Structs (`Ident <...>`, no `\`) interacting with real declared Types ---

	def test_bare_named_struct_conflicting_with_an_existing_type_raises
		assert_raises Lost::Undeclared_Tagged_Type do
			Lost.interp <<~CODE
			    Task\\<a: Number> {}
			    Task <b: String>
			CODE
		end
	end

	# --- Tag-aware `=X=` comparison operators ---

	# Regression: `interp_comparison_infix` read `tag_instance&.types` for a struct's per-member
	# types, but Lost::Struct < Instance < Type also inherits Type's own `.types` (the composed-type-name
	# Set, e.g. `Set['Struct']` -- the SAME for every struct regardless of its actual members), so a
	# plain Ruby method call shadowed the real per-member list. Every differently-tagged type compared
	# `===`-equal to every other one, no matter what it was actually tagged with.
	def test_differently_tagged_types_are_not_equal_regression
		out = Lost.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    (Abc\\<Number> === Abc\\<String>, Abc\\<Number> === Abc\\<Number>)
		CODE
		assert_equal [false, true], out.values
	end

	# `=!=`/`=>=`/`=<=`/`=/=` are all derived from the same tag-aware superset check `===` uses --
	# confirm the fix propagates to all four, not just `===` itself.
	def test_differently_tagged_types_via_the_other_comparison_operators_regression
		out = Lost.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    (Abc\\<Number> =!= Abc\\<String>, Abc\\<Number> =>= Abc\\<String>, Abc\\<Number> =<= Abc\\<String>, Abc\\<Number> =/= Abc\\<String>)
		CODE
		# =/= is disjointness of *composed types*, not tag -- both still compose "Abc", so they're not disjoint despite differing tags.
		assert_equal [true, false, false, false], out.values
	end

	# --- A struct member's own `: Type` annotation carrying a `\`-tag ---

	# `id: Array\String` parses `\String` onto the *annotation's* `.type_struct` (#parse_identifier_expr's
	# recursive `: Type` handling), a different AST shape than a bare `Array\String` reference -- #interp_struct
	# used to just `interpret` that annotation directly, silently resolving the untagged `Array` and dropping
	# the tag. `#interp_type_annotation` routes it through the same reference resolution a bare `Array\String`
	# already gets instead.
	def test_struct_member_type_annotation_resolves_named_reference_tag_regression
		out = Lost.interp <<~CODE
		    s := <id: Array\\String>
		    m := s.members.first()
		    (m.type.display_name, m.type.tag.type_names.first())
		CODE
		assert_equal %w(Array\\String String), out.values
	end

	# Same regression, but for the inline-literal tag form (`\<...>`) on the annotation -- exercises the
	# other branch of #parse_identifier_expr's `\`-consuming lookahead.
	def test_struct_member_type_annotation_resolves_inline_literal_tag_regression
		out = Lost.interp <<~CODE
		    s := <id: Array\\<String>>
		    m := s.members.first()
		    (m.type.display_name, m.type.tag.type_names.first())
		CODE
		assert_equal ['Array\\<String>', 'String'], out.values
	end

	# --- Nested `<...>` structs closing back-to-back (`>>`/`>>>` glued at the lexer level) ---

	# Two (or more) `<...>` structs closing with no space between them (`Array\<String>>`) lex as one
	# `>>` token -- a legitimate right-shift operator everywhere else, and a *higher*-precedence one than
	# a lone `>`, so ordinary expression parsing used to swallow it looking for a right-hand operand and
	# run out of tokens. #split_glued_close_angles! splits it back into individual `>` tokens, gated on
	# actually being inside a `<...>` (never firing for a real `8 >> 2`) and on a lone `>` being able to
	# stop parsing right there anyway.
	def test_nested_struct_closing_angles_parse_regression
		out = refute_raises Lost::Out_Of_Tokens do
			Lost.interp <<~CODE
			    s := <id: Array\\<String>>
			    s.members.first().type.tag.type_names.first()
			CODE
		end
		assert_equal 'String', out
	end

	# Three levels deep (`>>>`) -- confirms the fix isn't hardcoded to exactly two glued `>`s.
	def test_triple_nested_struct_closing_angles_parse_regression
		out = Lost.interp <<~CODE
		    s := <a: Array\\<b: Array\\<String>>>
		    s.members.first().type.tag.members.first().type.tag.type_names.first()
		CODE
		assert_equal 'String', out
	end

	# A genuine `>>`/chained `>>` (right-shift, nothing to do with structs) must keep working -- the fix
	# is gated on actually being inside a `<...>`, not just on precedence alone (an earlier version of
	# this fix broke exactly this, misfiring on the recursive right-hand-side parse of the *first* `>>`).
	def test_chained_real_shift_operator_unaffected_by_struct_close_fix_regression
		assert_equal 1, Lost.interp('8 >> 2 >> 1')
	end

	# --- Tag display mirrors how `\`'s RHS was actually written ---

	# `Array\<String>` (inline literal) and `Array\String` (bare reference) produce an *identically
	# shaped* single-unnamed-member struct at runtime -- shape alone can't tell them apart, so display
	# has to remember which form was actually written (Struct#bare_reference_name, set only for the bare
	# form) rather than guessing from the resolved struct's shape.
	def test_tag_display_distinguishes_bare_reference_from_inline_literal_with_same_shape_regression
		out = Lost.interp <<~CODE
		    a := Array\\String
		    b := Array\\<String>
		    (a.display_name, b.display_name)
		CODE
		assert_equal ['Array\\String', 'Array\\<String>'], out.values
	end

	# A bare reference to an already-declared *struct value* (as opposed to a Type) displays the same way.
	def test_tag_display_bare_reference_to_named_struct_value_regression
		out = Lost.interp <<~CODE
		    Named_Struct <a: Number>
		    Container\\Named_Struct {}
		    Container\\Named_Struct.display_name
		CODE
		assert_equal 'Container\\Named_Struct', out
	end
end
