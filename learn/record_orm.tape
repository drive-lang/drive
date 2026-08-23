### Introduction

`Table` (`lost/table.tape`) is an ActiveRecord-style ORM on top of `lost/database.tape` -- see learn/database.tape first if `Sqlite`/`@connect` are new to you. Compose a type with `Table`, point its static `Self.database` at a connected database, and give it a `table_name`.
###
@load 'lost/database.tape'
@load 'lost/table.tape'

db := Sqlite(':memory:')
@connect db

Survivors_Schema <
	id: Primary_Key
	name: String
>

db.create_table('survivors', Survivors_Schema)

Survivor | Table {
	Self.database := ~/db
	table_name := 'survivors'
}


### create and all

`create` inserts a row and returns the created record. `all` fetches every row back as an Array of Dictionaries.
###
jack := Survivor.create({name: 'Jack'})
Survivor.create({name: 'Kate'})

@assert jack == {id: 1, name: 'Jack'}, 'create should return the created record'
@assert Survivor.all() == [{id: 1, name: 'Jack'}, {id: 2, name: 'Kate'}], 'all should fetch every row as an Array of Dictionaries'


### find, find_by, where

`find` looks up by id. `find_by` returns the first row matching a Dictionary of conditions, or nil. `where` returns every matching row.
###
@assert Survivor.find(jack.id) == {id: 1, name: 'Jack'}, 'find should look up a row by id'
@assert Survivor.find_by({name: 'Kate'}) == {id: 2, name: 'Kate'}, 'find_by should return the first row matching the conditions'
@assert Survivor.where({name: 'Jack'}) == [{id: 1, name: 'Jack'}], 'where should return every matching row'


### update and delete

###
Survivor.update(jack.id, {name: 'Jack Shephard'})
@assert Survivor.find(jack.id) == {id: 1, name: 'Jack Shephard'}, 'update should change the row in place'

Survivor.delete(jack.id)
@assert Survivor.all() == [{id: 2, name: 'Kate'}], 'delete should remove the row'
