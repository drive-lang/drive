module Prog
	class File < Instance
		def proxy_read_file_to_string filepath
			Prog::String.new ::File.read(filepath)
		end

		def proxy_write_string_to_file filepath, string
			::File.write filepath, string
		end
	end
end
