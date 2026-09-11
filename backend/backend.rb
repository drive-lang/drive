require_relative 'shared/constants'

# Backend is the engine (lexer, parser, interpreter, and the other pipeline systems); Prog is the language's runtime vocabulary it operates on: the AST, the scope hierarchy, the built-in value types, the errors, the constants. The engine works directly in that vocabulary, so every Backend pipeline class resolves Prog's names unqualified. The reverse doesn't hold: a Prog file names a pipeline class explicitly (Backend::Interpreter).
module Backend
	VERSION = '0.0.0'
	include Prog
end

require_relative 'shared/helpers'
require_relative 'shared/ascii'
require_relative 'shared/ruby_proxies'
require_relative 'shared/declaration_accessors'
require_relative 'shared/cached_by_path'
require_relative 'shared/error_formatter'
require_relative 'shared/documenter'

# proxies/ is the Prog vocabulary: the AST, the scopes, the errors, and the Ruby class behind
# each built-in .prog type. Base types first -- the value types subclass Instance from scopes.
require_relative 'proxies/errors'
require_relative 'proxies/lexeme'
require_relative 'proxies/expressions'
require_relative 'proxies/scopes'
require_relative 'proxies/func_signature'
require_relative 'proxies/return'

require_relative 'proxies/string'
require_relative 'proxies/array'
require_relative 'proxies/range'
require_relative 'proxies/set'
require_relative 'proxies/dictionary'
require_relative 'proxies/number'
require_relative 'proxies/file'
require_relative 'proxies/directory'
require_relative 'proxies/temporal'
require_relative 'proxies/struct'
require_relative 'proxies/context'
require_relative 'proxies/database'
require_relative 'proxies/table'
require_relative 'proxies/member'
require_relative 'proxies/statement'
require_relative 'proxies/enum'

require_relative 'lexer/lexer'
require_relative 'parser/parser'
require_relative 'type_checker/type_checker'
require_relative 'declarator/declarator'
require_relative 'interpreter/dom_renderer'
require_relative 'interpreter/interpreter'
require_relative 'interpreter/hot_reloader'

require_relative 'repl'
require_relative 'cli'

module Backend
	ROOT_PATH             = ::File.expand_path('../', __dir__)
	STANDARD_LIBRARY_PATH = ::File.join(ROOT_PATH, 'frontend', 'global.prog')

	extend Helpers

	def self.interp source_code, load_standard_library: true
		interpreter                       = Interpreter.new
		interpreter.load_standard_library = load_standard_library
		interpreter.run source_code
	end

	def self.interp_file filepath, load_standard_library: true
		source_code                       = ::File.read filepath
		interpreter                       = Interpreter.new
		interpreter.load_standard_library = load_standard_library
		interpreter.register_source filepath, source_code
		interpreter.run source_code
	end

	def self.parse source_code
		Parser.new(Lexer.new(source_code).output).output
	end

	def self.parse_file filepath
		Parser.new(Lexer.new(::File.read(filepath)).output).output
	end

	def self.lex source_code
		Lexer.new(source_code).output
	end

	def self.lex_file filepath
		Lexer.new(::File.read(filepath)).output
	end

	def self.declare source_code
		Declarator.new(parse(source_code)).output
	end

	def self.declare_file filepath
		Declarator.new(parse_file(filepath)).output
	end

	def self.type_check_file filepath
		self.type_check ::File.read(filepath)
	end

	def self.type_check source
		expressions = Backend.parse source
		checker     = Backend::Type_Checker.new expressions
		if checker.output
			raise checker.output
		end
	end
end
