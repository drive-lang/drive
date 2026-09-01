Table {
	columns: Struct
	database: Database
	table_name: String

	all     (; @ruby)
	find    (pk: Primary_Key; @ruby)
	delete  (pk: Primary_Key; @ruby)
	update  (pk: Primary_Key, struct: Struct; @ruby)
	find_by (struct: Struct; @ruby)
	where   (struct: Struct; @ruby)
	create  (struct: Struct; @ruby)
	count   (; @ruby )
}
