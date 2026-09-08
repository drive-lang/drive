require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'
require 'net/http'
require 'uri'
require 'sequel'
require 'securerandom'

class Database_Test < Base_Test
	DATABASE = "@load 'tapes/database.tape'"
	RECORD   = "@load 'tapes/table.tape'"

	def before_setup
		@filepath = "./temp#{SecureRandom.hex}.db"
		File.delete(@filepath) if File.exist? @filepath
	end

	def after_teardown
		File.delete(@filepath) if File.exist? @filepath
	end

	def test_database_instance
		out = Drive.interp <<~TAPE
		    #{DATABASE}
			db := Database()
		    sq := Sqlite('#{@filepath}')
			(db, sq)
		TAPE
		assert_instance_of Tape::Database, out.values.first
		assert_instance_of Tape::Database, out.values.last

		assert_nil out.values.first.get 'adapter'
		assert_nil out.values.first.get 'url'
		assert_nil out.values.first.get 'connection'
		assert_nil out.values.last.get 'connection'

		# These are set in Sqlite.Self(;)
		refute_nil out.values.last.get 'adapter'
		refute_nil out.values.last.get 'url'
	end

	def test_database_connection_instance
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Sqlite('#{@filepath}')
		    @connect db
			db.connection
		TAPE
		refute_nil out
		assert_instance_of Sequel::SQLite::Database, out
	end

	def test_database_connection_is_cached
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Sqlite('#{@filepath}')
		    c1 := @connect db
		    c2 := @connect db
		    (c1, c2)
		TAPE
		assert_equal out.values[0].object_id, out.values[1].object_id
	end

	def test_connect_directive_creates_database_connection
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Sqlite('#{@filepath}')
			db.connection
		TAPE
		assert_nil out

		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Sqlite('#{@filepath}')
			@connect db
			db.connection
		TAPE
		assert_instance_of Sequel::SQLite::Database, out
	end

	def test_creating_table
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Sqlite('#{@filepath}')
			@connect db

			User <id: Primary_Key>

			pre_tables := db.tables()
			db.create_table(User)
			post_tables := db.tables()

			(pre_tables, post_tables)
		TAPE
		assert_equal [[], [:users]], out.values.map { |tape_array| tape_array.get('values') }
	end

	def test_record_database_reference
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			User <
				id: Primary_Key
				name: String
			>
			user := db.find_or_create_table(User)

			none := user.all()
			cooper := user.create(<name := 'Cooper'>)

			luna := user.create(<name := 'Luna'>)

			users := user.all()
			(none, users, cooper, luna, db.table_exists?(User))
		TAPE
		assert_equal 0, out.values[0].values.count
		assert_equal 2, out.values[1].values.count
		assert_equal [{ id: 1, name: 'Cooper' }, { id: 2, name: 'Luna' }], out.values[1].values.map(&:to_h)
		assert_equal({ id: 1, name: 'Cooper' }, out.values[2].to_h)
		assert_equal({ id: 2, name: 'Luna' }, out.values[3].to_h)
		assert out.values.last
	end

	def test_create_table_column_types
		refute_raises do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')

				Things <
					id: Primary_Key
					label: String
					count: Int
					active: Bool
				>
				db.create_table(Things)
			TAPE
		end
	end

	def test_record_update
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			User <
				id: Primary_Key
				name: String
			>
			user := db.find_or_create_table(User)

			created := user.create(<name := 'Cooper'>)
			user.update(created.id, <name := 'Cooper Updated'>)
			user.find(created.id)
		TAPE
		assert_equal 'Cooper Updated', out.to_h[:name]
	end

	# SQLite has no boolean type -- a Bool column stores 0/1, or NULL when unset. #row_to_struct must
	# coerce it back so `if record.done` behaves; before the fix an unset value read as the truthy
	# Bool *type* and a set one read as a truthy Integer.
	def test_bool_column_round_trips_as_a_usable_boolean
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Task <
				id: Primary_Key
				done := false
				text: String
			>
			tasks := db.find_or_create_table(Task)
			tasks.create(<text := 'a'>)
			tasks.create(<text := 'b', done := true>)

			unset := tasks.find(1)
			set   := tasks.find(2)

			marks := []
			unless unset.done
				marks << 'unset-falsy'
			end
			if set.done
				marks << 'set-truthy'
			end
			marks
		TAPE
		assert_equal ['unset-falsy', 'set-truthy'], out.values
	end

	def test_record_find_by
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			User <
				id: Primary_Key
				name: String
			>
			user := db.find_or_create_table(User)

			user.create(<name := 'Cooper'>)
			user.create(<name := 'Luna'>)
			user.find_by(<name := 'Luna'>)
		TAPE
		assert_equal({ id: 2, name: 'Luna' }, out.to_h)
	end

	def test_record_find_by_returns_nil_when_not_found
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			User <
				id: Primary_Key
				name: String
			>
			user := db.find_or_create_table(User)

			user.find_by(<name := 'nobody'>)
		TAPE
		assert_nil out
	end

	def test_record_where
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Items <
				id: Primary_Key
				name: String
				kind: String
			>
			item := db.find_or_create_table(Items)

			item.create(<name := 'Apple', kind := 'fruit'>)
			item.create(<name := 'Banana', kind := 'fruit'>)
			item.create(<name := 'Carrot', kind := 'vegetable'>)

			item.where(<kind := 'fruit'>)
		TAPE
		assert_equal 2, out.values.count
		assert_equal ['Apple', 'Banana'], out.values.map { |d| d.to_h[:name] }
	end

	def test_find_or_create_table_creates_when_missing
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>

			pre   := db.table_exists?(Widget)
			table := db.find_or_create_table(Widget)
			(pre, db.table_exists?(Widget), table.table_name, table.columns)
		TAPE
		assert_equal false, out.values[0]
		assert_equal true, out.values[1]
		assert_equal 'widgets', out.values[2]
		refute_nil out.values[3]
	end

	def test_find_or_create_table_reuses_existing_table
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>

			first := db.find_or_create_table(Widget)
			first.create(<name := 'A'>)

			second := db.find_or_create_table(Widget)
			(second.table_name, second.all().length())
		TAPE
		assert_equal 'widgets', out.values[0]
		assert_equal 1, out.values[1]
	end

	def test_find_table_by_struct
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>
			db.create_table(Widget)

			table := db.find_table(Widget)
			(table.table_name, table.columns)
		TAPE
		assert_equal 'widgets', out.values[0]
		refute_nil out.values[1]
	end

	def test_find_table_by_name
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')

			Widget <id: Primary_Key>
			db.create_table(Widget)

			db.find_table('widgets').table_name
		TAPE
		assert_equal 'widgets', out
	end

	def test_find_table_returns_nil_when_missing
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')
		    db.find_table('ghosts')
		TAPE
		assert_nil out
	end

	def test_delete_table
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')

			Widget <id: Primary_Key>
			db.create_table(Widget)

			pre := db.table_exists?(Widget)
			db.delete_table!(Widget)
			(pre, db.table_exists?(Widget))
		TAPE
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
	end

	def test_delete_table_by_name_without_the_struct_in_hand
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')

			Widget <id: Primary_Key>
			db.create_table(Widget)

			# No Widget struct in scope here -- delete_table! also takes a bare table-name Symbol,
			# derived independently, so a caller never has to keep the original schema around just to drop it.
			pre := db.table_exists?(:widgets)
			db.delete_table!(:widgets)
			(pre, db.table_exists?(:widgets))
		TAPE
		assert_equal true, out.values[0]
		assert_equal false, out.values[1]
	end

	def test_table_exists_false_for_missing_table
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')
		    Widget <id: Primary_Key>
		    db.table_exists?(Widget)
		TAPE
		assert_equal false, out
	end

	def test_table_exists_by_name
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')

			Widget <id: Primary_Key>
			db.create_table(Widget)

			db.table_exists?(:widgets)
		TAPE
		assert_equal true, out
	end

	def test_tables_lists_every_table
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite('#{@filepath}')

			Widget <id: Primary_Key>
			Gadget <id: Primary_Key>
			db.create_table(Widget)
			db.create_table(Gadget)

			db.tables()
		TAPE
		assert_equal [:widgets, :gadgets], out.values
	end

	def test_database_to_s
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := Database()
		    db.to_s()
		TAPE
		assert_match(/\ADatabase\{\d+\}\z/, out)
	end

	def test_sqlite_memory_does_not_persist_to_disk
		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite.memory()
		    db.url
		TAPE
		assert_equal ':memory:', out
	end

	def sqlite_local_defaults_to_temp_dir # skipping because it requires file system write
		filename = "local_test_#{SecureRandom.hex}"
		filepath = File.expand_path("../.temporary/#{filename}.db", __dir__)
		File.delete(filepath) if File.exist? filepath

		out = Drive.interp <<~TAPE
		    #{DATABASE}
		    db := @connect Sqlite.local('#{filename}')
		    db.url
		TAPE
		assert_equal filepath, out
		assert File.exist?(filepath), 'Sqlite.local should create the db file under .temporary/'
	ensure
		File.delete(filepath) if filepath && File.exist?(filepath)
	end

	def test_table_find_returns_nil_when_missing
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>
			table := db.find_or_create_table(Widget)

			table.find(999)
		TAPE
		assert_nil out
	end

	def test_table_delete
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>
			table := db.find_or_create_table(Widget)

			a := table.create(<name := 'A'>)
			table.create(<name := 'B'>)

			table.delete(a.id)
			(table.all().length(), table.find(a.id))
		TAPE
		assert_equal 1, out.values[0]
		assert_nil out.values[1]
	end

	# --- Drive.assert failure paths ---

	def test_create_table_raises_for_non_struct
		error = assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.create_table('not a struct')
			TAPE
		end
		assert_match(/Expected condition to be truthy/, error.message)
	end

	def test_create_table_raises_for_unnamed_struct
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.create_table(<id: Primary_Key>)
			TAPE
		end
	end

	def test_find_or_create_table_raises_for_unnamed_struct
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.find_or_create_table(<id: Primary_Key>)
			TAPE
		end
	end

	def test_find_table_raises_for_unnamed_struct
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.find_table(<id: Primary_Key>)
			TAPE
		end
	end

	# table_exists?/delete_table! never got their own named-struct assert -- they derive the table name
	# through the same #table_name_for every struct-accepting method shares, so an anonymous struct is
	# caught there instead, one guard covering every caller.
	def test_table_exists_raises_for_unnamed_struct
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.table_exists?(<id: Primary_Key>)
			TAPE
		end
	end

	def test_delete_table_raises_for_unnamed_struct
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')
			    db.delete_table!(<id: Primary_Key>)
			TAPE
		end
	end

	# --- Column types available to create_table ---

	def test_create_table_every_column_type
		# No distinct Drive Flo/Decimal/Blob type exists yet -- alias one yourself, same as the
		# codebase's own `Text | String {}` pattern (see database.rb's #proxy_create_table).
		# Primary_Key/String/Int/Bool/Date/Time/Date_Time/Enum need no aliasing -- all real,
		# provided types.
		refute_raises do
			Drive.interp <<~TAPE
			    #{DATABASE}
			    db := @connect Sqlite('#{@filepath}')

				Flo       | Number {}
				Float     | Number {}
				Decimal   | Number {}
				Blob      | Number {}
				Status [ACTIVE INACTIVE]

				Everything <
					id: Primary_Key
					label: String
					count: Int
					active: Bool
					happened_on: Date
					logged_at: Date_Time
					duration: Time
					ratio: Flo
					percent: Float
					price: Decimal
					attachment: Blob
					status: Status
				>
				db.create_table(Everything)
			TAPE
		end
	end

	# --- Building a Table by hand instead of through Database ---

	def test_table_built_manually_and_linked_to_a_database
		out = Drive.interp <<~TAPE
		    #{DATABASE}, #{RECORD}
		    db := @connect Sqlite('#{@filepath}')

			Widget <
				id: Primary_Key
				name: String
			>
			db.create_table(Widget)

			# No find_table/find_or_create_table here -- Table() built directly, then wired by hand.
			table := Table()
			table.database   = db
			table.table_name = 'widgets'
			table.columns    = Widget

			created := table.create(<name := 'Manual'>)
			(created.name, table.all().length())
		TAPE
		assert_equal 'Manual', out.values[0]
		assert_equal 1, out.values[1]
	end

	# --- create/update are Struct-only, not Dictionary ---

	def test_create_raises_for_dictionary
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}, #{RECORD}
			    db := @connect Sqlite('#{@filepath}')

				Widget <
					id: Primary_Key
					name: String
				>
				table := db.find_or_create_table(Widget)
				table.create({name: 'oops'})
			TAPE
		end
	end

	def test_update_raises_for_dictionary
		assert_raises RuntimeError do
			Drive.interp <<~TAPE
			    #{DATABASE}, #{RECORD}
			    db := @connect Sqlite('#{@filepath}')

				Widget <
					id: Primary_Key
					name: String
				>
				table := db.find_or_create_table(Widget)
				created := table.create(<name := 'A'>)
				table.update(created.id, {name: 'oops'})
			TAPE
		end
	end

	# --- find_by/where filtering on a column the schema doesn't have ---

	def test_find_by_raises_for_unknown_column
		error = assert_raises Tape::Table_Invalid_Filter_Column do
			Drive.interp <<~TAPE
			    #{DATABASE}, #{RECORD}
			    db := @connect Sqlite('#{@filepath}')

				Widget <
					id: Primary_Key
					name: String
				>
				table := db.find_or_create_table(Widget)
				table.create(<name := 'A'>)
				table.find_by(<ghost_column := 'x'>)
			TAPE
		end
		assert_match(/ghost_column/, error.message)
	end

	def test_where_raises_for_unknown_column
		error = assert_raises Tape::Table_Invalid_Filter_Column do
			Drive.interp <<~TAPE
			    #{DATABASE}, #{RECORD}
			    db := @connect Sqlite('#{@filepath}')

				Widget <
					id: Primary_Key
					name: String
				>
				table := db.find_or_create_table(Widget)
				table.create(<name := 'A'>)
				table.where(<ghost_column := 'x'>)
			TAPE
		end
		assert_match(/ghost_column/, error.message)
	end
end
