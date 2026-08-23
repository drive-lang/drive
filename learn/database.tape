### Introduction

`lost/database.tape` isn't part of the default preload -- it needs an explicit `@load`. `Sqlite` composes with the built-in `Database` type; `':memory:'` opens a database that only lives for this run, so nothing gets left on disk. The static `Self.memory (;)` function is shorthand.
###
@load 'lost/database.tape'

db := Sqlite.memory()
@connect db   # establishes the actual connection


### create_table and table_exists?

A table's schema is a named Struct: one member per column, its own type deciding the column type. `Primary_Key`, used here on `id`, is a small standard/provided marker type (`lost/database.tape`, same as `String`/`Bool`/etc) that marks a member as the table's primary key.
###
Survivors_Schema <
	id: Primary_Key
	name: String
>

db.create_table('survivors', Survivors_Schema)

@assert db.table_exists?('survivors') == true, 'create_table should make the table exist'
@assert db.table_exists?('rafts') == false, 'a table that was never created should not exist'


### tables

Lists every table currently in the database.
###
@assert db.tables() == [:survivors], 'tables should list every table in the database'


### delete_table

Drops a table entirely.
###
db.delete_table('survivors')
@assert db.table_exists?('survivors') == false, 'delete_table should remove the table'
