module Tape
	class Struct < Instance
		attr_accessor :names, :type_names, :type_objects, :members, :bare_reference_name
		attr_reader   :values

		def initialize names = [], type_names = [], types = [], values = []
			super 'Struct'
			@name = nil
			@names        = names
			@type_names   = type_names
			@type_objects = types || []
			@values       = values.dup

			names.each_with_index do |name, i|
				next unless name
				declare name, values[i], type_names[i]
			end
		end

		# `.member = v` writes go through here (via #declare / Interpreter#assign_dot_member). Keep the
		# positional `@values` snapshot -- what `@.values`, `@.members`, `for`-iteration and `to_h` all
		# read -- in step with `@declarations`, so a struct mutated after construction still reports its
		# current values instead of the ones it was built with.
		def []= key, value
			result = super
			if @names && (i = @names.index(key.to_s))
				@values[i] = value
				if (member = @members&.values&.at(i)).is_a?(Tape::Member)
					member.value      = value
					member['value']   = value
				end
			end
			result
		end

		# Strict equality for declaration-time collision checks (does a variant with this *exact*
		# structure already exist under this base name, so a new `Type\Struct {}` should extend it
		# rather than start a fresh variant?). Two declarations only ever describe the *same*
		# variant if every member's name and type match -- a differently-named member of the same
		# type (`dict:`/`other:`, both `Dictionary`) is a distinct variant, which is the whole point
		# of comparing `names` here too.
		#
		# Order-insensitive once every member is named -- a name (not position) is what identifies a
		# named member everywhere it's actually used (dot access, named construction), so `<a: X, b:
		# Y>` and `<b: Y, a: X>` are the same declaration, just typed in a different order. Falls back
		# to strict positional comparison the moment either side has an unnamed member, where position
		# *is* the member's only identity (positional construction binds by index).
		def structure_declaration_equal? other
			return false unless other.is_a? Struct
			return names == other.names && type_names == other.type_names unless names.all? && other.names.all?

			names.zip(type_names).sort == other.names.zip(other.type_names).sort
		end

		# Loose/compositional match for reference resolution (`Abc<value>()` against a declared
		# `Abc<dict: Dictionary>{}`) -- same set-comparison rules as `=>=` (superset): each supplied
		# value's own candidate type set (its own name plus everything it composes -- computed by the
		# caller via #Interpreter#member_candidate_type_names and passed in here, positionally) must
		# include what this struct declared for that member. A reference never supplies member names
		# (`Woof<'hello', 4815>`, never `Woof<key: 'hello'>`), so only `type_names` is compared here,
		# never `names`.
		def satisfied_by_candidates? candidate_type_lists
			return false unless candidate_type_lists.length == type_names.length

			type_names.each_with_index.all? { |declared_type, i| candidate_type_lists[i].include? declared_type }
		end

		# Named members only, keyed by Symbol -- an unnamed member has no key to hash under, same
		# `next unless name` skip #proxy_create_table already uses. Values are unwrapped just enough
		# for a plain Ruby caller (Sequel's own #where/#insert, primarily -- see Table#proxy_find_by)
		# to use directly: an Tape::String yields its raw ::String, and a raw ::Symbol (an enum
		# member's value, e.g. :TODO) is stringified -- Sequel already treats a bare Symbol as a
		# column/identifier reference, not a literal, so left alone it would build the wrong query.
		# Everything else passes through as-is.
		def to_h
			names.each_with_index.each_with_object({}) do |(name, i), hash|
				next unless name

				value             = values[i]
				hash[name.to_sym] = case value
				when Tape::String then value.value
				when Tape::Bool then value.truthiness
				when Tape::Date, Tape::Time, Tape::Date_Time then value.value
				when ::Symbol then value.to_s
				else value
				end
			end
		end
	end
end
