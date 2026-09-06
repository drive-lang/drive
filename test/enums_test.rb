require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

# TYPE_IDENT :: (OPTIONAL_FORCED_TYPE_IDENT_FOR_CONSTANTS) {
#
#   TYPE_IDENT              # gets its own unique value
#   TYPE_IDENT,             # with comma, also unique'd
#   TYPE_IDENT: TYPE_IDENT
#   TYPE_IDENT := EXPR
#   TYPE_IDENT: TYPE_IDENT = EXPR
#
# }
class Enums_Test < Base_Test
	def test_empty_enum
		out = Tape.parse <<~CODE
		    My_Enum []
		CODE
		assert_kind_of Tape::Enum_Expr, out.first
		refute out.first.type
		assert_equal 'My_Enum', out.first.name.value
		assert_empty out.first.expressions
	end

	def test_enum_with_forced_type
		out = Tape.parse <<~CODE
		    My_Enum []
		CODE
		assert_kind_of Tape::Enum_Expr, out.first
		assert_equal 'My_Enum', out.first.name.value
		assert_empty out.first.expressions
	end

	# TYPE_IDENT # gets its own unique value
	def test_bare_member_gets_its_own_unique_value
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Nil_Init_Expr, member
		assert_equal 'ABC', member.left.value
	end

	# TYPE_IDENT, # with comma -- same shape as the bare form above, comma is just a separator
	def test_member_with_trailing_comma
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC,
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Nil_Init_Expr, member
		assert_equal 'ABC', member.left.value
	end

	# TYPE_IDENT: TYPE_IDENT
	def test_member_with_type_annotation_only
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC: Some_Type
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Identifier_Expr, member
		assert_equal 'ABC', member.value
		assert_equal 'Some_Type', member.type.value
	end

	# TYPE_IDENT := EXPR
	def test_member_with_self_declared_value
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC := 1
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Infix_Expr, member
		assert_equal ':=', member.operator.value
		assert_equal 'ABC', member.left.value
		assert_kind_of Tape::Number_Expr, member.right
		assert_equal 1, member.right.value
	end

	# TYPE_IDENT: TYPE_IDENT = EXPR
	def test_member_with_type_annotation_and_value
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC: Some_Type = 1
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Infix_Expr, member
		assert_equal '=', member.operator.value
		assert_kind_of Tape::Identifier_Expr, member.left
		assert_equal 'ABC', member.left.value
		assert_equal 'Some_Type', member.left.type.value
		assert_kind_of Tape::Number_Expr, member.right
		assert_equal 1, member.right.value
	end

	# A member can be another enum declaration, nested (recursive TYPE_IDENT [ ... ])
	def test_nested_enum_member
		out = Tape.parse <<~CODE
		    My_Enum [
		    	Nested []
		    ]
		CODE
		member = out.first.expressions.first
		assert_kind_of Tape::Enum_Expr, member
		assert_equal 'Nested', member.name.value
		assert_empty member.expressions
	end

	def test_multiple_bare_members
		out = Tape.parse <<~CODE
		    My_Enum [
		    	ABC
		    	DEF
		    ]
		CODE
		assert_equal 2, out.first.expressions.count
		assert_equal 'ABC', out.first.expressions[0].left.value
		assert_equal 'DEF', out.first.expressions[1].left.value
	end

	# `Tape::Enum.new` (no name argument) used to bake "Instance" into @declarations['name'] at construction time; a later `.name =` (a plain Ruby attr write) never touched it, so an enum's own name was permanently wrong. `name` is `@`-only now (`@.name`), read straight off the Ruby-level attr.
	def test_enum_reports_its_own_name_not_the_ruby_default_regression
		out = Tape.interp <<~CODE
		    Task_Type [ TODO, BUG ]
		    Task_Type.@name
		CODE
		assert_equal 'Task_Type', out
	end

	# The same bug, as it actually surfaced: a struct member typed with a user-declared enum displayed its type as "Instance" instead of the real enum name.
	def test_struct_member_typed_with_an_enum_displays_the_real_enum_name_regression
		out = Tape.interp <<~CODE
		    @load 'tapes/struct.tape'
		    Task_Type [ TODO, BUG ]
		    s := <kind: Task_Type = Task_Type.TODO>
		    s.to_s()
		CODE
		assert_equal '<kind: Task_Type = TODO>', out
	end
end
