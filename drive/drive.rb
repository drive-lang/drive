require_relative 'shared/constants'

# Drive is the engine (lexer, parser, interpreter, and the other pipeline systems); Disk is the language's runtime vocabulary it operates on: the AST, the scope hierarchy, the built-in value types, the errors, the constants. The engine works directly in that vocabulary, so every Drive pipeline class resolves Disk's names unqualified. The reverse doesn't hold: a Disk file names a pipeline class explicitly (Drive::Interpreter).
module Drive
	VERSION = '0.0.0'
	include Disk
end

require_relative 'shared/helpers'
require_relative 'shared/ascii'
require_relative 'shared/ruby_proxies'
require_relative 'shared/declaration_accessors'
require_relative 'shared/cached_by_path'
require_relative 'shared/error_formatter'
require_relative 'shared/documenter'

# backings/ is the Disk vocabulary: the AST, the scopes, the errors, and the Ruby class behind
# each built-in .disk type. Base types first -- the value types subclass Instance from scopes.
require_relative 'backings/errors'
require_relative 'backings/lexeme'
require_relative 'backings/expressions'
require_relative 'backings/scopes'
require_relative 'backings/func_signature'
require_relative 'backings/return'

require_relative 'backings/string'
require_relative 'backings/array'
require_relative 'backings/range'
require_relative 'backings/set'
require_relative 'backings/dictionary'
require_relative 'backings/number'
require_relative 'backings/file_system'
require_relative 'backings/temporal'
require_relative 'backings/struct'
require_relative 'backings/context'
require_relative 'backings/database'
require_relative 'backings/table'
require_relative 'backings/member'
require_relative 'backings/statement'
require_relative 'backings/enum'

# The pipeline, in run order: 1_lexer -> 2_parser -> 3_type_checker -> 4_declarator -> 5_interpreter.
require_relative '1_lexer/lexer'
require_relative '2_parser/parser'
require_relative '3_type_checker/type_checker'
require_relative '4_declarator/declarator'
require_relative '5_interpreter/dom_renderer'
require_relative '5_interpreter/interpreter'
require_relative '5_interpreter/hot_reloader'

require_relative 'repl'
require_relative 'cli'

module Drive
	ROOT_PATH             = File.expand_path('../', __dir__)
	STANDARD_LIBRARY_PATH = File.join(ROOT_PATH, 'disks', 'global.disk')

	extend Helpers

	def self.interp source_code, load_standard_library: true
		interpreter                       = Interpreter.new
		interpreter.load_standard_library = load_standard_library
		interpreter.run source_code
	end

	def self.interp_file filepath, load_standard_library: true
		source_code                       = File.read filepath
		interpreter                       = Interpreter.new
		interpreter.load_standard_library = load_standard_library
		interpreter.register_source filepath, source_code
		interpreter.run source_code
	end

	def self.parse source_code
		Parser.new(Lexer.new(source_code).output).output
	end

	def self.parse_file filepath
		Parser.new(Lexer.new(File.read(filepath)).output).output
	end

	def self.lex source_code
		Lexer.new(source_code).output
	end

	def self.lex_file filepath
		Lexer.new(File.read(filepath)).output
	end

	def self.declare source_code
		Declarator.new(parse(source_code)).output
	end

	def self.declare_file filepath
		Declarator.new(parse_file(filepath)).output
	end

	def self.type_check_file filepath
		self.type_check File.read(filepath)
	end

	def self.type_check source
		expressions = Drive.parse source
		checker     = Drive::Type_Checker.new expressions
		if checker.output
			raise checker.output
		end
	end
end
