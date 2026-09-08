require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

class Pipeline_Test < Base_Test
	def test_interp
		assert_equal 42, Drive::Interpreter.new.run("42")
	end

	def test_lex
		result = Drive::Lexer.new("42").output
		assert_instance_of ::Array, result
		assert_instance_of Tape::Lexeme, result.first
	end

	def test_parse
		lexemes = Drive::Lexer.new("42").output
		result  = Drive::Parser.new(lexemes).output
		assert_instance_of ::Array, result
		assert_instance_of Tape::Number_Expr, result.first
	end

	def test_documenter
		code = <<~CODE
		    # a comment
		    1 + 1 # another comment
		CODE
		lexemes     = Drive::Lexer.new(code).output
		expressions = Drive::Parser.new(lexemes).output
		result      = Drive::Documenter.new(expressions).output
		assert_equal ['a comment', 'another comment'], result.map(&:value)
	end

	def test_type_checker
		lexemes     = Drive::Lexer.new("42").output
		expressions = Drive::Parser.new(lexemes).output
		assert_nil Drive::Type_Checker.new(expressions).output
	end
end
