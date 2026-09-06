module Tape
	class Table < Instance
		extend Ruby_Proxies
		include Declaration_Accessors
		# columns: Struct
		# database: Database
		# table_name: String

		def initialize name = 'Table'
			super name
			declare 'columns', nil
			declare 'database', nil
			declare 'table_name', nil
		end

		def proxy_all
			records = table.all.map { |row| row_to_struct row }
			Tape::Array.new records
		end

		def proxy_find id
			id = id.to_i if id.is_a?(::String)
			Tape.assert id.is_a?(::Numeric), "is actually #{id.inspect}"
			row = table.where(id: id).first
			row_to_struct(row)
		end

		def proxy_find_by struct
			Tape.assert struct.is_a? Tape::Struct
			check_filter_columns! struct
			row = table.where(struct.to_h).first
			row_to_struct(row)
		end

		def proxy_where struct
			Tape.assert struct.is_a? Tape::Struct
			check_filter_columns! struct
			rows = table.where(struct.to_h).all
			Tape::Array.new rows.map { |row| row_to_struct(row) }
		end

		def proxy_create struct
			Tape.assert struct.is_a? Tape::Struct
			id = table.insert struct.to_h
			proxy_find id
		end

		def proxy_update id, struct
			Tape.assert id.is_a? ::Numeric
			Tape.assert struct.is_a? Tape::Struct
			table.where(id: id).update struct.to_h
		end

		def proxy_delete id
			Tape.assert id.is_a? ::Numeric
			table.where(id: id).delete
		end

		def proxy_count
			table.all.count
		end

		def row_to_struct row
			return nil unless row

			values = columns.names.each_index.map do |i|
				coerce_column_value row[columns.names[i].to_sym], columns.type_names[i]
			end
			struct = Tape::Interpreter.current.build_struct columns.names, columns.type_names, columns.type_objects, values

			if (schema_name = columns.name)
				struct.name  = schema_name
				struct.types = columns.types.dup
			end

			struct
		end

		private

		# SQLite has no boolean type -- a Bool column round-trips as 0/1, or NULL when unset. Coerce it
		# back to a plain true/false (the same thing a `true`/`false` literal evaluates to) so
		# `if record.done` and `record.done == true` both behave, instead of a truthy Integer or a nil
		# that Struct init would fill with the Bool type object. Other column types pass through.
		def coerce_column_value raw, type_name
			case type_name
			when 'Bool'
				![nil, 0, 0.0, false, '0', 'f', 'false'].include?(raw)
			when 'Date'
				raw.nil? ? nil : linked_temporal(Tape::Date.new(raw.is_a?(::Date) ? raw : ::Date.parse(raw.to_s)), 'Date')
			when 'Time'
				raw.nil? ? nil : linked_temporal(Tape::Time.new(raw.is_a?(::Time) ? raw : ::Time.parse(raw.to_s)), 'Time')
			when 'Date_Time'
				raw.nil? ? nil : linked_temporal(Tape::Date_Time.new(raw.is_a?(::DateTime) ? raw : ::DateTime.parse(raw.to_s)), 'Date_Time')
			else
				raw
			end
		end

		def linked_temporal instance, type_name
			Tape::Interpreter.current&.link_instance_to_type instance, type_name
			instance
		end

		def table
			raise Tape::Database_Not_Set_For_Table_Instance unless database
			database.connection[table_name.to_sym]
		end

		def check_filter_columns! struct
			known   = columns.names.compact
			unknown = struct.names.compact - known
			return if unknown.empty?

			raise Tape::Table_Invalid_Filter_Column,
			      "#{table_name} has no column(s) named #{unknown.join(', ')} -- known columns: #{known.join(', ')}"
		end

	end
end
