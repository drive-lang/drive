require 'sequel'

module Lost
	class Database < Instance
		extend Ruby_Proxies
		include Declaration_Accessors
		include Sequel::Inflections
		# adapter: String
		# connection: Sequel::Sqlite::Database
		# url: String

		def initialize name = 'Database'
			super name
		end

		def table_name_for struct
			Lost.assert struct.get('name'), "table_name_for expects a named struct, got an anonymous one"
			pluralize(underscore(struct.get('name'))).to_sym
		end

		def proxy_find_or_create_table struct
			Lost.assert struct.get('name')

			table = if proxy_table_exists? table_name_for(struct)
				proxy_find_table struct
			else
				proxy_create_table struct
			end
		end

		# Given a named struct
		#   Todo<id: Primary_Key, text: String>
		#
		# creates a table called `todos` where the name is inferred from the name of the struct, hence the requirement for it to be named.
		# @param [Lost::Struct] struct with name
		# @return [Lost::Table] table
		def proxy_create_table struct
			Lost.assert struct.is_a? Lost::Struct
			Lost.assert struct.get('name')

			# It appears that #create_table here doesn't return anything so below this block, I'm forwarding to #find_table which actually builds a Lost::Table
			connection.create_table table_name_for(struct) do
				# Structs can have unnamed members because it's basically linear storage with indices as well as names. To create a table, I want both name and type present, otherwise see ya.
				struct.members.values.each do |member|
					next unless member.name && member.type

					column_name = member.name.to_sym
					case member.type.name
					when 'Primary_Key'
						primary_key column_name
					when 'String', 'Text'
						column column_name, ::String
					when 'Int'
						column column_name, ::Integer
					when 'Number'
						column column_name, ::Numeric
					when 'Bool'
						column column_name, ::TrueClass
						# ####
						# note; no Lost types yet for these below
						# ####
					when 'Date'
						column column_name, ::Date
					when 'Date_Time'
						column column_name, ::DateTime
					when 'Time'
						column column_name, ::Time
					when 'Flt', 'Float'
						column column_name, ::Float
					when 'Decimal'
						column column_name, ::BigDecimal
					when 'Blob', 'Binary'
						column column_name, ::File
					else
						if member.type.is_a? Lost::Enum
							column column_name, ::String
						end
					end

					# todo; Foreign keys need a separate generator method  # blocked on table associations, see todos.md
				end
			end

			proxy_find_table struct
		end

		proxy_overload :find_table,
		               Lost::Struct => :find_table_struct,
		               ::String     => :find_table_named

		# @param [::Symbol] name as symbol
		# @return [Lost::Table] table
		def find_table_named name
			Lost.assert name.is_a? ::String

			# note; `connection[name]` alone is always truthy so you have to explicitly check if the table exists.
			if connection.table_exists? name.to_sym
				table            = Lost::Table.new
				table.table_name = name.to_s
				table.database   = self
				table
			else
				nil
			end
		end

		def find_table_struct struct
			Lost.assert struct.get('name'), "#find_table_struct expects the given struct to be declared with a name."
			table         = find_table_named table_name_for(struct).to_s
			table.columns = struct
			table
		end

		# @param [::Symbol, Lost::Struct] name_or_struct a table name, or a named schema struct to derive one from
		def proxy_delete_table! name_or_struct
			name = name_or_struct.is_a?(Lost::Struct) ? table_name_for(name_or_struct) : name_or_struct
			connection.drop_table name
		end

		# @param [::Symbol, Lost::Struct] name_or_struct a table name, or a named schema struct to derive one from
		def proxy_table_exists? name_or_struct
			name = name_or_struct.is_a?(Lost::Struct) ? table_name_for(name_or_struct) : name_or_struct
			connection.table_exists? name
		end

		def proxy_tables
			Lost::Array.new connection.tables
		end

		def proxy_to_s
			"Database{#{object_id}}"
		end
	end
end
