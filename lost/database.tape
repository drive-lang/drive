@load 'lost/table'

Sequel_Sqlite_Database {}

Primary_Key | Int {
	name: String
}

Database {
	adapter: String
	connection: Sequel_Sqlite_Database
	url: String

	find_or_create_table (struct: Struct -> Table; @ruby )
	create_table (struct: Struct -> Table; @ruby )
	find_table   (by_name_or_struct; @ruby )  # no `-> Table` -- returns nil when the table doesn't exist, same as Table#find_by
	delete_table! (name: Symbol; @ruby )
	table_exists? (name: Symbol -> Bool; @ruby )
 	tables (; @ruby )
	to_s (; @ruby )
}

Sqlite | Database {
	new (url: String;
		adapter = 'sqlite'
		self.url = url
	)

	Self.local (named filename := 'demo.db';
		filename += '.db' unless filename.end_with?('.db')
		path := "`@root`/temp/`filename`"
		Sqlite(path)
	)

	Self.memory (;
		Sqlite(':memory:')
	)
}
