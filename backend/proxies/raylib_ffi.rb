# Implemented by Claude
#
# Raw C bindings, hand-rolled straight against the Homebrew-installed `libraylib` -- no pre-made Ruby
# gem in between (compare `backend/proxies/raylib.rb`, which uses the `raylib-bindings` gem for the
# exact same surface). Kept as its own plain module, entirely separate from the `Prog::Raylib_FFI` class
# below -- this module knows nothing about Backend, and `Prog::Raylib_FFI` knows nothing about
# `attach_function`. Same seam `Raylib.lib` / `Prog::Raylib` already keep, just with the FFI layer
# written by hand instead of borrowed from a gem.
#
# Loading (`require 'ffi'`, `extend FFI::Library`, every `attach_function`) is deferred to
# `Raylib_FFI.setup!`, called lazily from `Prog::Raylib_FFI` on first real use -- a machine without the
# `ffi` gem, or without `libraylib` installed, still boots Backend fine.
module Raylib_FFI
	def self.setup!
		return if @loaded

		require 'ffi'
		extend FFI::Library

		# Real struct layout, straight from raylib.h -- four unsigned bytes, not floats. `{...}` here,
		# not `do...end` -- `do...end` binds to the outermost call (`const_set`), not `Class.new`, so
		# `layout` would silently never run and every `.by_value` below would build with no real layout.
		unless const_defined?(:Color)
			const_set :Color, Class.new(FFI::Struct) { layout :r, :uchar, :g, :uchar, :b, :uchar, :a, :uchar } # todo; Study this
		end

		ffi_lib [
			'/opt/homebrew/lib/libraylib.dylib',      # Homebrew, Apple Silicon
			'/usr/local/lib/libraylib.dylib',         # Homebrew, Intel
			'/usr/lib/x86_64-linux-gnu/libraylib.so', # common Linux path
			'raylib',                                 # bare name -- last resort, let dlopen's own search path try
		]

		attach_function :InitWindow, [:int, :int, :string], :void
		attach_function :CloseWindow, [], :void
		attach_function :WindowShouldClose, [], :bool
		attach_function :SetTargetFPS, [:int], :void
		attach_function :GetFrameTime, [], :float

		attach_function :BeginDrawing, [], :void
		attach_function :EndDrawing, [], :void
		attach_function :ClearBackground, [Color.by_value], :void

		# DrawCircle/DrawCircleLines take a *float* radius -- everything else here is plain pixel ints.
		attach_function :DrawCircle, [:int, :int, :float, Color.by_value], :void
		attach_function :DrawCircleLines, [:int, :int, :float, Color.by_value], :void
		attach_function :DrawRectangle, [:int, :int, :int, :int, Color.by_value], :void
		attach_function :DrawRectangleLines, [:int, :int, :int, :int, Color.by_value], :void
		attach_function :DrawLine, [:int, :int, :int, :int, Color.by_value], :void

		attach_function :DrawText, [:string, :int, :int, :int, Color.by_value], :void
		attach_function :MeasureText, [:string, :int], :int
		attach_function :DrawFPS, [:int, :int], :void

		attach_function :IsKeyDown, [:int], :bool
		attach_function :IsKeyPressed, [:int], :bool

		@loaded = true
	end

	# raylib's key codes are compile-time C macros -- the compiled library exports no symbol named
	# `KEY_RIGHT` to look up at runtime, unlike a real function. `Raylib#proxy_key` gets away with a
	# dynamic lookup only because the raylib-bindings gem happens to pre-generate these as real Ruby
	# constants; hand-rolling the binding means hand-copying the table too, straight from raylib.h's
	# own `KEY_*` enum. – Claude
	KEY_CODES = {
		'null' => 0, 'apostrophe' => 39, 'comma' => 44, 'minus' => 45, 'period' => 46, 'slash' => 47,
		'zero' => 48, 'one' => 49, 'two' => 50, 'three' => 51, 'four' => 52, 'five' => 53, 'six' => 54,
		'seven' => 55, 'eight' => 56, 'nine' => 57, 'semicolon' => 59, 'equal' => 61,
		'a' => 65, 'b' => 66, 'c' => 67, 'd' => 68, 'e' => 69, 'f' => 70, 'g' => 71, 'h' => 72, 'i' => 73,
		'j' => 74, 'k' => 75, 'l' => 76, 'm' => 77, 'n' => 78, 'o' => 79, 'p' => 80, 'q' => 81, 'r' => 82,
		's' => 83, 't' => 84, 'u' => 85, 'v' => 86, 'w' => 87, 'x' => 88, 'y' => 89, 'z' => 90,
		'left_bracket' => 91, 'backslash' => 92, 'right_bracket' => 93, 'grave' => 96, 'space' => 32,
		'escape' => 256, 'enter' => 257, 'tab' => 258, 'backspace' => 259, 'insert' => 260, 'delete' => 261,
		'right' => 262, 'left' => 263, 'down' => 264, 'up' => 265,
		'page_up' => 266, 'page_down' => 267, 'home' => 268, 'end' => 269,
		'caps_lock' => 280, 'scroll_lock' => 281, 'num_lock' => 282, 'print_screen' => 283, 'pause' => 284,
		'f1' => 290, 'f2' => 291, 'f3' => 292, 'f4' => 293, 'f5' => 294, 'f6' => 295, 'f7' => 296,
		'f8' => 297, 'f9' => 298, 'f10' => 299, 'f11' => 300, 'f12' => 301,
		'left_shift' => 340, 'left_control' => 341, 'left_alt' => 342, 'left_super' => 343,
		'right_shift' => 344, 'right_control' => 345, 'right_alt' => 346, 'right_super' => 347,
		'kb_menu' => 348,
		'kp_0' => 320, 'kp_1' => 321, 'kp_2' => 322, 'kp_3' => 323, 'kp_4' => 324, 'kp_5' => 325,
		'kp_6' => 326, 'kp_7' => 327, 'kp_8' => 328, 'kp_9' => 329, 'kp_decimal' => 330,
		'kp_divide' => 331, 'kp_multiply' => 332, 'kp_subtract' => 333, 'kp_add' => 334,
		'kp_enter' => 335, 'kp_equal' => 336,
		'back' => 4, 'menu' => 5, 'volume_up' => 24, 'volume_down' => 25,
	}.freeze
end

module Prog
	# Same method surface as Raylib -- two examples of binding an external library side by side. Raylib
	# reaches for the `raylib-bindings` gem; this one hand-rolls the FFI layer straight against the
	# system-installed `libraylib` (Raylib_FFI, above). No per-instance state here either, same
	# reasoning as Raylib -- every `Self.` method runs against a throwaway instance.
	class Raylib_FFI < Instance
		# --- Window / lifecycle ---

		def proxy_init_window width, height, title
			::Raylib_FFI.setup!
			::Raylib_FFI.InitWindow width, height, title
		end

		def proxy_close_window
			::Raylib_FFI.setup!
			::Raylib_FFI.CloseWindow
		end

		def proxy_window_should_close?
			::Raylib_FFI.setup!
			::Raylib_FFI.WindowShouldClose
		end

		def proxy_set_target_fps fps
			::Raylib_FFI.setup!
			::Raylib_FFI.SetTargetFPS fps
		end

		def proxy_get_frame_time
			::Raylib_FFI.setup!
			::Raylib_FFI.GetFrameTime
		end

		# --- Drawing ---

		def proxy_begin_drawing
			::Raylib_FFI.setup!
			::Raylib_FFI.BeginDrawing
		end

		def proxy_end_drawing
			::Raylib_FFI.setup!
			::Raylib_FFI.EndDrawing
		end

		def proxy_clear_background color
			::Raylib_FFI.setup!
			::Raylib_FFI.ClearBackground rgba(color)
		end

		# --- Shapes ---

		def proxy_draw_circle x, y, radius, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawCircle x, y, radius, rgba(color)
		end

		def proxy_draw_circle_lines x, y, radius, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawCircleLines x, y, radius, rgba(color)
		end

		def proxy_draw_rectangle x, y, width, height, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawRectangle x, y, width, height, rgba(color)
		end

		def proxy_draw_rectangle_lines x, y, width, height, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawRectangleLines x, y, width, height, rgba(color)
		end

		def proxy_draw_line x1, y1, x2, y2, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawLine x1, y1, x2, y2, rgba(color)
		end

		# --- Text ---

		def proxy_draw_text text, x, y, size, color
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawText text, x, y, size, rgba(color)
		end

		def proxy_measure_text text, size
			::Raylib_FFI.setup!
			::Raylib_FFI.MeasureText text, size
		end

		def proxy_draw_fps x, y
			::Raylib_FFI.setup!
			::Raylib_FFI.DrawFPS x, y
		end

		# --- Input ---

		# Both take the key by name (`Raylib_FFI.is_key_down? :right`), not the raw raylib integer.
		def proxy_is_key_down? key
			::Raylib_FFI.setup!
			::Raylib_FFI.IsKeyDown key_code(key)
		end

		def proxy_is_key_pressed? key
			::Raylib_FFI.setup!
			::Raylib_FFI.IsKeyPressed key_code(key)
		end

		# `Raylib_FFI.key(:right)` -> the real `KEY_RIGHT` integer, for anywhere the raw code is genuinely
		# needed on its own -- `is_key_down?`/`is_key_pressed?` resolve it internally, no need to call
		# this first just to pass the result straight back in.
		def proxy_key name
			key_code name
		end

		private

		# `:right` / `'right'` -> the real `KEY_RIGHT` integer -- see ::Raylib_FFI::KEY_CODES for why
		# this is a hand-copied table rather than a dynamic lookup off the library itself.
		def key_code name
			::Raylib_FFI::KEY_CODES.fetch name.to_s.downcase
		end

		# A Backend color is a plain [r, g, b, a] (or [r, g, b], alpha defaulting to opaque) Array --
		# converted to raylib's own Color struct right at this boundary, so nothing upstream needs to
		# know raylib's FFI shape exists at all. Same contract as Raylib#rgba, different struct type.
		def rgba color
			r, g, b, a = color.values
			::Raylib_FFI::Color.new.tap do |c|
				c[:r] = r
				c[:g] = g
				c[:b] = b
				c[:a] = a || 255
			end
		end
	end
end
