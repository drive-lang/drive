module Backend
	# Runs a `.prog` entry file and, if it starts a server, keeps the process alive and re-runs the
	# whole file whenever any watched `.prog` changes on prog. Each cycle is a brand-new Interpreter
	# (all instance state reset for free) plus a drop of the class-level lex/parse caches -- no
	# partial state to reconcile. The server's port is reused across reloads.
	#
	# A file that never starts a server behaves exactly as before: run once, return, no watching.
	class Hot_Reloader
		include Prog
		def initialize entry_filepath
			@entry  = File.expand_path entry_filepath
			@events = Queue.new # fed [:change] by Listen and [:shutdown] by the INT/TERM trap
		end

		# @return [[Backend::Interpreter, Object]] the interpreter and its last output, for a one-shot
		#   script; [nil, nil] once a server session ends via ^C.
		def run
			$stdout.sync = true # a watch process should print reload/announce lines as they happen

			loop do
				interpreter, result, error = run_entry
				@is_server_app ||= !!interpreter&.servers&.any?

				unless @is_server_app
					raise error if error
					return [interpreter, result]
				end

				error ? report_error(error) : announce(interpreter)
				install_signal_traps
				start_watching

				case @events.pop.first
				when :shutdown
					interpreter&.shutdown_all_servers
					@listener&.stop
					puts "\n\s\s(V) (;,,;) (V)"
					return [nil, nil]
				when :change
					interpreter&.shutdown_all_servers
					Backend::Interpreter.reset_file_caches!
					puts Prog::Ascii.dim '↻ reloading'
				end
			end
		end

		private

		# @return [[Backend::Interpreter, Object, Exception, nil]]
		def run_entry
			interpreter                     = Backend::Interpreter.new
			interpreter.serve_in_foreground = false # this class owns the wait loop, not Interpreter#run
			interpreter.live_reload         = true  # mount /_backend/live-reload + inject its client script;
			#                                         each cycle's fresh Interpreter carries a new token,
			#                                         which is what tells the browser to refresh

			source = File.read @entry
			interpreter.register_source @entry, source
			interpreter.run source
			[interpreter, interpreter.last_output, nil]
		rescue Prog::Error, Errno::ENOENT => e
			[interpreter, nil, e]
		end

		def announce interpreter
			interpreter.servers.each do |server|
				puts "Backend server `#{server.name}` on http://localhost:#{server.port}"
			end
			puts Prog::Ascii.dim 'watching .prog files — ^C to stop (browser auto-refreshes on save)'
		end

		def report_error error
			$stderr.puts error.message
			$stderr.puts Prog::Ascii.dim 'save a fix to retry'
		end

		def install_signal_traps
			return if @traps_installed
			@traps_installed = true
			# Push from a fresh thread -- Queue#push straight from trap context is not guaranteed safe.
			%w[INT TERM].each do |signal|
				Signal.trap(signal) { Thread.new { @events << [:shutdown] } }
			end
		end

		def start_watching
			return if @listener
			require 'listen'
			@listener = Listen.to(*watch_dirs, only: /\.prog\z/) do |modified, added, removed|
				@events << [:change] unless (modified + added + removed).empty?
			end
			@listener.start
		end

		# The stdlib dir (the user edits `backend/*.prog` too) plus the entry file's own dir when that
		# sits outside it. Listen watches recursively.
		def watch_dirs
			prog_dir  = File.join(Backend::ROOT_PATH, 'frontend')
			entry_dir = File.dirname(@entry)
			dirs      = [prog_dir]
			dirs << entry_dir unless entry_dir == prog_dir || entry_dir.start_with?("#{prog_dir}/")
			dirs
		end
	end
end
