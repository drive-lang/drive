module Lost
	class Database < Instance
		require 'sequel'

		# @return [Sequel::SQLite::Database]
		def connection
			@declarations['connection'] ||= @connection ||= create_connection!
		end

		def create_connection!
			return @connection if @connection

			url = get 'url'
			raise Lost::Url_Not_Set_For_Database_Instance unless url

			# Note: As SQLite is a file-based database, the :host and :port options are ignored, and the :database option should be a path to the file — https://sequel.jeremyevans.net/rdoc/files/doc/opening_databases_rdoc.html#label-sqlite
			db = Sequel.sqlite adapter: 'sqlite', database: url

			@declarations['connection'] = @connection = db
		end

		# old proxy_create_table(name, columns_ore_dict)

		# @param [::String] table_name
		# @param [Lost::Struct] schema
		# @return [Lost::Table] table it created
		def proxy_create_table table_name, schema
			return connection[table_name.to_str.to_sym] if proxy_table_exists? table_name
			raise "proxy_create_table now only takes Struct" unless schema.is_a? Lost::Struct

			# Tags the returned table with its real declared type (`Task\Task_Schema | Table {}`) instead of staying generically `Table`-shaped. Doesn't run the model's own `new(;)` -- only safe via a full tagged reference (`Task\Task_Schema()`).
			model_type = Lost::Interpreter.current&.find_table_type_for_schema schema

			Lost::Table.new.tap do |it|
				it['schema']     = schema
				it['table_name'] = table_name

				if model_type
					# `it['name'] = ` also needed -- Type#initialize bakes the constructor's default name into @declarations['name'] too, so an Lost-level `table.name` dot-read would otherwise still see it stale.
					it.name    = model_type.name
					it.types   = model_type.types
					it['name'] = model_type.name
				end

				it['connection'] = connection.create_table table_name.to_str.to_sym do
					schema.members.values.each do |member|
						next unless member.name && member.type

						column_name = member.name.to_s
						# member.type is the real Lost::Type/Lost::Enum object, not a string -- `.name` is what compares against these literals.
						type_name = member.type.name

						if type_name == 'Primary_Key'
							# Sequel's `primary_key` doesn't take a type, so no String/UUID primary keys yet.
							primary_key member.name.to_sym
							next
						end

						if member.type.is_a? Lost::Enum
							# Any user-declared enum -- stored as text, no per-enum special-casing needed.
							String column_name
							next
						end

						case type_name
						when 'String'
							String column_name
						when 'Text' # no distinct Lost Text type -- alias one yourself (`Text | String {}`)
							String(column_name, text: true)
						when 'Int'
							Integer column_name
						when 'Number'
							Numeric column_name
						when 'Bool'
							TrueClass column_name
						when 'Date'
							Date column_name
						when 'Date_Time'
							DateTime column_name
						when 'Time'
							Time column_name

							# Sequel also supports these, but no real Lost type maps to them yet:
							# when 'Flt', 'Float' then Float column_name     # see design.md
							# when 'Decimal' then BigDecimal column_name     # Number above covers general numeric use
							# when 'Blob', 'Binary' then File column_name    # no Lost binary/file type yet
							# Foreign keys need a separate generator method -- blocked on table associations, see todos.md
						end
					end
				end
			end
		end

		def proxy_delete_table name
			connection.drop_table name.to_str.to_sym
		end

		def proxy_table_exists? table_name
			connection.table_exists? table_name.to_str.to_sym
		end

		def proxy_tables
			Lost::Array.new connection.tables
		end
	end
end
