### Introduction

`tapes/database.tape` is not part of the default preload. You must `@load` it. `Sqlite` composes with the built-in `Database` type. `':memory:'` opens a database that lives only for this run. This database leaves no file on disk. `Self.memory (;)` is a static function. It is shorthand for `':memory:'`.
###
@load 'tapes/database.tape'

db := Sqlite.memory()
@connect db   # establishes the actual connection


### create_table and table_exists?

A table's schema is a named Struct. Each member is one column. The member's type sets the column's type. `Primary_Key` marks a member as the table's primary key. Here, `id` uses this marker. `Primary_Key` is a small, provided type, like `String` or `Bool` (`tapes/database.tape`).

`table_exists?` and `delete_table!` take that same schema Struct. They also accept a bare table-name Symbol instead, if you do not have the Struct on hand. When given a Struct, each method derives the real table name from the Struct's own name. It makes the name lowercase and plural. So a Struct named `Survivor` maps to the `survivors` table.
###
Survivor <
	id: Primary_Key
	name: String
>

db.create_table(Survivor)

Raft <
	id: Primary_Key
>

@assert db.table_exists?(Survivor) == true, 'create_table should make the table exist'
@assert db.table_exists?(Raft) == false, 'a table that was never created should not exist'


### tables

This method lists every table in the database.
###
@assert db.tables() == [:survivors], 'tables should list every table in the database'


### delete_table!

This method drops a table completely.
###
db.delete_table!(Survivor)
@assert db.table_exists?(Survivor) == false, 'delete_table! should remove the table'
