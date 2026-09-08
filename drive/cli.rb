module Drive
	class CLI
		include Tape
		INSTRUCTIONS = <<~INST
		    Usage:
		        bundle exec bin/drive <file>          Execute a .tape file and keep running until interrupt
		        bundle exec bin/drive [command]       Run command

		    COMMANDS:
		        run <file>            Execute a .tape file and keep running until interrupt
		        check <file>          Run basic type check on file

		        repl                  Enter repl mode, type code press enter

		        interp <code>         Execute code string
		        interpf <file>        Execute file

		        parse <code>          Show AST for code
		        parsef <file>         Show AST for file

		        declare <code>        Show forward declarations for code
		        declaref <file>       Show forward declarations for file

		        lex <code>            Show lexer tokens for code
		        lexf <file>           Show lexer tokens for file

		        -p                    Print output created by program.
		        -v | --version        Show version number
		        -h | --help           Show help instructions

		    EXAMPLES:
		        drive learn/hello_world.tape -p
		        drive lex "x = 5 + 3" -p
		        drive parsef learn/hello_world.tape -p
		        drive interp "4815" -p
		INST

		def self.run argv
			new(argv).run
		end

		def initialize argv
			@argv         = argv
			@command      = argv[0]
			@arg          = argv[1]
			@print_output = argv.last == '-p'
		end

		def run
			if @argv.empty?
				puts INSTRUCTIONS
				exit 1
			end

			case @command
			when '-v', '--version'
				puts "Drive #{VERSION}"
			when '-h', '--help'
				puts INSTRUCTIONS
			when 'repl'
				Drive::REPL.new.run
			when 'check'
				Drive.type_check_file @arg
			when 'lex'
				dump Drive.lex(@arg)
			when 'lexf'
				dump Drive.lex_file(@arg)
			when 'parse'
				dump Drive.parse(@arg)
			when 'parsef'
				dump Drive.parse_file(@arg)
			when 'declare'
				dump Drive.declare(@arg)
			when 'declaref'
				dump Drive.declare_file(@arg)
			when 'interp'
				run_source @arg
			when 'interpf'
				run_source File.read(@arg), file: @arg
			when 'interp-nostd'
				run_source @arg, load_standard_library: false
			when 'interpf-nostd'
				run_source File.read(@arg), file: @arg, load_standard_library: false
			when 'run'
				hot_reload @arg
			else
				hot_reload @command
			end
		rescue Errno::ENOENT
			$stderr.puts "Could not find file `#{@arg || @command}`"
			exit 1
		rescue Tape::Error => e
			$stderr.puts e.message
			exit 1
		end

		private

		def dump result
			pp result if @print_output
		end

		def run_source source_code, file: nil, load_standard_library: true
			interpreter                       = Drive::Interpreter.new
			interpreter.load_standard_library = load_standard_library
			interpreter.register_source file, source_code if file
			result = interpreter.run source_code
			puts interpreter.stringify_for_display(result) if @print_output
		end

		def hot_reload filepath
			interpreter, result = Drive::Hot_Reloader.new(filepath).run
			puts interpreter.stringify_for_display(result) if @print_output && interpreter
		end
	end
end
