module Lost
	class Table < Instance
		extend Ruby_Proxies

		attr_accessor :connection # to the Sqlite database

		# @return [Lost::Struct]
		attr_accessor :schema

		attr_accessor :table_name

		def initialize name = 'Table'
			super name
		end

		def proxy_infer_table_name_from_class!
			require 'sequel/extensions/inflector.rb'
			first_type = types.to_a.first
			return nil unless first_type
			@declarations['table_name'] = first_type.split('::').last.downcase.pluralize
		end

		# Checked on `self` first (per-instance), then `enclosing_scope` (the older static `Self.database` pattern) -- same own-then-enclosing_scope fallback as #struct_schema below.
		# @return [Lost::Database]
		def database
			@declarations['database'] || enclosing_scope&.declarations&.[]('database')
		end

		# @return [Symbol]
		def table_name
			@declarations['table_name'] ||= proxy_infer_table_name_from_class!

			name = @declarations['table_name'] || enclosing_scope&.declarations&.[]('table_name')
			name&.to_str&.to_sym
		end

		# @return [Sequel::SQLite::Dataset]
		def table
			raise Lost::Database_Not_Set_For_Table_Instance unless database

			database['connection'][table_name]
		end

		def proxy_all
			records = table&.all || []
			Lost::Array.new records.map { |row| record_struct(row) }
		end

		def proxy_find id
			record = table.where(id: id).first
			record ? record_struct(record) : nil
		end

		def proxy_find_by lost_dict
			record = table.where(lost_dict.hash).first
			record ? record_struct(record) : nil
		end

		def proxy_where lost_dict
			records = table.where(lost_dict.hash).all
			Lost::Array.new records.map { |row| record_struct(row) }
		end

		def proxy_create dict_or_struct
			# todo: Return self, or a hash of the inserted row. By default, table#insert returns the id of the inserted row
			id = table.insert record_hash(dict_or_struct)
			proxy_find id
		end

		def proxy_update id, attrs
			table.where(id: id).update record_hash(attrs)
		end

		def proxy_delete id
			table.where(id: id).delete
		end

		# @param dict_or_struct [Lost::Dictionary, Lost::Struct]
		def record_hash dict_or_struct
			return dict_or_struct.hash if dict_or_struct.is_a? Lost::Dictionary

			dict_or_struct.names.zip(dict_or_struct.values).each_with_object({}) do |(name, value), hash|
				next unless name
				hash[name.to_sym] = sql_literal_value(value)
			end
		end

		# Sequel only knows how to literalize plain Ruby values -- an Lost::String struct member value needs unwrapping (Sequel also can't tell it apart from a column/identifier reference the way it can a raw String), and a raw Symbol (an enum member's value, e.g. `:TODO`) is itself already treated as a column/identifier reference rather than a string literal, so it needs converting too.
		def sql_literal_value value
			case value
			when Lost::String then value.value
			when ::Symbol then value.to_s
			else value
			end
		end

		# A tagged composition (`Tasks | Table\<'tasks', Task> {}`) declares `.tag` (a real member, copied onto Tasks at composition time -- see #declare_tag, interpreter.rb) whose `columns` is the model's own schema Struct (`Task`). Checked on `self` first (for an instance call), then `enclosing_scope` (the Type, for a static call, since @declarations is shared with a temp instance built fresh per call -- see #interp_directive's 'ruby' case).
		def struct_schema
			(@declarations['tag'] || enclosing_scope&.declarations&.[]('tag'))&.get('columns')
		end

		# Builds a real, Task-shaped Lost::Struct from a raw SQL row when the model was declared with a schema (see #struct_schema); falls back to a plain Lost::Dictionary otherwise, unchanged from before -- the older `User | Table { Self.database := ~/db }` pattern (no tagged reference) has no schema to shape a Struct from. Goes through Interpreter#build_struct (not a bare Lost::Struct.new) so `.members` gets populated the same way a real struct literal's does -- lost/struct.tape's own `to_s`/`==` read `.members`, not `.names`/`.values` directly.
		def record_struct row
			schema      = struct_schema
			interpreter = Lost::Interpreter.current
			return Lost::Dictionary.new(row) unless schema.is_a?(Lost::Struct) && interpreter

			values = schema.names.map { |name| row[name.to_sym] }
			struct = interpreter.build_struct schema.names, schema.type_names, schema.type_objects, values

			if (schema_name = schema.get('name'))
				struct.name                 = schema_name
				struct.declarations['name'] = schema_name
				struct.types                = schema.types.dup
			end

			struct
		end
	end
end
