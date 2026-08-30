Table {
	columns: Struct
	database: Database
	table_name: String

	all     (; @ruby)
	find    (id: Primary_Key; @ruby)
	find_by (struct: Struct; @ruby)
	where   (struct: Struct; @ruby)
	create  (struct: Struct; @ruby)
	update  (id: Primary_Key, struct: Struct; @ruby)
	delete  (id: Primary_Key; @ruby)
	count (; @ruby )
}
