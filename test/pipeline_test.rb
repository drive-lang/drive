require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

class Pipeline_Test < Base_Test
	def test_interp
		assert_equal 42, Tape::Interpreter.new.run("42")
	end

	def test_lex
		result = Tape::Lexer.new("42").output
		assert_instance_of ::Array, result
		assert_instance_of Tape::Lexeme, result.first
	end

	def test_parse
		lexemes = Tape::Lexer.new("42").output
		result  = Tape::Parser.new(lexemes).output
		assert_instance_of ::Array, result
		assert_instance_of Tape::Number_Expr, result.first
	end

	def test_documenter
		code = <<~CODE
		    # a comment
		    1 + 1 # another comment
		CODE
		lexemes     = Tape::Lexer.new(code).output
		expressions = Tape::Parser.new(lexemes).output
		result      = Tape::Documenter.new(expressions).output
		assert_equal ['a comment', 'another comment'], result.map(&:value)
	end

	def test_type_checker
		lexemes     = Tape::Lexer.new("42").output
		expressions = Tape::Parser.new(lexemes).output
		assert_nil Tape::Type_Checker.new(expressions).output
	end
end
