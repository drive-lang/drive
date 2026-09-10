require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

# TYPE_IDENT [ ... ]                    -- bare form (needs a comma / 2+ items / a member form, else it's a subscript)
# TYPE_IDENT: Enum [ ... ]              -- annotated: always an enum, any item count
# TYPE_IDENT: Enum\Backing_Type [ ... ] -- annotated with a backing/value type (rides on `expr.type`)
# TYPE_IDENT: Backing_Type [ ... ]      -- the backing type on its own, no `Enum\` needed
#
#   TYPE_IDENT              # gets its own unique value
#   TYPE_IDENT,             # with comma, also unique'd
#   TYPE_IDENT: TYPE_IDENT
#   TYPE_IDENT := EXPR
#   TYPE_IDENT: TYPE_IDENT = EXPR
class Enums_Test < Base_Test
	def test_empty_enum
		out = Backend.parse <<~CODE
		    My_Enum []
		CODE
		assert_kind_of Prog::Enum_Expr, out.first
		refute out.first.type
		assert_equal 'My_Enum', out.first.name.value
		assert_empty out.first.expressions
	end

	# `NAME: Enum [ ... ]` -- an explicit annotation. Always an enum, whatever the item count.
	def test_annotated_enum_is_always_an_enum_even_with_one_member
		out = Backend.parse 'My_Enum: Enum [ ABC ]'
		assert_kind_of Prog::Enum_Expr, out.first
		assert_equal 'My_Enum', out.first.name.value
		refute out.first.type
		assert_equal 'ABC', out.first.expressions.first.left.value
	end

	# `NAME: Enum\Backing_Type [ ... ]` -- the backing/value type rides on `expr.type`.
	def test_annotated_enum_records_its_backing_type
		out = Backend.parse 'My_Enum: Enum\Int [ ABC, DEF ]'
		assert_kind_of Prog::Enum_Expr, out.first
		assert_equal 'Int', out.first.type.value
	end

	# The backing type can be the annotation on its own -- `NAME: Int [ ... ]`, no `Enum\` needed.
	def test_bare_backing_type_annotation_is_an_enum
		out = Backend.parse 'My_Enum: Int [ ABC ]'
		assert_kind_of Prog::Enum_Expr, out.first
		assert_equal 'Int', out.first.type.value
	end

	# TYPE_IDENT # gets its own unique value. Two members here -- a single bare member (`My_Enum [ ABC ]`)
	# is an ordinary subscript now, see #test_single_bare_member_is_a_subscript below.
	def test_bare_member_gets_its_own_unique_value
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC
		    	DEF
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Nil_Init_Expr, member
		assert_equal 'ABC', member.left.value
	end

	# The deliberate tradeoff for dropping the declared-identifier tracking: bare `NAME [ one_item ]` reads
	# as a subscript. Write a trailing comma, or annotate, to force the one-option enum.
	def test_single_bare_member_is_a_subscript
		out = Backend.parse 'My_Enum [ ABC ]'
		assert_kind_of Prog::Subscript_Expr, out.first
	end

	def test_single_member_with_trailing_comma_is_an_enum
		out = Backend.parse 'My_Enum [ ABC, ]'
		assert_kind_of Prog::Enum_Expr, out.first
		assert_equal 'ABC', out.first.expressions.first.left.value
	end

	# TYPE_IDENT, # with comma -- same shape as the bare form above, comma is just a separator
	def test_member_with_trailing_comma
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC,
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Nil_Init_Expr, member
		assert_equal 'ABC', member.left.value
	end

	# TYPE_IDENT: TYPE_IDENT
	def test_member_with_type_annotation_only
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC: Some_Type
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Identifier_Expr, member
		assert_equal 'ABC', member.value
		assert_equal 'Some_Type', member.type.value
	end

	# TYPE_IDENT := EXPR
	def test_member_with_self_declared_value
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC := 1
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Infix_Expr, member
		assert_equal ':=', member.operator.value
		assert_equal 'ABC', member.left.value
		assert_kind_of Prog::Number_Expr, member.right
		assert_equal 1, member.right.value
	end

	# TYPE_IDENT: TYPE_IDENT = EXPR
	def test_member_with_type_annotation_and_value
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC: Some_Type = 1
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Infix_Expr, member
		assert_equal '=', member.operator.value
		assert_kind_of Prog::Identifier_Expr, member.left
		assert_equal 'ABC', member.left.value
		assert_equal 'Some_Type', member.left.type.value
		assert_kind_of Prog::Number_Expr, member.right
		assert_equal 1, member.right.value
	end

	# A member can be another enum declaration, nested (recursive TYPE_IDENT [ ... ])
	def test_nested_enum_member
		out = Backend.parse <<~CODE
		    My_Enum [
		    	Nested []
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Prog::Enum_Expr, member
		assert_equal 'Nested', member.name.value
		assert_empty member.expressions
	end

	def test_multiple_bare_members
		out = Backend.parse <<~CODE
		    My_Enum [
		    	ABC
		    	DEF
		    ]
		CODE
		assert_equal 2, out.first.expressions.count
		assert_equal 'ABC', out.first.expressions[0].left.value
		assert_equal 'DEF', out.first.expressions[1].left.value
	end

	# `Prog::Enum.new` (no name argument) used to bake "Instance" into @declarations['name'] at construction time; a later `.name =` (a plain Ruby attr write) never touched it, so an enum's own name was permanently wrong. `name` is `@`-only now (`@.name`), read straight off the Ruby-level attr.
	def test_enum_reports_its_own_name_not_the_ruby_default_regression
		out = Backend.interp <<~CODE
		    Task_Type [ TODO, BUG ]
		    Task_Type.@name
		CODE
		assert_equal 'Task_Type', out
	end

	# The same bug, as it actually surfaced: a struct member typed with a user-declared enum displayed its type as "Instance" instead of the real enum name.
	def test_struct_member_typed_with_an_enum_displays_the_real_enum_name_regression
		out = Backend.interp <<~CODE
		    @load 'frontend/struct.prog'
		    Task_Type [ TODO, BUG ]
		    s := <kind: Task_Type = Task_Type.TODO>
		    s.to_s()
		CODE
		assert_equal '<kind: Task_Type = TODO>', out
	end
end
