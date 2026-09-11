module Backend
	class CLI
		include Prog
		INSTRUCTIONS = <<~INST
		    Usage:
		        bundle exec bin/prog <file>          Execute a .prog file and keep running until interrupt
		        bundle exec bin/prog [command]       Run command

		    COMMANDS:
		        run <file>            Execute a .prog file and keep running until interrupt
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
		        prog examples/hello_world.prog -p
		        prog lex "x = 5 + 3" -p
		        prog parsef examples/hello_world.prog -p
		        prog interp "4815" -p
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
				puts "Backend #{VERSION}"
			when '-h', '--help'
				puts INSTRUCTIONS
			when 'repl'
				Backend::REPL.new.run
			when 'check'
				Backend.type_check_file @arg
			when 'lex'
				dump Backend.lex(@arg)
			when 'lexf'
				dump Backend.lex_file(@arg)
			when 'parse'
				dump Backend.parse(@arg)
			when 'parsef'
				dump Backend.parse_file(@arg)
			when 'declare'
				dump Backend.declare(@arg)
			when 'declaref'
				dump Backend.declare_file(@arg)
			when 'interp'
				run_source @arg
			when 'interpf'
				run_source ::File.read(@arg), file: @arg
			when 'interp-nostd'
				run_source @arg, load_standard_library: false
			when 'interpf-nostd'
				run_source ::File.read(@arg), file: @arg, load_standard_library: false
			when 'run'
				hot_reload @arg
			else
				hot_reload @command
			end
		rescue Errno::ENOENT => e
			# The missing file might be the one the CLI was told to run, or one the program itself
			# tried to open (::File.read, @load). Errno::ENOENT names the real path in its
			# message ("... - <path>"); fall back to the CLI argument only if that isn't there.
			missing = e.message.include?(' - ') ? e.message.split(' - ').last : (@arg || @command)
			$stderr.puts "Could not find file `#{missing}`"
			exit 1
		rescue Prog::Error => e
			$stderr.puts e.message
			exit 1
		end

		private

		def dump result
			pp result if @print_output
		end

		def run_source source_code, file: nil, load_standard_library: true
			interpreter                       = Backend::Interpreter.new
			interpreter.load_standard_library = load_standard_library
			interpreter.register_source file, source_code if file
			result = interpreter.run source_code
			puts interpreter.stringify_for_display(result) if @print_output
		end

		def hot_reload filepath
			interpreter, result = Backend::Hot_Reloader.new(filepath).run
			puts interpreter.stringify_for_display(result) if @print_output && interpreter
		end
	end
end
