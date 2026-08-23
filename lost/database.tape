@load 'lost/table'

# Marks a struct member as the table's primary key in a `create_table` schema (`id: Primary_Key`) -- see #proxy_create_table (database.rb). Standard/provided, same as `String`/`Bool`/etc: not something you need to declare yourself.
Primary_Key | Int {
	name: String
}

Database {
	adapter: String
	connection, # todo: Make a type for this, currently it stores an Sequel::SQLite::Database instance
	url,

	create_table ( name: String, scheme: Struct -> Table;
		@ruby
	)

	delete_table ( name; @ruby )
	tables (; @ruby )
	table_exists? ( name; @ruby )
}

Sqlite | Database {
	new ( url;
		adapter = 'sqlite'
		self.url = url
	)

	Self.local ( url := './test/fixtures/sqlite_test.db';
		Sqlite(url)
	)

	Self.memory (;
		Sqlite(':memory:')
	)
}
