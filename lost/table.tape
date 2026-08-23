Table {
	database: Database
	columns: Struct
	table_name: String

	Self.all     (; @ruby )
	Self.find    ( id; @ruby )
	Self.find_by ( dict; @ruby )
	Self.where   ( dict; @ruby )
	Self.create  ( dict_or_struct; @ruby )
	Self.update  ( id, dict; @ruby )
	Self.delete  ( id; @ruby )
}

### Tagged Tables
Use these for quick
###
Table\<name: String, columns: Struct> {
	new ( database: Database;
		self.database = database
		self.columns = tag.columns
	)
}


###
	@operator -> @infix ( left,right; left has_one right )
	@operator ->> @infix ( left,right; left has_many right )
	@operator <- @infix ( left,right; right belongs_to left )

	User -> Profile     # user has_one profile
	User ->> Post       # user has_many profiles
	Post <- User        # user belongs_to post
###
