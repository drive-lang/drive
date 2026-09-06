require 'set'

module Tape
	class Set < Instance
		extend Ruby_Proxies
		attr_accessor :set

		def initialize _items = nil
			super 'Set'
			@set = ::Set.new
		end

		def to_ruby_set other
			return ::Set.new               if other.nil?
			return other.dup              if other.is_a? ::Set
			return other.set.dup         if other.is_a? Tape::Set
			return ::Set.new(other.values) if other.respond_to? :values
			return ::Set.new(other.to_a)  if other.respond_to?(:to_a) || other.respond_to?(:each)
			Tape.assert false, "Set expected an Array, Range, or Set, got #{other.class.name.split('::').last}"
		end

		# --- mutating primitives (return self, matching Ruby's Set#add/#delete/#merge/#clear) ---

		def proxy_add item
			@set.add item
			self
		end

		def proxy_delete item
			@set.delete item
			self
		end

		def proxy_merge other
			@set.merge to_ruby_set(other)
			self
		end

		def proxy_clear
			@set.clear
			self
		end

		# --- queries ---

		def proxy_length
			@set.size
		end

		def proxy_empty?
			@set.empty?
		end

		# A fresh Array snapshot -- mutating it can't corrupt the Set's own store.
		def proxy_values
			Tape::Array.new @set.to_a
		end

		def proxy_subset? other
			@set.subset? to_ruby_set(other)
		end

		def proxy_superset? other
			@set.superset? to_ruby_set(other)
		end

		def proxy_disjoint? other
			@set.disjoint? to_ruby_set(other)
		end

		def proxy_intersect? other
			@set.intersect? to_ruby_set(other)
		end

		# --- set algebra ---

		def | other
			Tape::Set.new.tap { |s| s.set.replace(@set | to_ruby_set(other)) }
		end

		def & other
			Tape::Set.new.tap { |s| s.set.replace(@set & to_ruby_set(other)) }
		end

		def - other
			Tape::Set.new.tap { |s| s.set.replace(@set - to_ruby_set(other)) }
		end

		def ^ other
			Tape::Set.new.tap { |s| s.set.replace(@set ^ to_ruby_set(other)) }
		end

		def == other
			other.is_a?(Tape::Set) && @set == other.set
		end

		def to_s
			"Set{#{@set.to_a.map(&:to_s).join(', ')}}"
		end
	end
end
