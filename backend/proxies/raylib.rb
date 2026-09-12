# Implemented by Claude
#
module Prog
	class Raylib < Instance
		def self.lib
			return @lib if defined? @lib

			begin
				require 'raylib'
			rescue LoadError
				raise "Raylib isn't available -- run `gem install raylib-bindings` to use it"
			end

			gem_lib_path = ::Gem::Specification.find_by_name('raylib-bindings').full_gem_path + '/lib/'
			arch         = RUBY_PLATFORM.split('-').first
			extension    = case RUBY_PLATFORM
			when /darwin/ then 'dylib'
			when /linux/ then 'so'
			when /mswin|msys|mingw|cygwin/ then 'dll'
			else raise "Raylib: unsupported platform #{RUBY_PLATFORM}"
			end

			::Raylib.load_lib(
				"#{gem_lib_path}libraylib.#{arch}.#{extension}",
				raygui_libpath: "#{gem_lib_path}raygui.#{arch}.#{extension}",
				physac_libpath: "#{gem_lib_path}physac.#{arch}.#{extension}"
			)
			@lib = ::Raylib
		end

		# --- Window / lifecycle ---

		def proxy_init_window width, height, title
			self.class.lib.InitWindow width, height, title
		end

		def proxy_close_window
			self.class.lib.CloseWindow
		end

		def proxy_window_should_close?
			self.class.lib.WindowShouldClose
		end

		def proxy_set_target_fps fps
			self.class.lib.SetTargetFPS fps
		end

		def proxy_get_frame_time
			self.class.lib.GetFrameTime
		end

		# --- Drawing ---

		def proxy_begin_drawing
			self.class.lib.BeginDrawing
		end

		def proxy_end_drawing
			self.class.lib.EndDrawing
		end

		def proxy_clear_background color
			self.class.lib.ClearBackground rgba(color)
		end

		# --- Shapes ---

		def proxy_draw_circle x, y, radius, color
			self.class.lib.DrawCircle x, y, radius, rgba(color)
		end

		def proxy_draw_circle_lines x, y, radius, color
			self.class.lib.DrawCircleLines x, y, radius, rgba(color)
		end

		def proxy_draw_rectangle x, y, width, height, color
			self.class.lib.DrawRectangle x, y, width, height, rgba(color)
		end

		def proxy_draw_rectangle_lines x, y, width, height, color
			self.class.lib.DrawRectangleLines x, y, width, height, rgba(color)
		end

		def proxy_draw_line x1, y1, x2, y2, color
			self.class.lib.DrawLine x1, y1, x2, y2, rgba(color)
		end

		# --- Text ---

		def proxy_draw_text text, x, y, size, color
			self.class.lib.DrawText text, x, y, size, rgba(color)
		end

		def proxy_measure_text text, size
			self.class.lib.MeasureText text, size
		end

		def proxy_draw_fps x, y
			self.class.lib.DrawFPS x, y
		end

		# --- Textures / Shaders / Render targets ---
		#
		# Texture2D / RenderTexture2D / Shader / Image values are opaque to Backend -- these methods
		# hand back the raw FFI struct raylib itself returns and take it straight back in on the next
		# call, the same way a file handle or socket would flow through untouched. Nothing here wraps
		# them in a Prog:: type; nothing needs to.

		def proxy_load_texture path
			self.class.lib.LoadTexture path
		end

		# A placeholder texture built from a plain color -- no external image file needed. Combines
		# GenImageColor + LoadTextureFromImage; the CPU-side Image is only scratch space for building
		# the GPU texture, so it's unloaded again immediately after. Note: a flat, single-color texture
		# has no internal detail at all, so any UV-shift-based distortion shader (a wave/ripple effect,
		# say) has nothing to visibly displace -- every shifted sample looks identical to the original.
		# Use gen_checked_texture instead when the placeholder needs to actually show that kind of effect.
		def proxy_gen_color_texture width, height, color
			image   = self.class.lib.GenImageColor width, height, rgba(color)
			texture = self.class.lib.LoadTextureFromImage image
			self.class.lib.UnloadImage image
			texture
		end

		# Same idea, but a checkerboard instead of one flat color -- has actual internal detail, so a
		# UV-shift distortion shader visibly displaces it instead of sampling the same color either way.
		def proxy_gen_checked_texture width, height, checks_x, checks_y, color1, color2
			image   = self.class.lib.GenImageChecked width, height, checks_x, checks_y, rgba(color1), rgba(color2)
			texture = self.class.lib.LoadTextureFromImage image
			self.class.lib.UnloadImage image
			texture
		end

		def proxy_load_render_texture width, height
			self.class.lib.LoadRenderTexture width, height
		end

		# The drawable Texture2D backing a render target -- e.g. feeding one pass's output into the
		# next pass as an ordinary texture.
		def proxy_render_texture_texture render_texture
			render_texture.texture
		end

		def proxy_load_shader vertex_path, fragment_path
			self.class.lib.LoadShader vertex_path, fragment_path
		end

		def proxy_get_shader_location shader, name
			self.class.lib.GetShaderLocation shader, name
		end

		# A GLSL shader's uniform (`uniform float u_time;`) can hold more than just
		# a float -- raylib tags every SetShaderValue call with which one it's writing. Backend's own
		# Raylib.set_shader_value_float only ever writes the SHADER_UNIFORM_FLOAT case (all this demo
		# needs), but here's the full list raylib itself defines (raylib.h's ShaderUniformDataType),
		# for whenever a future shader needs one of the others:
		#
		#   SHADER_UNIFORM_FLOAT        a single float           (GLSL `float`)
		#   SHADER_UNIFORM_VEC2         2 floats                 (GLSL `vec2`)
		#   SHADER_UNIFORM_VEC3         3 floats                 (GLSL `vec3`)
		#   SHADER_UNIFORM_VEC4         4 floats                 (GLSL `vec4`)
		#   SHADER_UNIFORM_INT          a single int             (GLSL `int`)
		#   SHADER_UNIFORM_IVEC2        2 ints                   (GLSL `ivec2`)
		#   SHADER_UNIFORM_IVEC3        3 ints                   (GLSL `ivec3`)
		#   SHADER_UNIFORM_IVEC4        4 ints                   (GLSL `ivec4`)
		#   SHADER_UNIFORM_UINT         a single unsigned int    (GLSL `uint`)
		#   SHADER_UNIFORM_UIVEC2       2 unsigned ints          (GLSL `uivec2`)
		#   SHADER_UNIFORM_UIVEC3       3 unsigned ints          (GLSL `uivec3`)
		#   SHADER_UNIFORM_UIVEC4       4 unsigned ints          (GLSL `uivec4`)
		#   SHADER_UNIFORM_SAMPLER2D    a bound texture unit     (GLSL `sampler2D`)
		#
		def proxy_set_shader_value_float shader, location, value
			pointer = ::FFI::MemoryPointer.new(:float)
			pointer.write_float value
			self.class.lib.SetShaderValue shader, location, pointer, self.class.lib::SHADER_UNIFORM_FLOAT
		end

		# Binds a texture to a `uniform sampler2D` -- for reading a *different* texture than whatever
		# the current draw call's own `texture0` is (e.g. a shader that samples a separately-rendered
		# background to invert it). A real, separate raylib call from SetShaderValue -- it also binds
		# the texture unit, not just writes a value.
		def proxy_set_shader_value_texture shader, location, texture
			self.class.lib.SetShaderValueTexture shader, location, texture
		end

		def proxy_begin_texture_mode render_texture
			self.class.lib.BeginTextureMode render_texture
		end

		def proxy_end_texture_mode
			self.class.lib.EndTextureMode
		end

		def proxy_begin_shader_mode shader
			self.class.lib.BeginShaderMode shader
		end

		def proxy_end_shader_mode
			self.class.lib.EndShaderMode
		end

		def proxy_draw_texture texture, x, y, color
			self.class.lib.DrawTexture texture, x, y, rgba(color)
		end

		# `source`/`dest` are [x, y, width, height] Arrays, `origin` an [x, y] Array -- same "plain
		# Backend Array in, real raylib struct out" boundary conversion as colors get.
		def proxy_draw_texture_pro texture, source, dest, origin, rotation, color
			self.class.lib.DrawTexturePro texture, rectangle(source), rectangle(dest), vector2(origin), rotation, rgba(color)
		end

		def proxy_unload_texture texture
			self.class.lib.UnloadTexture texture
		end

		def proxy_unload_render_texture render_texture
			self.class.lib.UnloadRenderTexture render_texture
		end

		def proxy_unload_shader shader
			self.class.lib.UnloadShader shader
		end

		# --- Input ---

		# @param [::Symbol] key
		def proxy_is_key_down? key
			self.class.lib.IsKeyDown key_code(key)
		end

		# @param [::Symbol] key
		def proxy_is_key_pressed? key
			self.class.lib.IsKeyPressed key_code(key)
		end

		# @param [::Symbol] name
		# @return [::Integer]
		def proxy_key name
			key_code name
		end

		private

		# @param [::Symbol] name
		# @return [::Integer]
		def key_code name
			self.class.lib.const_get "KEY_#{name.to_s.upcase}"
		end

		# @param [Prog::Array | Prog::Struct] collection that responds to &:values
		# @return [::Integer]
		def rgba collection
			r, g, b, a = collection.values
			self.class.lib::Color.from_u8(r, g, b, a || 255)
		end

		# A Backend [x, y, width, height] Array -> a real raylib Rectangle.
		def rectangle collection
			x, y, width, height = collection.values
			self.class.lib::Rectangle.create(x, y, width, height)
		end

		# A Backend [x, y] Array -> a real raylib Vector2.
		def vector2 collection
			x, y = collection.values
			self.class.lib::Vector2.create(x, y)
		end
	end
end
