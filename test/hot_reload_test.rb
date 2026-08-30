require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'
require 'timeout'

# The file-watch loop itself (Listen + signal traps + WEBrick lifecycle) is integration territory;
# these cover the interpreter-side primitives Hot_Reloader stands on.
class Hot_Reload_Test < Base_Test
	def teardown
		@interpreter&.shutdown_all_servers
	end

	def server_code port
		<<~TAPE
		    @load 'lost/server'
		    App | Server {
		    	new (; self.port = #{port} )
		    	get:// (; "ok" )
		    }
		    app := App()
		    @start_server app
		TAPE
	end

	def test_serve_in_foreground_false_makes_run_return_instead_of_blocking
		@interpreter                     = Lost::Interpreter.new
		@interpreter.serve_in_foreground = false

		# With the default (true) this call never returns -- it sits in #loop_servers until ^C.
		result = Timeout.timeout(5) { @interpreter.run server_code(9810 + rand(80)) }

		assert_instance_of Lost::Server, result
		assert_equal 1, @interpreter.servers.length
		assert_equal :Running, @interpreter.servers.first.webrick_server.status
	end

	def test_shutdown_all_servers_stops_every_server_and_empties_the_list
		@interpreter                     = Lost::Interpreter.new
		@interpreter.serve_in_foreground = false
		@interpreter.run server_code(9810 + rand(80))
		server = @interpreter.servers.first

		@interpreter.shutdown_all_servers

		assert_empty @interpreter.servers
		refute_equal :Running, server.webrick_server.status
	end

	def test_reset_file_caches_clears_every_parse_cache
		Lost.interp "@load 'test/fixtures/test_module.tape'"
		refute_empty Lost::Interpreter.cached_expressions_by_filepath

		Lost::Interpreter.reset_file_caches!

		assert_empty Lost::Interpreter.cached_expressions_by_filepath
		assert_empty Lost::Interpreter.type_checked_filepaths
		assert_empty Lost::Declarator.cached_declarations_by_filepath
	end

	def test_reset_file_caches_with_paths_only_drops_those_paths
		fixture = File.expand_path 'test/fixtures/test_module.tape'
		Lost.interp "@load 'test/fixtures/test_module.tape'" # caches stdlib + the fixture
		stdlib = Lost::STANDARD_LIBRARY_PATH

		assert Lost::Interpreter.cached_expressions_by_filepath.key?(stdlib)
		assert Lost::Interpreter.cached_expressions_by_filepath.key?(fixture)

		Lost::Interpreter.reset_file_caches! [fixture]

		assert Lost::Interpreter.cached_expressions_by_filepath.key?(stdlib), 'stdlib entry should survive a targeted reset'
		refute Lost::Interpreter.cached_expressions_by_filepath.key?(fixture), 'the named path should be dropped'
	end
end
