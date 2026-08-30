# Mixin for classes that keep class-level Hash caches keyed by resolved filepath (Interpreter,
# Declarator). Extending this gives each declared cache an initialized ivar, a reader/writer
# accessor, and a slot in #reset_cached_by_path! -- one hook Hot_Reloader can call on a file
# change without knowing which caches exist or where they live.
module Cached_By_Path
	def self.extended base
		base.instance_variable_set :@cached_by_path_names, []
	end

	# Declares one class-level Hash cache. `name` becomes both the ivar and the accessor method,
	# same shape as writing `@name = {}` plus `class << self; attr_accessor :name; end` by hand.
	def cache_by_path name
		instance_variable_set "@#{name}", {}
		singleton_class.attr_accessor name
		@cached_by_path_names << name
	end

	def cached_by_path_names
		@cached_by_path_names
	end

	# Drops every registered cache's entries for the given resolved paths (all entries when
	# `paths` is nil). Generic over whichever caches this particular class declared.
	def reset_cached_by_path! paths = nil
		hashes = cached_by_path_names.map { |name| public_send name }
		if paths
			paths.each { |path| hashes.each { |hash| hash.delete path } }
		else
			hashes.each(&:clear)
		end
	end
end
