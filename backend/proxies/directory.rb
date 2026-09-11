module Prog
	class Directory < Instance
		extend Ruby_Proxies
		include Declaration_Accessors

		def proxy_cwd       = ::Dir.pwd
		def proxy_home_path = ::Dir.home

		def proxy_exists? = ::File.directory?(here)
		def proxy_empty?  = ::File.directory?(here) && ::Dir.empty?(here)
		def proxy_name    = Prog::String.new(::File.basename(here))
		def proxy_to_s    = Prog::String.new("Dir(#{here})")

		def proxy_entries  = Prog::Array.new(exists? ? ::Dir.entries(here).sort : [])
		def proxy_names    = Prog::Array.new(child_names)
		def proxy_children = Prog::Array.new(child_paths)
		def proxy_subdirs  = Prog::Array.new(child_paths.select { |p| ::File.directory?(p) })
		def proxy_files    = Prog::Array.new(child_paths.reject { |p| ::File.directory?(p) })

		def proxy_size = bytes(here)

		def proxy_is_dir?(at)  = ::File.directory?(path_arg(at))
		def proxy_is_file?(at) = ::File.file?(path_arg(at))
		def proxy_size_of(at)  = bytes(path_arg(at))

		private

		def here     = path_arg(self.path)
		def exists?  = ::File.directory?(here)
		def path_arg(v) = v.respond_to?(:value) ? v.value : v.to_s

		def child_names = exists? ? ::Dir.children(here).sort : []
		def child_paths = child_names.map { |n| ::File.join(here, n) }

		# Bytes of a file, or the recursive total under a directory. Symlinks are not descended.
		def bytes path
			return 0 unless ::File.exist?(path)
			return ::File.size(path) unless ::File.directory?(path)

			::Dir.children(path).sum do |name|
				child = ::File.join(path, name)
				::File.symlink?(child) ? 0 : bytes(child)
			end
		end
	end
end
