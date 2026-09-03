require 'minitest/autorun'
require_relative '../src/tape'
require 'net/http'
require 'uri'
require 'timeout'

class E2E_Server_Test < Minitest::Test
	def setup
		@port = 9999 + Random.rand(100) # Random port to avoid conflicts
	end

	def teardown
		if @server_runner && @interpreter
			@interpreter.stop_server @server_runner
			sleep 0.1
		end
	end

	# `#start_server` used to spawn WEBrick in a Thread.new and return immediately, with nothing synchronizing the caller to when WEBrick actually starts listening. Thread.new returns before the new thread has run at all, so `webrick_server.status` was still :Stop right after start_server returned.
	# Interpreter#run's own "did a server start?" check (`servers.any? { status == :Running }`) raced that and tape almost every time, so `bin/tape run`/`@start` would just silently exit instead of staying up. start_server now blocks on a StartCallback until WEBrick is genuinely :Running (or raises if it failed to start), so this must be true with no sleep at all.
	def test_start_server_blocks_until_webrick_is_actually_running_regression
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get:// (; "ok" )
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		assert_equal :Running, @server_runner.webrick_server.status
	end

	def test_server_starts_and_responds
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get:// (;
		    		"Hello from Tape!"
		    	)

		    	get://hello/:name ( name;
		    		"<h1>Hello, `name`!</h1>"
		    	)
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		# Test GET /
		response = Net::HTTP.get_response URI("http://localhost:#{@port}/")
		assert_equal '200', response.code
		assert_equal 'Hello from Tape!', response.body

		# Test parameterized route
		response = Net::HTTP.get_response URI("http://localhost:#{@port}/hello/World")
		assert_equal '200', response.code
		assert_includes response.body, 'Hello, World!'

		# Test 404
		response = Net::HTTP.get_response URI("http://localhost:#{@port}/nonexistent")
		assert_equal '404', response.code
		assert_includes response.body, 'Not Found'
	end

	# A route matching every segment literally wins over one that leaned on a `:param`, regardless of
	# declaration order. This is what makes `tapes/server.tape`'s `get://favicon.ico` route actually
	# shield an app's own `get://:id` from the browser's automatic icon probes.
	def test_literal_route_beats_a_param_route_regardless_of_order
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get://:id ( id; "dynamic `id`" )
		    	get://favicon.ico (; "the literal one" )
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		literal = Net::HTTP.get_response URI("http://localhost:#{@port}/favicon.ico")
		assert_equal '200', literal.code
		assert_equal 'the literal one', literal.body

		# A path with no literal route still reaches the dynamic one.
		dynamic = Net::HTTP.get_response URI("http://localhost:#{@port}/42")
		assert_equal '200', dynamic.code
		assert_equal 'dynamic 42', dynamic.body
	end

	def test_query_parameters
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get://search (;
		    		"Query: `request.query`"
		    	)
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		response = Net::HTTP.get_response URI("http://localhost:#{@port}/search?q=test&page=1")
		assert_equal '200', response.code
		# The response should contain the query params
		assert_includes response.body, 'q'
	end

	def test_post_route
		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	post://submit (;
		    		"Form submitted"
		    	)
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		uri      = URI("http://localhost:#{@port}/submit")
		response = Net::HTTP.post_form uri, {}
		assert_equal '200', response.code
		assert_equal 'Form submitted', response.body
	end

	def test_dialog_and_popover_render_through_a_real_route
		code = <<~TAPE
		    @load 'tapes/html'

		    Server {
		    	port,
		    	new ( port := #{@port};
		    		self.port = port
		    	)
		    }

		    Web_App | Server {
		    	get:// (;
		    		Div([
		    			Button('Open menu', html_popovertarget := 'menu'),
		    			Div([
		    				Button('Close', html_popovertarget := 'menu', html_popovertargetaction := 'hide')
		    			], html_id := 'menu', html_popover := 'auto'),
		    			Dialog([], html_open := true)
		    		])
		    	)
		    }

		    app := Web_App()
		TAPE

		@interpreter    = Tape::Interpreter.new
		server_instance = @interpreter.run code

		@server_runner        = server_instance
		@server_runner.port   = Integer(server_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner.routes = @interpreter.collect_routes_from_instance server_instance
		@interpreter.start_server @server_runner

		response = Net::HTTP.get_response URI("http://localhost:#{@port}/")
		assert_equal '200', response.code
		assert_includes response.body, '<dialog open>', 'a real request must render the boolean-true fix as a bare attribute, not open="true"'
		assert_includes response.body, 'popover="auto"', 'popover keeps its real value, not collapsed to bare'
		assert_includes response.body, 'popovertarget="menu"', 'no hyphen -- this is one real HTML attribute, not popover-target'
		assert_includes response.body, 'popovertargetaction="hide"', 'same no-hyphen shape as popovertarget'
	end

	def test_multiple_servers_with_different_routes
		port_a = @port
		port_b = @port + 1

		code = <<~TAPE
		    Server {
		    	port,
		    	new ( port;
		    		self.port = port
		    	)
		    }

		    Server_A | Server {
		    	get://a (;
		    		"Response from Server A"
		    	)
		    }

		    Server_B | Server {
		    	get://b (;
		    		"Response from Server B"
		    	)
		    }

		    a := Server_A(#{port_a})
		    b := Server_B(#{port_b})
		TAPE

		interpreter = Tape::Interpreter.new
		interpreter.run code

		a_instance = interpreter.stack.first['a']
		b_instance = interpreter.stack.first['b']

		routes_a = interpreter.collect_routes_from_instance a_instance
		routes_b = interpreter.collect_routes_from_instance b_instance

		@server_runner_a        = a_instance
		@server_runner_a.port   = Integer(a_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner_a.routes = routes_a

		@server_runner_b        = b_instance
		@server_runner_b.port   = Integer(b_instance.get(:port) || Tape::Server::DEFAULT_PORT)
		@server_runner_b.routes = routes_b

		interpreter.start_server @server_runner_a
		interpreter.start_server @server_runner_b

		# Server A should respond to /a but not /b
		response_a = Net::HTTP.get_response URI("http://localhost:#{port_a}/a")
		assert_equal '200', response_a.code
		assert_equal 'Response from Server A', response_a.body

		response_a_404 = Net::HTTP.get_response URI("http://localhost:#{port_a}/b")
		assert_equal '404', response_a_404.code

		# Server B should respond to /b but not /a
		response_b = Net::HTTP.get_response URI("http://localhost:#{port_b}/b")
		assert_equal '200', response_b.code
		assert_equal 'Response from Server B', response_b.body

		response_b_404 = Net::HTTP.get_response URI("http://localhost:#{port_b}/a")
		assert_equal '404', response_b_404.code

		interpreter.stop_server @server_runner_a
		interpreter.stop_server @server_runner_b
		@server_runner = nil
	end
end
