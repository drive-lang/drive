require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Structs_Test < Base_Test
	def test_parses_standalone_struct_literal
		out = Drive.parse '<String, Number>'
		assert_kind_of Disk::Struct_Expr, out.first
		assert_equal %w(String Number), out.first.types.map(&:value)
	end

	def test_parses_standalone_struct_literal_with_single_type
		out = Drive.parse '<String>'
		assert_kind_of Disk::Struct_Expr, out.first
		assert_equal %w(String), out.first.types.map(&:value)
	end

	def test_parses_type_declaration_with_struct
		out = Drive.parse 'Array\\<String> {}'
		assert_kind_of Disk::Type_Expr, out.first
		assert_equal 'Array', out.first.name
		assert_kind_of Disk::Struct_Expr, out.first.tag
		assert_equal %w(String), out.first.tag.types.map(&:value)
	end

	def test_parses_type_declaration_with_multiple_members
		out = Drive.parse 'Dictionary\\<String, Number> {}'
		assert_equal %w(String Number), out.first.tag.types.map(&:value)
	end

	def test_type_declaration_without_struct_has_nil_struct
		out = Drive.parse 'String {}'
		assert_nil out.first.tag
	end

	def test_struct_members_can_be_arbitrary_expressions
		out = Drive.parse 'Abc\\<1+2+3/123>'
		assert_kind_of Disk::Infix_Expr, out.first.tag.types.first

		result = Drive.interp "Abc {}
		Abc\\<Number> {}
		Abc\\<1+2+3/123>.tag.@types.first()"
		assert_equal 3, result
	end

	# `Primary_Key\123` (no angle brackets) is a version tag -- sugar for `Primary_Key\<123>`. Both spell
	# the same single-unnamed-member struct, in a declaration, a bare reference, and a `: Type` annotation.
	def test_bare_integer_version_tag_matches_the_bracketed_form
		bare    = Drive.parse 'Abc\\7'
		bracket = Drive.parse 'Abc\\<7>'
		assert_equal bracket.first.tag.types.map(&:value), bare.first.tag.types.map(&:value)
		assert_equal bracket.first.tag.names, bare.first.tag.names

		# Declaration then reference resolves, same as the bracketed form.
		bare_type = Drive.interp "Abc\\7 {}\nAbc\\7"
		assert_kind_of Disk::Type, bare_type

		# As a struct member annotation, the surrounding named struct still registers -- the misparse this
		# guards against used to leave `\` and `123` as two extra nil-named members, which silently
		# stopped `Thing` from being declared at all.
		names = Drive.interp "Abc\\9 {}\nThing <id: Abc\\9, text: String>\nThing.@names"
		assert_equal %w(id text), names.values
	end

	# A dotted number (`\1.5`, `\1.2.3`) is not a version tag -- only a plain run of digits is.
	def test_non_integer_after_tag_operator_is_not_a_version_tag
		parsed = Drive.parse 'x: Abc\\1.5'
		assert_nil parsed.first.tag
	end

	def test_interprets_standalone_struct_literal_to_struct_instance
		out = Drive.interp '<String, Number>'
		assert_kind_of Disk::Struct, out
		assert_equal 'String', out.type_objects[0].name
		assert_equal 'Number', out.type_objects[1].name
	end

	def test_struct_instance_types_accessible_from_disk
		out = Drive.interp "g := <String, Number>
		g.@types"
		assert_equal 'String', out.values[0].name
		assert_equal 'Number', out.values[1].name
	end

	def test_bare_struct_assignable_and_storable
		# A bare annotation alone on its own line (no `=` on the same expression) is undeclared, same as any other annotation (`x: Number` alone behaves identically) — combine the annotation and assignment into one expression, which is how self-declaring annotations actually work today.
		out = Drive.interp 'thing: <String, Number> = <String, Number>
		thing.@types.count'
		assert_equal 2, out
	end

	def test_type_with_struct_still_composes_normally
		refute_raises do
			out = Drive.interp 'Array\\<String> {}'
			assert_kind_of Disk::Type, out
			assert_equal 'Array', out.name
		end
	end

	def test_composing_builtin_type_with_struct_does_not_break_it
		out = Drive.interp <<~CODE
		    String\\<Dictionary> {}
		    s := String('hello')
		    s.upcase()
		CODE
		assert_equal 'HELLO', out
	end

	def test_struct_does_not_interfere_with_plain_type_declarations
		out = Drive.interp <<~CODE
		    Point {
		    	x, y,
		    	Self ( x, y;
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
		out = Drive.parse 'x: Abc\\<Number>'
		assert_kind_of Disk::Struct_Expr, out.first.tag
		assert_equal %w(Number), out.first.tag.types.map(&:value)
	end

	def test_bare_struct_annotation_with_no_type_name
		out = Drive.parse 'thing: <String, Number>'
		assert_kind_of Disk::Struct_Expr, out.first.type
		assert_equal %w(String Number), out.first.type.types.map(&:value)
	end

	def test_type_reference_with_struct_does_not_mutate_shared_type
		out = Drive.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    x := Abc\\<Number>
		    y := Abc\\<String>
		    (x.tag.@types.first(), y.tag.@types.first())
		CODE
		assert_equal 'Number', out.values[0].name
		assert_equal 'String', out.values[1].name
	end

	def test_type_reference_works_with_constants_too
		out = Drive.interp <<~CODE
		    Abc {
		    	val,
		    	Self ( v; self.val = v )
		    }
		    Abc\\<Number> {}
		    Y := Abc\\<Number>
		    Y(9).val
		CODE
		assert_equal 9, out
	end

	def test_type_reference_can_be_reassigned_before_calling
		out = Drive.interp <<~CODE
		    Abc {
		    	val,
		    	Self ( v; self.val = v )
		    }
		    Abc\\<Number> {}
		    y := Abc\\<Number>
		    z := y
		    z(5).val
		CODE
		assert_equal 5, out
	end

	def test_struct_bound_onto_instance_before_self_runs
		out = Drive.interp <<~CODE
		    Abc\\<Number> {
		    	Self (;)
		    }
		    z := Abc\\<4815>
		    zz := z()
		    zz.tag.@types.first()
		CODE
		assert_equal 4815, out
	end

	def test_struct_members_are_not_forwarded_as_constructor_arguments
		out = Drive.interp <<~CODE
		    Abc {
		    	val,
		    	Self ( v := -1; self.val = v )
		    }
		    Abc\\<Number> {}
		    zz := Abc\\<4815>()
		    zz.val
		CODE
		assert_equal(-1, out)
	end

	def test_named_member_schema_parses_and_resolves_declared_type
		out = Drive.parse 'Type\\<some_string: String, num: Number> {}'
		assert_equal ['some_string', 'num'], out.first.tag.names

		type = Drive.interp 'Type\\<some_string: String, num: Number> {}'
		assert_equal ['some_string', 'num'], type.tag_declaration.names
		assert_equal ['String', 'Number'], type.tag_declaration.type_names
	end

	def test_unset_named_typed_member_reads_as_nil_not_the_declared_type
		# `<flag: Bool>` with no value used to resolve `thing.flag` to the Bool *type* object (truthy!),
		# breaking every `if thing.flag` check. It must read as nil, same as `x: Number` everywhere else.
		out = Drive.interp <<~CODE
		    thing := <flag: Bool, count: Number>
		    (thing.flag, thing.count)
		CODE
		assert_nil out.values[0]
		assert_nil out.values[1]
	end

	def test_tag_declaration_captures_default_values
		type = Drive.interp 'Widget\\<indent: Number = 2> {}'
		assert_equal ['indent'], type.tag_declaration.names
		assert_equal [2], type.tag_declaration.values
	end

	def test_untagged_declaration_has_no_tag_declaration
		type = Drive.interp 'Plain { x, }'
		assert_nil type.tag_declaration
	end

	def test_tag_declaration_is_independent_per_variant
		out = Drive.interp <<~CODE
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
		dict_a = Disk::Struct.new(['dict'], ['Dictionary'], [nil])
		dict_b = Disk::Struct.new(['dict'], ['Dictionary'], [nil])
		other  = Disk::Struct.new(['other'], ['Dictionary'], [nil]) # same type, different name
		number = Disk::Struct.new(['dict'], ['Number'], [nil]) # same name, different type

		assert dict_a.structure_declaration_equal?(dict_b)
		refute dict_a.structure_declaration_equal?(other)
		refute dict_a.structure_declaration_equal?(number)
	end

	# Reference matching (`String<{x=1}>()`) never supplies member names, so it only ever compares
	# against `type_names` -- names exist purely to keep declarations distinct from each other.
	def test_tag_satisfied_by_candidates_ignores_names
		declared = Disk::Struct.new(['dict'], ['Dictionary'], [nil])

		assert declared.satisfied_by_candidates?([['Dictionary']])
		refute declared.satisfied_by_candidates?([['Number']])
	end

	def test_differently_named_same_typed_members_are_distinct_variants_regression
		out = Drive.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<{x=1}>()
		    a.to_s()
		CODE
		assert_equal 'dict-named', out

		out = Drive.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<other := {x=1}>()
		    a.to_s()
		CODE
		assert_equal 'other-named', out

		out = Drive.interp <<~CODE
		    String\\<dict: Dictionary> { to_s (; "dict-named" ) }
		    String\\<other: Dictionary> { to_s (; "other-named" ) }

		    a := String\\<dict := {x=1}>()
		    a.to_s()
		CODE
		assert_equal 'dict-named', out
	end

	def test_reference_to_never_declared_type_name_builds_a_bare_named_struct
		# `Ident<...>` with a base name that's never been declared as anything at all (no bare Type, no tagged variant, no alias) isn't an error -- it's a bare named struct, same shape as `<...>` but with `.name` set from the identifier. Only collides with something else declared -- a real Type with a mismatched tag, or an alias to a non-Type value -- does it still raise (see test_reference_to_mismatched_declared_tag_raises).
		out = Drive.interp <<~CODE
		    n := Named\\<Number>
		    n.@name
		CODE
		assert_equal 'Named', out

		out = Drive.interp <<~CODE
		    n := Named\\<Number>
		    n.@types.values.map((it; it.@name)).join(', ')
		CODE
		assert_equal 'Number', out
	end

	# A bare named struct whose own member references the struct's own name used to raise
	# Undeclared_Identifier -- the name wasn't declared until after every member was resolved.
	# Now an empty stand-in is declared first (like a bare Type before its body runs), and
	# #register_bare_named_struct swaps the finished struct in.
	def test_bare_named_struct_can_reference_itself
		out = Drive.interp <<~CODE
		    Node <
		    	name: String
		    	parent: Node
		    >
		    n := Node
		    (n.@type_names, n.@types.get(1) == Node)
		CODE
		assert_equal %w(String Node), out.values[0].values
		assert_equal true, out.values[1] # the `parent` slot points at the finished Node, not the stand-in
	end

	# The forward-declaration machinery already hoists a `Struct_Expr`, so the self-referencing
	# stand-in also unblocks two structs that reference each other.
	def test_mutually_referential_bare_named_structs
		out = Drive.interp <<~CODE
		    A <partner: B>
		    B <partner: A>
		    (A.@type_names, B.@type_names)
		CODE
		assert_equal %w(B), out.values[0].values
		assert_equal %w(A), out.values[1].values
	end

	# An empty `Name <>` is a forward declaration -- a later `Name <...>` fills it in rather than
	# raising the different-shape error (which still applies to two genuinely non-empty shapes). This
	# is the spelling that lets `enclosing_scope: Scope` resolve inside `disks/scopes.disk` without
	# the one-shot self-reference above.
	def test_empty_bare_named_struct_is_a_forward_declaration
		out = Drive.interp <<~CODE
		    Scope <>
		    Scope <
		    	name: String
		    	parent: Scope
		    >
		    s := Scope
		    (s.@type_names, s.@types.get(1) == Scope)
		CODE
		assert_equal %w(String Scope), out.values[0].values
		assert_equal true, out.values[1]
	end

	# `Empty <>` on its own (never filled in) is just an empty struct, not an Undeclared_Identifier.
	def test_empty_bare_named_struct_on_its_own
		out = Drive.interp <<~CODE
		    Empty <>
		    (Empty.@name, Empty.@names)
		CODE
		assert_equal 'Empty', out.values[0]
		assert_equal [], out.values[1].values
	end

	# Filling in a forward declaration and *then* trying a third, different shape still raises --
	# only the empty placeholder is special, not every prior shape.
	def test_forward_declared_struct_still_rejects_a_later_shape_change
		assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
			    N <>
			    N <a: Number>
			    N <a: String>
			CODE
		end
	end

	# Re-declaring the exact same bare named struct a second time used to raise Undeclared_Type_Structure -- `aliased` (the struct from the first declaration) being non-nil blocked the bare-named-struct fallback, even though the shape hadn't actually changed.
	def test_redeclaring_same_bare_named_struct_is_a_no_op
		refute_raises do
			out = Drive.interp <<~CODE
			    Task <
			    	id: Number
			    	done := false
			    >
			    Task <
			    	id: Number
			    	done := false
			    >
			    Task.@name
			CODE
			assert_equal 'Task', out
		end
	end

	# A genuinely different shape under the same name still raises, unchanged.
	def test_redeclaring_bare_named_struct_with_a_different_shape_still_raises
		assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
			    Task <id: Number>
			    Task <id: String>
			CODE
		end
	end

	# A name, not position, identifies a named member everywhere it's actually used -- reordering named members is still the same declaration, not a different one.
	def test_redeclaring_bare_named_struct_with_reordered_members_is_a_no_op
		out = Drive.interp <<~CODE
		    Task <id: Number, done: Bool>
		    Task <done: Bool, id: Number>
		    Task.@name
		CODE
		assert_equal 'Task', out
	end

	# Not just "doesn't raise" -- the actual member set is unchanged by the reorder, before and after.
	def test_redeclaring_bare_named_struct_with_reordered_members_keeps_the_same_members
		out = Drive.interp <<~CODE
		    before := Task <id: Number, done: Bool>
		    after := Task <done: Bool, id: Number>
		    (before.@names, before.@type_names, after.@names, after.@type_names)
		CODE
		before_members = out.values[0].values.zip(out.values[1].values).sort
		after_members  = out.values[2].values.zip(out.values[3].values).sort

		assert_equal [%w(done Bool), %w(id Number)], before_members
		assert_equal before_members, after_members
	end

	# Unnamed members have no such identity besides position -- reordering those still counts as a different tag and raises, same as any other shape mismatch.
	def test_redeclaring_unnamed_tagged_type_with_reordered_members_still_raises
		assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
			    Abc\\<Number, String> {}
			    Abc\\<String, Number>
			CODE
		end
	end

	def test_reference_to_mismatched_declared_tag_raises
		assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
			    Abc\\<Number> {}
			    Abc\\<String>
			CODE
		end
	end

	# Undeclared_Type_Structure's own message-rendering used to crash (NoMethodError inside Struct_Expr#to_s) when the mismatched struct had a named member with no `: Type` annotation (`done := false` -- `.type` is nil, unlike `.type.value` this code blindly read). assert_raises here would surface that NoMethodError instead of the real error if this regressed.
	def test_mismatched_structure_error_message_renders_untyped_member_without_crashing
		error = assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
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
		type = Drive.interp <<~CODE
		    DEFAULT_COLUMNS := <id: Number, created_at: Number>
		    Thing\\<DEFAULT_COLUMNS> {}
		CODE
		assert_equal %w(id created_at), type.tag_declaration.names
		assert_equal %w(Number Number), type.tag_declaration.type_objects.map(&:name)
	end

	def test_spread_struct_members_bind_correctly_at_construction
		out = Drive.interp <<~CODE
		    DEFAULT_COLUMNS := <id: Number, created_at: Number>
		    Thing\\<DEFAULT_COLUMNS> {}

		    t := Thing\\<5, 1234>()
		    (t.tag.id, t.tag.created_at)
		CODE
		assert_equal [5, 1234], out.values
	end

	def test_reference_to_struct_valued_identifier_does_not_spread_regression
		out = Drive.interp <<~CODE
		    Options := <table_name: String, columns: Number>

		    Thing\\<opts: Options = Options> {
		    	Self (;)
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
		out = Drive.interp <<~CODE
		    Data_Conn { name, Self ( name; self.name = name ) }
		    Table\\<columns: Struct, database: Data_Conn> {}

		    cols := <name: String, age: Number>
		    db := Data_Conn('primary')

		    t := Table\\<columns := cols, database := db>
		    (t.tag.columns.@names, t.tag.database.name)
		CODE
		assert_equal %w(name age), out.values[0].values
		assert_equal 'primary', out.values[1]
	end

	def test_redeclaring_same_tag_extends_the_same_variant
		out = Drive.interp <<~CODE
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
		out = Drive.interp <<~CODE
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
		assert_raises Disk::Undeclared_Identifier do
			Drive.interp <<~CODE
			    X\\<a: Number> {}
			    X\\<b: String> {}
			    X()
			CODE
		end
	end

	def test_string_tagged_with_a_dictionary
		src = <<~CODE
		    String\\<dict: Dictionary> {
		    	Self ( str: String = "";
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
		out = Drive.interp src
		assert_equal '{x::0, y::1, z::2, }', out.values[0]
		assert_equal 'My dict: {x::0, y::1, z::2, }', out.values[1]
	end

	# Member#to_s used to check `if value`/`elif not value` (truthy) to mean "has a value" -- `false` is a legitimate value that's also falsy in Drive, so a member holding it looked exactly like one holding nothing at all (`<done: Bool>` instead of `<done: Bool = false>`).
	def test_member_display_shows_a_real_false_value_not_as_unset
		out = Drive.interp '<done := false>.to_s()'
		assert_equal '<done: Bool = false>', out
	end

	def test_bare_default_member_infers_type_from_value
		out = Drive.interp '<id := 4815>'
		assert_equal ['id'], out.names
		assert_equal ['Number'], out.type_names
		assert_equal [4815], out.values
	end

	def test_tagged_reference_has_members_populated
		out = Drive.interp <<~CODE
		    @load 'disks/struct.disk'
		    Abc\\<dict: Dictionary> {
		    	Self (;)
		    }
		    z := Abc\\<{x=1}>
		    zz := z()
		    zz.tag.@members
		CODE
		assert_equal 1, out.values.length
		assert_equal 'dict', out.values.first.name
	end

	def test_members_array_stays_positionally_aligned_with_unnamed_members
		out = Drive.interp <<~CODE
		    @load 'disks/struct.disk'
		    s := <name: String, Number>('Alice', 42)
		    s.@members
		CODE
		assert_equal 2, out.values.length
		assert_equal 'name', out.values[0].name
		# .value is wrapped (Disk::String, carrying quotation_style) -- .value.value unwraps to the raw content.
		assert_equal 'Alice', out.values[0].value.value
		assert_nil out.values[1].name
		assert_equal 42, out.values[1].value
	end

	def test_bare_struct_literal_with_computed_value_parses
		assert_kind_of Disk::Struct, Drive.interp('<123>')
		assert_equal [3], Drive.interp('<1+2+3/123>').values
		assert_equal [3], Drive.interp('x := <1+2+3/123>
			x').values
	end

	# `for` over a Struct iterates its `.members` (Disk::Member instances, populated via `disks/struct.disk`, loaded by default) -- regression: used to call a nonexistent method and raise NoMethodError unconditionally.
	def test_for_loop_over_struct_iterates_members
		out = Drive.interp <<~CODE
		    s := <name: String, age: Number>('Alice', 30)
		    names := for s map
		        it.name
		    end
			names
		CODE
		assert_equal ['name', 'age'], out.values

		# With the standard library not loaded at all, a bare Struct has no `.members` to read (`disks/struct.disk` never ran) -- iterates zero elements rather than raising.
		refute_raises do
			out = Drive.interp(<<~CODE, load_standard_library: false)
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
		assert_raises Disk::Invalid_Struct_Member_Annotation do
			Drive.interp 'columns := 99
				<columns: cols>'
		end
	end

	# The two legitimate ways to read as "two elements" instead: an explicit comma, or `:=` to actually give a member a value.
	def test_struct_still_supports_the_forms_that_look_similar
		out = Drive.interp 'columns := 99
			<columns, :cols>'
		assert_equal [99, :cols], out.values

		out = Drive.interp 'cols := <name: String>
			<columns := cols>'
		assert_kind_of Disk::Struct, out.values.first
	end

	# A struct member's type can be a func signature (`to_s: (-> String;)`) -- looks like a function
	# declaration but is strictly struct syntax; it's a named member whose type is a Func_Signature.
	def test_struct_member_can_be_typed_with_a_func_signature
		out = Drive.parse 'Api <name: String, run: (Number -> Number;), reset: (;)>'
		assert_equal %w(name run reset), out.first.names
		assert_kind_of Disk::Func_Signature_Expr, out.first.types[1]
		assert_kind_of Disk::Func_Signature_Expr, out.first.types[2] # no return type, still a signature via the `:` form

		# The member is a real, named slot -- nil until assigned, name reflected.
		out = Drive.interp <<~CODE
		    Api <name: String, run: (Number -> Number;)>
		    api := Api
		    (api.@names.values, api.run)
		CODE
		assert_equal %w(name run), out.values[0]
		assert_nil out.values[1]
	end

	def test_struct_typed_param_parses
		out   = Drive.parse 'f ( right: <name: String, type: Any, value: Any>; right )'
		param = out.first.parameters.first
		assert_kind_of Disk::Struct_Expr, param.type
		assert_equal %w(name type value), param.type.names
		assert_equal %w(String Any Any), param.type.types.map { |member| member.type.value }
	end

	def test_struct_typed_param_accepts_structurally_compatible_argument
		refute_raises do
			out = Drive.interp "@load 'disks/member.disk'
				f ( right: <name: String, type: Any, value: Any>; right.name )
				m := Member('x', String, 4)
				f(m)"
			assert_equal 'x', out
		end
	end

	def test_struct_typed_param_raises_for_missing_member
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'f ( right: <name: String, type: Any, value: Any>; right )
				f(nil)'
		end
		assert_equal '<name, type, value>', error.contract
	end

	def test_struct_typed_param_raises_for_wrong_member_type
		error = assert_raises Disk::Type_Contract_Violation do
			Drive.interp 'Thing { name := 4 }
				f ( right: <name: String>; right )
				f(Thing())'
		end
		assert_equal 'String', error.contract
		assert_equal 'Number', error.actual
	end

	def test_struct_typed_param_any_matches_anything
		refute_raises do
			out = Drive.interp "f ( right: <value: Any>; right.value )
				Thing { value := 4815 }
				f(Thing())"
			assert_equal 4815, out
		end
	end

	def test_struct_typed_param_works_on_operator_overloads
		refute_raises do
			out = Drive.interp "@load 'disks/member.disk'
				Thing {
					@operator ~ @infix ( left, right: <name: String>; right.name )
				}
				t := Thing()
				t ~ Member('x', String, 4)"
			assert_equal 'x', out
		end

		assert_raises Disk::Type_Contract_Violation do
			Drive.interp "Thing {
				@operator ~ @infix ( left, right: <name: String>; right.name )
			}
			t := Thing()
			t ~ nil"
		end
	end

	# A struct annotation with only unnamed members (`<String, Number>`, no names to check anything by) enforces nothing at all on a param -- there's no name on the argument to look up. Documenting the current, if surprising, behavior rather than letting it go unnoticed.
	def test_struct_typed_param_with_only_unnamed_members_enforces_nothing
		refute_raises do
			out = Drive.interp 'f ( x: <String, Number>; x )
				f(nil)'
			assert_nil out
		end
	end

	# `x: Abc\<Number>` (a named type plus a tag) parses the same way it already does for plain identifiers/variables -- reachable as param.type.tag, same as any other type annotation (no separate Param_Expr#tag; that duplicated what param.type.tag already gives you).
	def test_named_type_plus_struct_param_parses
		out   = Drive.parse 'f ( x: Abc\\<Number>; x )'
		param = out.first.parameters.first
		assert_equal 'Abc', param.type.value
		assert_kind_of Disk::Struct_Expr, param.type.tag
		assert_equal 'Abc', param.type.tag.name
	end

	# --- `<>` immediately followed by `;`/`,` (no space) -- lexer regression ---

	def test_struct_close_immediately_followed_by_semicolon_lexes_correctly
		out    = Drive.lex '<String>;'
		values = out.map(&:value)
		assert_includes values, '>'
		assert_includes values, ';'
		refute_includes values, '>;'
	end

	def test_struct_close_immediately_followed_by_comma_lexes_correctly
		out    = Drive.lex '<String>,X'
		values = out.map(&:value)
		assert_includes values, '>'
		assert_includes values, ','
		refute_includes values, '>,'
	end

	# --- `\` named-reference tagged types (`Type\Struct`, no `<...>` at all) ---

	def test_named_reference_tagged_type_declaration
		type = Drive.interp <<~CODE
		    Task_Schema <a: Number, b: String>
		    Array\\Task_Schema {}
		CODE
		assert_equal ['a', 'b'], type.tag_declaration.names
	end

	# Regression: dispatch used to require a trailing `{`, which left the bare (no-body) reference form -- the "Reference: Type::Struct" your own spec called for -- unreachable.
	def test_named_reference_tagged_type_used_as_a_bare_value_regression
		out = Drive.interp <<~CODE
		    Task_Schema <a: Number, b: String>
		    Array\\Task_Schema {}
		    x := Array\\Task_Schema
		    x.tag.@names
		CODE
		assert_equal ['a', 'b'], out.values
	end

	# `\Name` accepts a Struct or a Type (wrapped like `\<Type>` would build) -- a plain value isn't a valid target for either.
	def test_named_reference_must_resolve_to_a_type_or_struct
		assert_raises Disk::Tag_Reference_Must_Be_Type_Or_Struct do
			Drive.interp <<~CODE
			    X := 5
			    Array\\X {}
			CODE
		end
	end

	# Regression: `\Name` used to require Name to already be a Struct -- a bare Type reference
	# (`Array\String`) raised even though it's exactly equivalent to `Array\<String>`.
	def test_named_reference_to_a_type_behaves_like_the_equivalent_inline_literal
		out = Drive.interp <<~CODE
		    Array\\String {}
		    x := Array\\String
		    x.tag.@types.first().@name
		CODE
		assert_equal 'String', out
	end

	# --- Unifying declare/reference spread behavior ---

	# Regression: declaring spreads a lone unnamed Struct-valued member, but a reference to that same shape used to never spread -- so a reference/composition site could never reach a variant declared this way.
	def test_reference_matches_a_spread_declared_variant_regression
		out = Drive.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<Connection> {}
		    x := Container\\<Connection>
		    x.tag.@names
		CODE
		assert_equal ['db', 'name'], out.values
	end

	# Same shape, reached through a composition operand (`X | Y\<...> {}`) rather than a plain
	# reference -- a separate parser code path (#parse_composition_expr) that needed its own fix.
	def test_composition_operand_with_named_reference_propagates_tag_regression
		out = Drive.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<Connection> {}
		    Tasks | Container\\<Connection> {}
		    Tasks.tag.@names
		CODE
		assert_equal ['db', 'name'], out.values
	end

	# A composition chain can mix plain operands with both tagged-reference forms; ordinary `|` "leftmost wins" conflict rules still apply to the composed `tag` member itself.
	def test_composition_chain_mixes_plain_and_both_tagged_reference_forms
		out = Drive.interp <<~CODE
		    This { a := 1 }
		    That { b := 2 }
		    Here\\<> {}
		    Info <c: Number>
		    There\\Info {}

		    Combo | This | That | There\\Info | Here\\<> {}
		    x := Combo()
		    (x.a, x.b, Combo.tag.@names)
		CODE
		a, b, tag_names = out.values
		assert_equal 1, a
		assert_equal 2, b
		assert_equal ['c'], tag_names.values
	end

	# An unspread reference that already matches (a real named member never spreads) should win outright -- spreading is only ever a fallback.
	def test_reference_prefers_unspread_match_before_retrying_with_spread
		out = Drive.interp <<~CODE
		    Connection <db: Number, name: String>
		    Container\\<conn: Connection> {}
		    Container\\<Connection> {}
		    x := Container\\<Connection>
		    x.tag.@names
		CODE
		assert_equal ['conn'], out.values
	end

	# --- Bare Named Structs (`Ident <...>`, no `\`) interacting with real declared Types ---

	def test_bare_named_struct_conflicting_with_an_existing_type_raises
		assert_raises Disk::Undeclared_Tagged_Type do
			Drive.interp <<~CODE
			    Task\\<a: Number> {}
			    Task <b: String>
			CODE
		end
	end

	# --- Tag-aware `=X=` comparison operators ---

	# Regression: `interp_comparison_infix` read `tag_instance&.types` for a struct's per-member
	# types, but Disk::Struct < Instance < Type also inherits Type's own `.types` (the composed-type-name
	# Set, e.g. `Set['Struct']` -- the SAME for every struct regardless of its actual members), so a
	# plain Ruby method call shadowed the real per-member list. Every differently-tagged type compared
	# `===`-equal to every other one, no matter what it was actually tagged with.
	def test_differently_tagged_types_are_not_equal_regression
		out = Drive.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    (Abc\\<Number> === Abc\\<String>, Abc\\<Number> === Abc\\<Number>)
		CODE
		assert_equal [false, true], out.values
	end

	# `=!=`/`=>=`/`=<=`/`=/=` are all derived from the same tag-aware superset check `===` uses --
	# confirm the fix propagates to all four, not just `===` itself.
	def test_differently_tagged_types_via_the_other_comparison_operators_regression
		out = Drive.interp <<~CODE
		    Abc\\<Number> {}
		    Abc\\<String> {}
		    (Abc\\<Number> =!= Abc\\<String>, Abc\\<Number> =>= Abc\\<String>, Abc\\<Number> =<= Abc\\<String>, Abc\\<Number> =/= Abc\\<String>)
		CODE
		# =/= is disjointness of *composed types*, not tag -- both still compose "Abc", so they're not disjoint despite differing tags.
		assert_equal [true, false, false, false], out.values
	end

	# --- A struct member's own `: Type` annotation carrying a `\`-tag ---

	# `id: Array\String` parses `\String` onto the *annotation's* `.tag` (#parse_identifier_expr's
	# recursive `: Type` handling), a different AST shape than a bare `Array\String` reference -- #interp_struct
	# used to just `interpret` that annotation directly, silently resolving the untagged `Array` and dropping
	# the tag. `#interp_type_annotation` routes it through the same reference resolution a bare `Array\String`
	# already gets instead.
	def test_struct_member_type_annotation_resolves_named_reference_tag_regression
		out = Drive.interp <<~CODE
		    s := <id: Array\\String>
		    m := s.@members.first()
		    (m.type.@display_name, m.type.tag.@type_names.first())
		CODE
		assert_equal %w(Array\\String String), out.values
	end

	# Same regression, but for the inline-literal tag form (`\<...>`) on the annotation -- exercises the
	# other branch of #parse_identifier_expr's `\`-consuming lookahead.
	def test_struct_member_type_annotation_resolves_inline_literal_tag_regression
		out = Drive.interp <<~CODE
		    s := <id: Array\\<String>>
		    m := s.@members.first()
		    (m.type.@display_name, m.type.tag.@type_names.first())
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
		out = refute_raises Disk::Out_Of_Tokens do
			Drive.interp <<~CODE
			    s := <id: Array\\<String>>
			    s.@members.first().type.tag.@type_names.first()
			CODE
		end
		assert_equal 'String', out
	end

	# Three levels deep (`>>>`) -- confirms the fix isn't hardcoded to exactly two glued `>`s.
	def test_triple_nested_struct_closing_angles_parse_regression
		out = Drive.interp <<~CODE
		    s := <a: Array\\<b: Array\\<String>>>
		    s.@members.first().type.tag.@members.first().type.tag.@type_names.first()
		CODE
		assert_equal 'String', out
	end

	# A genuine `>>`/chained `>>` (right-shift, nothing to do with structs) must keep working -- the fix
	# is gated on actually being inside a `<...>`, not just on precedence alone (an earlier version of
	# this fix broke exactly this, misfiring on the recursive right-hand-side parse of the *first* `>>`).
	def test_chained_real_shift_operator_unaffected_by_struct_close_fix_regression
		assert_equal 1, Drive.interp('8 >> 2 >> 1')
	end

	# --- Tag display mirrors how `\`'s RHS was actually written ---

	# `Array\<String>` (inline literal) and `Array\String` (bare reference) produce an *identically
	# shaped* single-unnamed-member struct at runtime -- shape alone can't tell them apart, so display
	# has to remember which form was actually written (Struct#bare_reference_name, set only for the bare
	# form) rather than guessing from the resolved struct's shape.
	def test_tag_display_distinguishes_bare_reference_from_inline_literal_with_same_shape_regression
		out = Drive.interp <<~CODE
		    a := Array\\String
		    b := Array\\<String>
		    (a.@display_name, b.@display_name)
		CODE
		assert_equal ['Array\\String', 'Array\\<String>'], out.values
	end

	# A bare reference to an already-declared *struct value* (as opposed to a Type) displays the same way.
	def test_tag_display_bare_reference_to_named_struct_value_regression
		out = Drive.interp <<~CODE
		    Named_Struct <a: Number>
		    Container\\Named_Struct {}
		    Container\\Named_Struct.@display_name
		CODE
		assert_equal 'Container\\Named_Struct', out
	end

	# --- Tag chains (`Ab\Cd\Ef`) ---

	def test_tag_chain_parses_into_nested_tag
		t = Drive.parse('Array\\A\\B\\C { }').first
		assert_equal 'A', t.tag.value
		assert_equal 'B', t.tag.tag.value
		assert_equal 'C', t.tag.tag.tag.value
	end

	def test_tag_chain_readable_at_each_level
		out = Drive.interp <<~CODE
		    A {} B {} C {}
		    Thing\\A\\B\\C {
		        probe (; [self.tag.@type_names.0, self.tag.tag.@type_names.0, self.tag.tag.tag.@type_names.0] )
		    }
		    Thing\\A\\B\\C().probe()
		CODE
		assert_equal %w(A B C), out.values
	end

	# Two chains sharing a prefix are distinct variants with distinct bodies.
	def test_tag_chains_with_shared_prefix_are_distinct_variants
		out = Drive.interp <<~CODE
		    A {} B {} C {}
		    Thing\\A\\B { which (; 'B' ) }
		    Thing\\A\\C { which (; 'C' ) }
		    (Thing\\A\\B().which(), Thing\\A\\C().which())
		CODE
		assert_equal %w(B C), out.values
	end

	# --- Runtime `.tag =` ---

	def test_tag_reassignment_accepts_a_value_that_composes_the_current_tag
		out = Drive.interp <<~CODE
		    Base {} Sub | Base {}
		    Thing\\Base {}
		    z := Thing\\Base()
		    z.tag = Sub
		    z.tag.@type_names.0
		CODE
		assert_equal 'Sub', out
	end

	def test_tag_reassignment_rejects_a_value_that_does_not_compose_the_current_tag
		assert_raises Disk::Tag_Signature_Violation do
			Drive.interp <<~CODE
			    Base {} Other {}
			    Thing\\Base {}
			    z := Thing\\Base()
			    z.tag = Other
			CODE
		end
	end

	# `.tag` is only writable on a value whose type was declared with a tag.
	def test_tag_reassignment_on_untagged_type_raises_undeclared
		assert_raises Disk::Cannot_Assign_Undeclared_Identifier do
			Drive.interp <<~CODE
			    Thingy {}
			    t := Thingy()
			    t.tag = 5
			CODE
		end
	end

	# Struct Composition -- `Both | Abc | Def <extra: ...>` composes Bare Named Structs the same way `Type | Other {}` composes Types, with `<...>` playing the role `{}` plays for a type declaration.

	def test_parses_struct_composition_trailing_body
		out = Drive.parse 'Both | Abc | Def <>'
		expr = out.first
		assert_kind_of Disk::Type_Expr, expr
		assert_equal 'Both', expr.name
		refute expr.anonymous_composition
		assert_kind_of Disk::Struct_Expr, expr.struct_body
		assert_equal [], expr.struct_body.names
		assert_equal 2, expr.expressions.length
	end

	def test_parses_struct_composition_with_own_extra_members
		out = Drive.parse 'Both2 | Abc <my_own: String>'
		expr = out.first
		assert_equal ['my_own'], expr.struct_body.names
		assert_equal %w(String), expr.struct_body.types.map { |member| member.type.value }
	end

	# A trailing `<` after a composition chain that doesn't actually parse as a struct member list falls back to an ordinary comparison, same ambiguity #try_parse_struct already resolves for a bare `Ident <...>`.
	def test_composition_followed_by_real_comparison_still_parses_as_comparison
		out = Drive.parse 'x := A | B < 5'
		infix = out.first.right
		assert_kind_of Disk::Infix_Expr, infix
		assert_equal '<', infix.operator.value
	end

	def test_struct_composition_union_merges_members_from_both_operands
		out = Drive.interp <<~CODE
		    Abc <abc: Int>
		    Def <def: String>
		    Both | Abc | Def <>
		    b := Both(1, 'hi')
		    (b.abc, b.def)
		CODE
		assert_equal [1, 'hi'], out.values
	end

	def test_struct_composition_with_own_extra_members
		out = Drive.interp <<~CODE
		    Abc <abc: Int>
		    Both2 | Abc <my_own: String>
		    b := Both2(1, 'yo')
		    (b.abc, b.my_own)
		CODE
		assert_equal [1, 'yo'], out.values
	end

	# A member whose *name* collides with a reflective struct key (`types`, `names`, `type_names`,
	# `values`) used to make `Struct#type_objects` return nil -- it read `@declarations['types']`,
	# which the member's own declaration had overwritten -- and struct composition then crashed on
	# `own.type_objects[i]`. Per-member data is now a plain ivar, immune to the name shadowing.
	def test_struct_with_a_member_named_like_a_reflective_key
		out = Drive.interp <<~CODE
		    Schema <types: Array, names: Array, declared_name: String>
		    s := Schema
		    s.@type_names
		CODE
		assert_equal %w(Array Array String), out.values
	end

	def test_struct_composition_with_a_member_named_like_a_reflective_key
		out = Drive.interp <<~CODE
		    Node <lexemes: Array>
		    Schema | Node <types: Array, names: Array>
		    Schema.@type_names
		CODE
		assert_equal %w(Array Array Array), out.values
	end

	def test_struct_composition_union_leftmost_operand_wins_a_name_collision
		out = Drive.interp <<~CODE
		    Abc <abc: Int, shared: String>
		    Def <def: String, shared: String>
		    U | Abc | Def <>
		    u := U(1, 'left-shared', 'right-only')
		    (u.abc, u.shared, u.def)
		CODE
		assert_equal [1, 'left-shared', 'right-only'], out.values
	end

	# Own declared members always win, even over a name a composed operand already claimed -- the struct-composition counterpart of a type's own `{}` body always overwriting anything pulled in via composition.
	def test_struct_composition_own_members_win_over_composed_members
		out = Drive.interp <<~CODE
		    Abc <shared: Int>
		    Both3 | Abc <shared: String>
		    b := Both3('mine')
		    b.shared
		CODE
		assert_equal 'mine', out
	end

	def test_struct_composition_intersection_keeps_only_shared_members
		out = Drive.interp <<~CODE
		    Abc <abc: Int, shared: String>
		    Def <def: String, shared: String>
		    I | Abc & Def <>
		    i := I('only-shared')
		    i.shared
		CODE
		assert_equal 'only-shared', out
	end

	def test_struct_composition_difference_removes_the_operands_members
		out = Drive.interp <<~CODE
		    Abc <abc: Int, shared: String>
		    Def <def: String, shared: String>
		    D | Abc ~ Def <>
		    d := D(1)
		    d.abc
		CODE
		assert_equal 1, out
	end

	def test_struct_composition_symmetric_difference_keeps_only_unique_members
		out = Drive.interp <<~CODE
		    Abc <abc: Int, shared: String>
		    Def <def: String, shared: String>
		    S | Abc ^ Def <>
		    s := S(1, 'unique-def')
		    (s.abc, s.def)
		CODE
		assert_equal [1, 'unique-def'], out.values
	end

	def test_struct_composition_result_is_a_real_bare_named_struct
		out = Drive.interp <<~CODE
		    Abc <abc: Int>
		    Def <def: String>
		    Both | Abc | Def <>
		    b := Both(1, 'hi')
		    (b === Both, Both.@name)
		CODE
		assert_equal [true, 'Both'], out.values
	end

	def test_struct_composition_operand_that_is_not_a_struct_raises
		assert_raises Disk::Invalid_Composition_With_A_Non_Struct_type do
			Drive.interp <<~CODE
			    Abc <abc: Int>
			    Real_Type {}
			    Bad | Abc | Real_Type <>
			CODE
		end
	end

	# Redeclaring the identical struct composition a second time is a no-op, same as a plain Bare Named Struct -- both funnel through the same #register_bare_named_struct.
	def test_redeclaring_same_struct_composition_is_a_no_op
		refute_raises do
			out = Drive.interp <<~CODE
			    Abc <abc: Int>
			    Def <def: String>
			    Both | Abc | Def <>
			    Both | Abc | Def <>
			    Both.@name
			CODE
			assert_equal 'Both', out
		end
	end

	# Positional `.N` dot-index -- same mechanism Array/Tuple already use (#array_index_value only ever needs `.values`, which every Disk::Struct already has), so it works unchanged for a struct too.

	def test_struct_positional_index_on_an_instance
		out = Drive.interp "s := <'a', 'b'>
		s.0"
		assert_equal 'a', out
	end

	def test_struct_positional_index_on_an_anonymous_unnamed_literal
		out = Drive.interp '<123>.0'
		assert_equal 123, out
	end

	def test_struct_positional_index_on_a_named_member_literal
		out = Drive.interp '<a := 456>.0'
		assert_equal 456, out
	end

	# A typed-only member with no value supplied (a schema declaration, not real data) is still a valid, in-bounds index -- just nil, same as any other unset member.
	def test_struct_positional_index_on_a_typed_only_member_is_nil
		out = Drive.interp '<id: Int>.0'
		assert_nil out
	end

	def test_struct_positional_index_out_of_bounds_raises
		assert_raises Disk::Invalid_Array_Index do
			Drive.interp '<1, 2>.5'
		end
	end

	# Named/reflective access must still fall through to ordinary member lookup, unaffected by the new numeric-index dispatch.
	def test_struct_named_member_access_still_works_alongside_positional_index
		out = Drive.interp "s := <a := 456>
		(s.0, s.a)"
		assert_equal [456, 456], out.values
	end
end
