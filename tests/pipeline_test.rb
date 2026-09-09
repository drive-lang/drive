require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

class Pipeline_Test < Base_Test
	def test_interp
		assert_equal 42, Backend::Interpreter.new.run("42")
	end

	def test_lex
		result = Backend::Lexer.new("42").output
		assert_instance_of ::Array, result
		assert_instance_of Prog::Lexeme, result.first
	end

	def test_parse
		lexemes = Backend::Lexer.new("42").output
		result  = Backend::Parser.new(lexemes).output
		assert_instance_of ::Array, result
		assert_instance_of Prog::Number_Expr, result.first
	end

	def test_documenter
		code = <<~CODE
		    # a comment
		    1 + 1 # another comment
		CODE
		lexemes     = Backend::Lexer.new(code).output
		expressions = Backend::Parser.new(lexemes).output
		result      = Backend::Documenter.new(expressions).output
		assert_equal ['a comment', 'another comment'], result.map(&:value)
	end

	def test_type_checker
		lexemes     = Backend::Lexer.new("42").output
		expressions = Backend::Parser.new(lexemes).output
		assert_nil Backend::Type_Checker.new(expressions).output
	end
end
