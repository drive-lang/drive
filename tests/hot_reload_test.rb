require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'
require 'timeout'
require 'net/http'
require 'socket'

# The file-watch loop itself (Listen + signal traps + WEBrick lifecycle) is integration territory;
# these cover the interpreter-side primitives Hot_Reloader stands on.
class Hot_Reload_Test < Base_Test
	def teardown
		@interpreter&.shutdown_all_servers
	end

	def server_code port
		<<~TAPE
		    @load 'tapes/server'
		    App | Server {
		    	Self (; self.port = #{port} )
		    	get:// (; "ok" )
		    }
		    app := App()
		    @start_server app
		TAPE
	end

	def test_serve_in_foreground_false_makes_run_return_instead_of_blocking
		@interpreter                     = Drive::Interpreter.new
		@interpreter.serve_in_foreground = false

		# With the default (true) this call never returns -- it sits in #loop_servers until ^C.
		result = Timeout.timeout(5) { @interpreter.run server_code(9810 + rand(80)) }

		assert_instance_of Tape::Server, result
		assert_equal 1, @interpreter.servers.length
		assert_equal :Running, @interpreter.servers.first.webrick_server.status
	end

	def test_shutdown_all_servers_stops_every_server_and_empties_the_list
		@interpreter                     = Drive::Interpreter.new
		@interpreter.serve_in_foreground = false
		@interpreter.run server_code(9810 + rand(80))
		server = @interpreter.servers.first

		@interpreter.shutdown_all_servers

		assert_empty @interpreter.servers
		refute_equal :Running, server.webrick_server.status
	end

	def test_reset_file_caches_clears_every_parse_cache
		Drive.interp "@load 'tests/fixtures/test_module.tape'"
		refute_empty Drive::Interpreter.cached_expressions_by_filepath

		Drive::Interpreter.reset_file_caches!

		assert_empty Drive::Interpreter.cached_expressions_by_filepath
		assert_empty Drive::Interpreter.type_checked_filepaths
		assert_empty Drive::Declarator.cached_declarations_by_filepath
	end

	# --- live reload (browser auto-refresh) -------------------------------------------------------

	def html_server_code port
		<<~TAPE
		    @load 'tapes/server'
		    App | Server {
		    	Self (; self.port = #{port} )
		    	get:// (; "<html><head></head><body>hi</body></html>" )
		    }
		    app := App()
		    @start_server app
		TAPE
	end

	# Reads a Server-Sent-Events response for `seconds` then returns whatever arrived. Net::HTTP would
	# block forever on the never-ending stream, so this goes straight to a socket.
	def read_sse host, port, path, seconds: 1.5
		socket   = TCPSocket.new host, port
		socket.write "GET #{path} HTTP/1.1\r\nHost: #{host}\r\nConnection: close\r\n\r\n"
		buffer   = +''
		deadline = Time.now + seconds
		while Time.now < deadline
			ready = IO.select [socket], nil, nil, 0.1
			next unless ready
			chunk = socket.read_nonblock 4096, exception: false
			break if chunk == :wait_readable || chunk.nil?
			buffer << chunk
		end
		buffer
	ensure
		socket&.close
	end

	def test_live_reload_defaults_off_and_the_token_is_unique_per_interpreter
		a = Drive::Interpreter.new
		b = Drive::Interpreter.new

		refute a.live_reload, 'live_reload must be opt-in -- a plain interpf run should never stream events'
		refute_nil a.live_reload_token
		refute_equal a.live_reload_token, b.live_reload_token, 'each Interpreter (each hot-reload cycle) needs its own token'
	end

	def test_live_reload_endpoint_streams_the_interpreter_token
		port                             = 9810 + rand(80)
		@interpreter                     = Drive::Interpreter.new
		@interpreter.serve_in_foreground = false
		@interpreter.live_reload         = true
		@interpreter.run html_server_code(port)

		frame = read_sse 'localhost', port, '/_drive/live-reload'

		assert_includes frame, 'text/event-stream'
		assert_includes frame, "data: #{@interpreter.live_reload_token}"
	end

	def test_live_reload_endpoint_is_absent_when_disabled
		port                             = 9810 + rand(80)
		@interpreter                     = Drive::Interpreter.new
		@interpreter.serve_in_foreground = false
		# live_reload left at its default (false)
		@interpreter.run html_server_code(port)

		response = Net::HTTP.get_response 'localhost', '/_drive/live-reload', port

		assert_kind_of Net::HTTPNotFound, response
	end

	def test_client_script_is_injected_only_under_live_reload
		off_port                          = 9810 + rand(80)
		off                               = Drive::Interpreter.new
		off.serve_in_foreground           = false
		off.run html_server_code(off_port)
		off_body = Net::HTTP.get 'localhost', '/', off_port
		off.shutdown_all_servers

		on_port                           = 9810 + rand(80)
		@interpreter                      = Drive::Interpreter.new
		@interpreter.serve_in_foreground  = false
		@interpreter.live_reload          = true
		@interpreter.run html_server_code(on_port)
		on_body = Net::HTTP.get 'localhost', '/', on_port

		refute_includes off_body, '/_drive/live-reload', 'the client must not ship without hot reload'
		assert_includes on_body, "new EventSource('/_drive/live-reload')"
	end

	def test_reset_file_caches_with_paths_only_drops_those_paths
		fixture = File.expand_path 'tests/fixtures/test_module.tape'
		Drive.interp "@load 'tests/fixtures/test_module.tape'" # caches stdlib + the fixture
		stdlib = Drive::STANDARD_LIBRARY_PATH

		assert Drive::Interpreter.cached_expressions_by_filepath.key?(stdlib)
		assert Drive::Interpreter.cached_expressions_by_filepath.key?(fixture)

		Drive::Interpreter.reset_file_caches! [fixture]

		assert Drive::Interpreter.cached_expressions_by_filepath.key?(stdlib), 'stdlib entry should survive a targeted reset'
		refute Drive::Interpreter.cached_expressions_by_filepath.key?(fixture), 'the named path should be dropped'
	end

	# These boot a real WEBrick server (~2s total). CI runs them; locally they're removed outright so
	# the IDE runner doesn't expand a skip block per test -- `CI=1 rake test` includes them.
	CI_ONLY = %i[
		test_serve_in_foreground_false_makes_run_return_instead_of_blocking
		test_shutdown_all_servers_stops_every_server_and_empties_the_list
		test_live_reload_endpoint_streams_the_interpreter_token
		test_live_reload_endpoint_is_absent_when_disabled
		test_client_script_is_injected_only_under_live_reload
	].freeze

	unless ENV['CI']
		CI_ONLY.each { |m| remove_method m } # I don't even want to know it's skipped when running locally.
	end
end
